/**
 * Cloudflare Worker — Orchestrateur Sécurisé des Notifications 9DILI EXPRESS.
 *
 * Principes architecturaux :
 * 1. Zéro Firebase Cloud Functions (100% Spark gratuit côté Firebase).
 * 2. Authentification obligatoire via jeton Firebase Auth ID (Bearer JWT).
 * 3. Validation autoritative de l'état réel de la course dans Firestore avant tout envoi.
 * 4. Protection stricte contre les abus et les doublons (Idempotence).
 * 5. Zéro secret dans l'application cliente ou dans le code Git.
 */

import { authenticateCaller } from './security.js';
import { getAuthoritativeErrand, getUserFcmToken, parseFirestoreFields } from './firestore.js';
import {
  acquireIdempotencyLock,
  commitIdempotency,
  releaseIdempotencyLock,
  processErrandNotificationEvent,
} from './events.js';
import {
  LockStatus,
  acquireDistributedLock,
  commitDistributedLock,
  releaseDistributedLock,
  markDistributedLockAmbiguousTimeout,
} from './distributed_lock.js';
import { getGoogleOAuth2AccessToken, sendFcmHttpV1Message } from './fcm.js';
import {
  dispatchRadarWave,
  advanceRadarWave,
  handleAtomicAssignment,
  handleShopperDecline,
  getRadarState,
  saveRadarState,
  sweepPendingRadarWaves,
} from './radar_service.js';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Content-Type': 'application/json; charset=utf-8',
};

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: CORS_HEADERS,
  });
}

function errorResponse(message, status = 400) {
  return new Response(
    JSON.stringify({
      success: false,
      error: message,
      timestamp: new Date().toISOString(),
    }),
    {
      status,
      headers: CORS_HEADERS,
    }
  );
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // 1. Pré-vol CORS
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: CORS_HEADERS,
      });
    }

    // 2. Healthcheck
    if (url.pathname === '/health' && request.method === 'GET') {
      return jsonResponse({
        status: 'ok',
        service: '9dili-express-notifications-dispatcher',
        environment: env?.ENVIRONMENT || 'production',
        projectId: env?.FIREBASE_PROJECT_ID || 'dili-express',
        timestamp: new Date().toISOString(),
      });
    }

    // 3. Endpoint principal : /api/notify
    if (url.pathname === '/api/notify' && request.method === 'POST') {
      const projectId = env?.FIREBASE_PROJECT_ID || 'dili-express';
      let lockKey = null;

      try {
        // A. Authentification du demandeur via jeton Firebase ID
        const authHeader = request.headers.get('Authorization');
        const skipSignatureVerification =
          env?.ENVIRONMENT === 'test' || env?.SKIP_AUTH_SIGNATURE === 'true';
        const caller = await authenticateCaller(authHeader, projectId, {
          skipSignatureVerification,
        });

        // B. Lecture du corps de requête
        let body;
        try {
          body = await request.json();
        } catch {
          return errorResponse('Corps JSON invalide ou illisible.', 400);
        }

        const { errandId, eventType, idempotencyKey } = body;
        if (!errandId || !eventType) {
          return errorResponse("Champs obligatoires manquants : 'errandId' et 'eventType'.", 400);
        }

        const lockKey = idempotencyKey ? `custom_${idempotencyKey}` : `${errandId}_${eventType}`;
        const ownerId = typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : `owner_${Date.now()}`;
        const callerToken = authHeader && authHeader.startsWith('Bearer ') ? authHeader.substring(7).trim() : null;
        const useDistributed = env?.USE_DISTRIBUTED_LOCK === 'true' || env?.ENVIRONMENT === 'production' || env?.ENVIRONMENT === 'staging';

        let distributedLock = null;

        // C. Contrôle anti-doublon et verrouillage atomique (Distribué Firestore REST ou Isolate Local)
        if (useDistributed) {
          distributedLock = await acquireDistributedLock({
            projectId,
            lockKey,
            ownerId,
            authToken: callerToken,
            customFetcher: env?.__CUSTOM_FETCHER__,
          });

          if (!distributedLock.acquired) {
            return errorResponse(distributedLock.message, 409);
          }
        } else {
          const lock = acquireIdempotencyLock(errandId, eventType, idempotencyKey);
          if (!lock.acquired) {
            return errorResponse(lock.message, 409);
          }
        }

        // Helper pour valider le verrou
        const finalizeLockSuccess = async (msgId = null) => {
          if (distributedLock) {
            await commitDistributedLock({
              projectId,
              lockKey,
              ownerId,
              updateTime: distributedLock.updateTime,
              messageId: msgId,
              authToken: callerToken,
              customFetcher: env?.__CUSTOM_FETCHER__,
            });
          } else {
            commitIdempotency(lockKey);
          }
        };

        // Helper pour libérer le verrou
        const rollbackLockFailure = async (reason = 'failure') => {
          if (distributedLock) {
            await releaseDistributedLock({
              projectId,
              lockKey,
              ownerId,
              updateTime: distributedLock.updateTime,
              errorReason: reason,
              authToken: callerToken,
              customFetcher: env?.__CUSTOM_FETCHER__,
            });
          } else {
            releaseIdempotencyLock(lockKey);
          }
        };

        // D. Vérification de l'état autoritatif dans Firestore
        const errand = await getAuthoritativeErrand(projectId, errandId, callerToken, env?.__CUSTOM_FETCHER__);
        if (!errand) {
          await rollbackLockFailure('errand_not_found');
          return errorResponse(`Course '${errandId}' introuvable dans Firestore.`, 404);
        }

        // E. Validation des règles métier et construction de la charge utile assainie
        let processed;
        try {
          processed = processErrandNotificationEvent(caller.uid, errand, eventType);
        } catch (valErr) {
          await rollbackLockFailure(valErr.message);
          throw valErr;
        }

        // F. Envoi réel FCM si le secret du compte de service est configuré
        let serviceAccount = null;
        if (env?.FIREBASE_SERVICE_ACCOUNT) {
          try {
            serviceAccount = typeof env.FIREBASE_SERVICE_ACCOUNT === 'string'
              ? JSON.parse(env.FIREBASE_SERVICE_ACCOUNT)
              : env.FIREBASE_SERVICE_ACCOUNT;
          } catch {
            await rollbackLockFailure('corrupted_service_account');
            return errorResponse('Secret FIREBASE_SERVICE_ACCOUNT corrompu (JSON invalide).', 500);
          }
        }

        if (serviceAccount) {
          // Échange OAuth2 et dispatch FCM HTTP v1
          const accessToken = await getGoogleOAuth2AccessToken(serviceAccount);

          if (processed.isTopicBroadcast) {
            const fcmRes = await sendFcmHttpV1Message({
              projectId,
              accessToken,
              targetTopic: processed.topicName,
              title: processed.notification.title,
              body: processed.notification.body,
              data: {
                errandId,
                eventType,
              },
            });

            await finalizeLockSuccess(fcmRes.name);
            return jsonResponse({
              success: true,
              delivered: true,
              mode: 'topic_broadcast',
              topic: processed.topicName,
              messageId: fcmRes.name,
            });
          } else {
            // Recherche du jeton FCM du destinataire
            const targetToken = await getUserFcmToken(projectId, processed.recipientUid, accessToken, env?.__CUSTOM_FETCHER__);
            if (!targetToken) {
              await finalizeLockSuccess('recipient_has_no_fcm_token');
              return jsonResponse({
                success: true,
                delivered: false,
                reason: 'recipient_has_no_fcm_token',
                recipientUid: processed.recipientUid,
              });
            }

            try {
              const fcmRes = await sendFcmHttpV1Message({
                projectId,
                accessToken,
                targetFcmToken: targetToken,
                title: processed.notification.title,
                body: processed.notification.body,
                data: {
                  errandId,
                  eventType,
                },
              });

              await finalizeLockSuccess(fcmRes.name);
              return jsonResponse({
                success: true,
                delivered: true,
                mode: 'unicast',
                recipientUid: processed.recipientUid,
                messageId: fcmRes.name,
              });
            } catch (fcmErr) {
              if (fcmErr.isStaleToken) {
                // Jeton expiré ou désinstallé (UNREGISTERED / INVALID_ARGUMENT)
                await finalizeLockSuccess(`stale_token_${fcmErr.errorCode}`);
                return jsonResponse({
                  success: false,
                  delivered: false,
                  staleToken: true,
                  errorCode: fcmErr.errorCode,
                  recipientUid: processed.recipientUid,
                  notice: `Jeton FCM de l'utilisateur ${processed.recipientUid} obsolète (UNREGISTERED). L'application doit renouveler son inscription.`,
                }, 200);
              }

              // Gestion explicite des délais d'attente ambigus
              if (fcmErr.name === 'TimeoutError' || fcmErr.message?.includes('timeout') || fcmErr.message?.includes('abort')) {
                if (distributedLock) {
                  await markDistributedLockAmbiguousTimeout({
                    projectId,
                    lockKey,
                    ownerId,
                    updateTime: distributedLock.updateTime,
                    timeoutError: fcmErr.message,
                    authToken: callerToken,
                    customFetcher: env?.__CUSTOM_FETCHER__,
                  });
                }
                return errorResponse('Délai d\'attente réseau ambigu auprès de FCM. État verrouillé par précaution anti-doublon.', 504);
              }

              await rollbackLockFailure(fcmErr.message);
              throw fcmErr;
            }
          }
        } else {
          // Mode simulation propre et sécurisé lorsque le secret n'a pas encore été injecté
          await finalizeLockSuccess('simulated_success');
          return jsonResponse({
            success: true,
            configured: false,
            simulated: true,
            notice: "Notification validée avec succès par l'état Firestore. Envoi FCM en attente de la configuration du secret FIREBASE_SERVICE_ACCOUNT.",
            details: {
              errandId,
              eventType,
              recipientUid: processed.recipientUid,
              isTopicBroadcast: processed.isTopicBroadcast,
              notification: processed.notification,
            },
          });
        }
      } catch (err) {
        return errorResponse(err.message || 'Erreur interne du Worker.', 400);
      }
    }

    // 4. Radar intelligent : Déclenchement de vague (/api/radar/dispatch)
    if (url.pathname === '/api/radar/dispatch' && request.method === 'POST') {
      const projectId = env?.FIREBASE_PROJECT_ID || 'dili-express';
      try {
        const authHeader = request.headers.get('Authorization');
        const skipSignatureVerification =
          env?.ENVIRONMENT === 'test' || env?.SKIP_AUTH_SIGNATURE === 'true';
        const caller = await authenticateCaller(authHeader, projectId, {
          skipSignatureVerification,
        });

        let body;
        try {
          body = await request.json();
        } catch {
          return errorResponse('Corps JSON invalide.', 400);
        }

        const { errandId, waveNumber = 1, radiusKm, shoppers = [] } = body;
        if (!errandId) {
          return errorResponse("Le champ 'errandId' est obligatoire.", 400);
        }

        const callerToken = authHeader && authHeader.startsWith('Bearer ') ? authHeader.substring(7).trim() : null;
        const result = await dispatchRadarWave({
          projectId,
          errandId,
          callerUid: caller.uid,
          waveNumber,
          radiusKm,
          shoppers,
          authToken: callerToken,
          customFetcher: env?.__CUSTOM_FETCHER__,
          env,
        });

        return jsonResponse(result);
      } catch (err) {
        return errorResponse(err.message || 'Erreur lors de la diffusion du radar.', 400);
      }
    }

    // 5. Radar intelligent : Avancement de vague (/api/radar/next-wave)
    if (url.pathname === '/api/radar/next-wave' && request.method === 'POST') {
      const projectId = env?.FIREBASE_PROJECT_ID || 'dili-express';
      try {
        const authHeader = request.headers.get('Authorization');
        const skipSignatureVerification =
          env?.ENVIRONMENT === 'test' || env?.SKIP_AUTH_SIGNATURE === 'true';
        await authenticateCaller(authHeader, projectId, {
          skipSignatureVerification,
        });

        let body;
        try {
          body = await request.json();
        } catch {
          return errorResponse('Corps JSON invalide.', 400);
        }

        const { errandId, shoppers = [], force = false } = body;
        if (!errandId) {
          return errorResponse("Le champ 'errandId' est obligatoire.", 400);
        }

        const callerToken = authHeader && authHeader.startsWith('Bearer ') ? authHeader.substring(7).trim() : null;
        const result = await advanceRadarWave({
          projectId,
          errandId,
          shoppers,
          force,
          authToken: callerToken,
          customFetcher: env?.__CUSTOM_FETCHER__,
          env,
        });

        return jsonResponse(result);
      } catch (err) {
        return errorResponse(err.message || "Erreur lors de l'avancement de vague.", 400);
      }
    }

    // 6. Radar intelligent : Attribution exclusive atomique (/api/radar/accept)
    if (url.pathname === '/api/radar/accept' && request.method === 'POST') {
      const projectId = env?.FIREBASE_PROJECT_ID || 'dili-express';
      try {
        const authHeader = request.headers.get('Authorization');
        const skipSignatureVerification =
          env?.ENVIRONMENT === 'test' || env?.SKIP_AUTH_SIGNATURE === 'true';
        const caller = await authenticateCaller(authHeader, projectId, {
          skipSignatureVerification,
        });

        let body;
        try {
          body = await request.json();
        } catch {
          return errorResponse('Corps JSON invalide.', 400);
        }

        const { errandId } = body;
        if (!errandId) {
          return errorResponse("Le champ 'errandId' est obligatoire.", 400);
        }

        const callerToken = authHeader && authHeader.startsWith('Bearer ') ? authHeader.substring(7).trim() : null;
        const result = await handleAtomicAssignment({
          projectId,
          errandId,
          shopperUid: caller.uid,
          authToken: callerToken,
          customFetcher: env?.__CUSTOM_FETCHER__,
          env,
        });

        return jsonResponse(result, result.statusCode || 200);
      } catch (err) {
        return errorResponse(err.message || "Erreur lors de l'attribution.", 400);
      }
    }

    // 7. Radar intelligent : Refus individuel (/api/radar/decline)
    if (url.pathname === '/api/radar/decline' && request.method === 'POST') {
      const projectId = env?.FIREBASE_PROJECT_ID || 'dili-express';
      try {
        const authHeader = request.headers.get('Authorization');
        const skipSignatureVerification =
          env?.ENVIRONMENT === 'test' || env?.SKIP_AUTH_SIGNATURE === 'true';
        const caller = await authenticateCaller(authHeader, projectId, {
          skipSignatureVerification,
        });

        let body;
        try {
          body = await request.json();
        } catch {
          return errorResponse('Corps JSON invalide.', 400);
        }

        const { errandId } = body;
        if (!errandId) {
          return errorResponse("Le champ 'errandId' est obligatoire.", 400);
        }

        const callerToken = authHeader && authHeader.startsWith('Bearer ') ? authHeader.substring(7).trim() : null;
        const result = await handleShopperDecline({
          projectId,
          errandId,
          shopperUid: caller.uid,
          authToken: callerToken,
          customFetcher: env?.__CUSTOM_FETCHER__,
        });

        return jsonResponse(result);
      } catch (err) {
        return errorResponse(err.message || 'Erreur lors du refus.', 400);
      }
    }

    // 8. Radar intelligent : Consultation de l'état (/api/radar/status)
    if (url.pathname === '/api/radar/status' && request.method === 'GET') {
      const projectId = env?.FIREBASE_PROJECT_ID || 'dili-express';
      try {
        const authHeader = request.headers.get('Authorization');
        const skipSignatureVerification =
          env?.ENVIRONMENT === 'test' || env?.SKIP_AUTH_SIGNATURE === 'true';
        await authenticateCaller(authHeader, projectId, {
          skipSignatureVerification,
        });

        const errandId = url.searchParams.get('errandId');
        if (!errandId) {
          return errorResponse("Le paramètre 'errandId' est obligatoire.", 400);
        }

        const callerToken = authHeader && authHeader.startsWith('Bearer ') ? authHeader.substring(7).trim() : null;
        const state = await getRadarState(projectId, errandId, callerToken, env?.__CUSTOM_FETCHER__);
        if (!state) {
          return jsonResponse({ exists: false, errandId });
        }
        return jsonResponse({ exists: true, state });
      } catch (err) {
        return errorResponse(err.message || "Erreur lors de la lecture de l'état.", 400);
      }
    }

    return errorResponse('Endpoint introuvable.', 404);
  },

  /**
   * Consommateur Cloudflare Queues pour le déclenchement différé des vagues radar à 15s.
   * Traite les messages asynchrones avec garantie de non-duplication et reprise sur échec.
   */
  async queue(batch, env, ctx) {
    const projectId = env?.FIREBASE_PROJECT_ID || 'dili-express';
    const fetcher = env?.__CUSTOM_FETCHER__ || fetch;
    const results = [];

    for (const msg of batch.messages) {
      const body = msg.body || {};
      const { action, errandId, waveNumber } = body;

      if (action === 'advance_radar_wave' && errandId) {
        try {
          // 1. Lire la course dans Firestore
          const errandUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/errands/${errandId}`;
          const errandRes = await fetcher(errandUrl, { headers: { 'Accept': 'application/json' } });

          if (!errandRes.ok) {
            msg.ack();
            results.push({ errandId, status: 'aborted', reason: 'errand_not_found' });
            continue;
          }

          const errandRaw = await errandRes.json();
          const errand = parseFirestoreFields(errandRaw.fields);

          // Si déjà attribuée ou statut non pending : neutraliser les vagues
          if (errand.status !== 'pending' || (errand.shopperId && errand.shopperId.trim() !== '')) {
            let state = await getRadarState(projectId, errandId, null, fetcher);
            if (state && state.status === 'active') {
              state.status = errand.status === 'cancelled' ? 'cancelled' : 'assigned';
              state.nextWaveDueAt = null;
              await saveRadarState(projectId, errandId, state, null, fetcher);
            }
            msg.ack();
            results.push({ errandId, status: 'stopped', reason: 'errand_no_longer_pending' });
            continue;
          }

          // 2. Contrôle de l'état du radar
          const radarState = await getRadarState(projectId, errandId, null, fetcher);
          if (!radarState || radarState.status !== 'active') {
            msg.ack();
            results.push({ errandId, status: 'stopped', reason: 'radar_not_active' });
            continue;
          }

          // 3. Idempotence : si la vague demandée a déjà été diffusée par un autre canal
          if (waveNumber && radarState.currentWave >= waveNumber) {
            msg.ack();
            results.push({ errandId, status: 'skipped', reason: 'wave_already_advanced' });
            continue;
          }

          // 4. Avancer la vague
          const advanceResult = await advanceRadarWave({
            projectId,
            errandId,
            authToken: null,
            customFetcher: fetcher,
            env,
            nowMs: Date.now(),
            force: true,
          });

          msg.ack();
          results.push({ errandId, status: 'advanced', result: advanceResult });
        } catch (err) {
          console.error(`[Queue Consumer] Erreur avancement vague errandId=${errandId}:`, err);
          if (typeof msg.retry === 'function') {
            msg.retry();
          }
          results.push({ errandId, status: 'retried', error: err.message });
        }
      } else {
        msg.ack();
      }
    }

    return results;
  },

  async scheduled(event, env, ctx) {
    const projectId = env?.FIREBASE_PROJECT_ID || 'dili-express';
    const sweepResult = await sweepPendingRadarWaves({
      projectId,
      env,
      customFetcher: env?.__CUSTOM_FETCHER__,
      nowMs: Date.now(),
    });
    return {
      status: 'scheduled_sweep_complete',
      sweptCount: sweepResult.sweptCount || 0,
      timestamp: new Date().toISOString(),
      details: sweepResult,
    };
  },
};
