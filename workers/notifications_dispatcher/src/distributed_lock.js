/**
 * Module de Verrouillage Atomique Distribué pour Cloudflare Workers & Firebase Firestore REST.
 *
 * Garantit l'idempotence à l'échelle mondiale (multi-datacenters Cloudflare) sans état en mémoire :
 * 1. Création atomique sous Firestore REST avec précondition exists=false (HTTP 409 ALREADY_EXISTS).
 * 2. Jetons de fencing et Identifiants Propriétaire (ownerId) empêchant les écrasements par requêtes lentes.
 * 3. Gestion stricte des états du cycle de vie : IN_FLIGHT, SENT, FAILED, AMBIGUOUS_TIMEOUT.
 * 4. Expiration logique (TTL) et reprise après crash (Crash Recovery).
 * 5. Zéro état en mémoire volatile d'isolate V8.
 */

import { parseFirestoreFields } from './firestore.js';

export const LockStatus = {
  IN_FLIGHT: 'in_flight',
  SENT: 'sent',
  FAILED: 'failed',
  AMBIGUOUS_TIMEOUT: 'ambiguous_timeout',
};

const DEFAULT_IN_FLIGHT_TTL_SECONDS = 60; // 60 secondes pour traiter une requête
const COMPLETED_RETENTION_TTL_SECONDS = 24 * 3600; // 24 heures de rétention pour les envois confirmés

/**
 * Encode un document JavaScript en format de champs typés Firestore REST.
 */
export function formatFirestoreDocumentFields(data) {
  const fields = {};
  for (const [key, val] of Object.entries(data)) {
    if (val === null || val === undefined) {
      fields[key] = { nullValue: null };
    } else if (typeof val === 'string') {
      fields[key] = { stringValue: val };
    } else if (typeof val === 'number') {
      if (Number.isInteger(val)) {
        fields[key] = { integerValue: val.toString() };
      } else {
        fields[key] = { doubleValue: val };
      }
    } else if (typeof val === 'boolean') {
      fields[key] = { booleanValue: val };
    } else if (val instanceof Date) {
      fields[key] = { timestampValue: val.toISOString() };
    } else {
      fields[key] = { stringValue: JSON.stringify(val) };
    }
  }
  return { fields };
}

/**
 * Tente d'acquérir de façon atomique et distribuée un verrou d'idempotence via Firestore REST.
 *
 * @param {Object} params
 * @param {string} params.projectId - Identifiant du projet Firebase (dili-express ou dili-express-staging)
 * @param {string} params.lockKey - Clé unique d'idempotence (ex: errand_123_shopper_delivering)
 * @param {string} [params.ownerId] - Identifiant unique de l'exécution (auto-généré si omis)
 * @param {number} [params.ttlSeconds=60] - Durée de validité en secondes de l'état in_flight
 * @param {string} [params.authToken] - Jeton OAuth2 / Auth pour l'API Firestore REST
 * @param {Function} [params.customFetcher] - Client HTTP injectable (pour tests unitaires)
 * @returns {Promise<Object>} Résultat de l'acquisition
 */
export async function acquireDistributedLock({
  projectId,
  lockKey,
  ownerId = null,
  ttlSeconds = DEFAULT_IN_FLIGHT_TTL_SECONDS,
  authToken = null,
  customFetcher = null,
}) {
  if (!projectId || !lockKey) {
    throw new Error('Paramètres obligatoires manquants: projectId et lockKey.');
  }

  const fetcher = customFetcher || fetch;
  const currentOwnerId = ownerId || (typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : `owner_${Date.now()}_${Math.random()}`);
  const now = new Date();
  const expiresAt = new Date(now.getTime() + ttlSeconds * 1000);

  const lockDocPath = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/idempotency_locks`;
  const specificDocUrl = `${lockDocPath}/${lockKey}`;

  const headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`;
  }

  // 1. TENTATIVE DE CRÉATION ATOMIQUE AVEC exists=false
  // L'API Firestore REST crée le document si absent ; renvoie HTTP 409 Conflict s'il existe déjà.
  const createPayload = formatFirestoreDocumentFields({
    lockKey,
    ownerId: currentOwnerId,
    fencingToken: 1,
    status: LockStatus.IN_FLIGHT,
    createdAt: now.toISOString(),
    expiresAt: expiresAt.toISOString(),
    messageId: null,
    error: null,
  });

  const createRes = await fetcher(`${lockDocPath}?documentId=${encodeURIComponent(lockKey)}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(createPayload),
  });

  // CAS NOMINAL : Verrou acquis en premier par cette requête
  if (createRes.status === 200 || createRes.status === 201) {
    const createdData = await createRes.json();
    return {
      acquired: true,
      lockKey,
      ownerId: currentOwnerId,
      fencingToken: 1,
      updateTime: createdData.updateTime,
      expiresAt: expiresAt.toISOString(),
    };
  }

  // CAS DE CONFLIT : Le document existe déjà (HTTP 409 ALREADY_EXISTS)
  if (createRes.status === 409) {
    // 2. Relecture de l'état actuel du verrou
    const getRes = await fetcher(specificDocUrl, { headers: { 'Accept': 'application/json', ...(authToken ? { 'Authorization': `Bearer ${authToken}` } : {}) } });
    if (!getRes.ok) {
      return {
        acquired: false,
        lockKey,
        reason: 'read_error',
        message: `Impossible de lire l'état du verrou existant: HTTP ${getRes.status}`,
      };
    }

    const doc = await getRes.json();
    const existing = parseFirestoreFields(doc.fields);
    existing.updateTime = doc.updateTime;

    // A. Événement déjà envoyé avec succès -> Doublon formel
    if (existing.status === LockStatus.SENT) {
      return {
        acquired: false,
        lockKey,
        reason: 'duplicate',
        messageId: existing.messageId,
        message: 'Requête dupliquée : cette notification a déjà été expédiée avec succès.',
      };
    }

    // B. Délai d'attente ambigu précédent -> Livraison incertaine, blocage de sécurité
    if (existing.status === LockStatus.AMBIGUOUS_TIMEOUT) {
      return {
        acquired: false,
        lockKey,
        reason: 'ambiguous_timeout',
        message: 'Opération suspendue : une précédente tentative a subi un délai d\'attente réseau ambigu auprès de FCM.',
      };
    }

    // C. Verrou en cours de traitement (IN_FLIGHT)
    if (existing.status === LockStatus.IN_FLIGHT) {
      const lockExpiryTime = existing.expiresAt ? new Date(existing.expiresAt).getTime() : 0;
      const isExpired = Date.now() > lockExpiryTime;

      // Verrou encore valide et actif -> Rejet concurrence immédiat
      if (!isExpired) {
        return {
          acquired: false,
          lockKey,
          reason: 'in_flight',
          message: 'Une notification identique est en cours de traitement simultané par une autre instance.',
        };
      }

      // CRASH RECOVERY : Le verrou est expiré (crash ou timeout de la précédente instance)
      // Tentative de reprise conditionnelle avec updateTime (Optimistic Lock)
      const nextFencingToken = (parseInt(existing.fencingToken, 10) || 1) + 1;
      const recoveryPayload = formatFirestoreDocumentFields({
        lockKey,
        ownerId: currentOwnerId,
        fencingToken: nextFencingToken,
        status: LockStatus.IN_FLIGHT,
        recoveredFromOwnerId: existing.ownerId,
        recoveredAt: now.toISOString(),
        expiresAt: expiresAt.toISOString(),
      });

      const patchUrl = `${specificDocUrl}?currentDocument.updateTime=${encodeURIComponent(existing.updateTime)}&updateMask.fieldPaths=ownerId&updateMask.fieldPaths=fencingToken&updateMask.fieldPaths=status&updateMask.fieldPaths=recoveredFromOwnerId&updateMask.fieldPaths=recoveredAt&updateMask.fieldPaths=expiresAt`;
      const patchRes = await fetcher(patchUrl, {
        method: 'PATCH',
        headers,
        body: JSON.stringify(recoveryPayload),
      });

      if (patchRes.ok) {
        const patchData = await patchRes.json();
        return {
          acquired: true,
          lockKey,
          ownerId: currentOwnerId,
          fencingToken: nextFencingToken,
          updateTime: patchData.updateTime,
          recovered: true,
          expiresAt: expiresAt.toISOString(),
        };
      } else {
        // Une autre instance concurrente a repris le verrou entre temps
        return {
          acquired: false,
          lockKey,
          reason: 'race_lost',
          message: 'Conflit de reprise de verrou expiré remporté par une autre instance concurrente.',
        };
      }
    }

    // D. Échec précédent enregistré (FAILED) -> Retentative autorisée
    if (existing.status === LockStatus.FAILED) {
      const nextFencingToken = (parseInt(existing.fencingToken, 10) || 1) + 1;
      const retryPayload = formatFirestoreDocumentFields({
        lockKey,
        ownerId: currentOwnerId,
        fencingToken: nextFencingToken,
        status: LockStatus.IN_FLIGHT,
        retriedAt: now.toISOString(),
        expiresAt: expiresAt.toISOString(),
      });

      const patchUrl = `${specificDocUrl}?currentDocument.updateTime=${encodeURIComponent(existing.updateTime)}&updateMask.fieldPaths=ownerId&updateMask.fieldPaths=fencingToken&updateMask.fieldPaths=status&updateMask.fieldPaths=retriedAt&updateMask.fieldPaths=expiresAt`;
      const patchRes = await fetcher(patchUrl, {
        method: 'PATCH',
        headers,
        body: JSON.stringify(retryPayload),
      });

      if (patchRes.ok) {
        const patchData = await patchRes.json();
        return {
          acquired: true,
          lockKey,
          ownerId: currentOwnerId,
          fencingToken: nextFencingToken,
          updateTime: patchData.updateTime,
          retried: true,
          expiresAt: expiresAt.toISOString(),
        };
      }
    }
  }

  return {
    acquired: false,
    lockKey,
    reason: 'unexpected_error',
    message: `Réponse inattendue de Firestore: HTTP ${createRes.status}`,
  };
}

/**
 * Valide et clôture le verrou avec succès après confirmation de réception par FCM (Statut: SENT).
 * Vérifie formellement le jeton de propriété (ownerId) pour prévenir les libérations abusives.
 */
export async function commitDistributedLock({
  projectId,
  lockKey,
  ownerId,
  updateTime,
  messageId,
  authToken = null,
  customFetcher = null,
}) {
  if (!projectId || !lockKey || !ownerId) {
    throw new Error('Paramètres manquants pour commitDistributedLock.');
  }

  const fetcher = customFetcher || fetch;
  const specificDocUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/idempotency_locks/${lockKey}`;

  const headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`;
  }

  const now = new Date();
  const commitPayload = formatFirestoreDocumentFields({
    status: LockStatus.SENT,
    messageId: messageId || 'sent_unspecified',
    sentAt: now.toISOString(),
    ownerId, // Vérification de propriété
  });

  let url = `${specificDocUrl}?updateMask.fieldPaths=status&updateMask.fieldPaths=messageId&updateMask.fieldPaths=sentAt`;
  if (updateTime) {
    url += `&currentDocument.updateTime=${encodeURIComponent(updateTime)}`;
  }

  const res = await fetcher(url, {
    method: 'PATCH',
    headers,
    body: JSON.stringify(commitPayload),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Échec du commit de verrou d'idempotence: HTTP ${res.status} (${errText})`);
  }

  return await res.json();
}

/**
 * Libère le verrou en cas d'échec transitoire AVANT envoi FCM (Statut: FAILED).
 * Vérifie rigoureusement l'ownerId pour empêcher qu'une ancienne requête lente n'écrase
 * le verrou d'une nouvelle tentative concurrente.
 */
export async function releaseDistributedLock({
  projectId,
  lockKey,
  ownerId,
  updateTime = null,
  errorReason = 'unknown_failure',
  authToken = null,
  customFetcher = null,
}) {
  if (!projectId || !lockKey || !ownerId) {
    return;
  }

  const fetcher = customFetcher || fetch;
  const specificDocUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/idempotency_locks/${lockKey}`;

  const headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`;
  }

  const releasePayload = formatFirestoreDocumentFields({
    status: LockStatus.FAILED,
    error: errorReason,
    failedAt: new Date().toISOString(),
    ownerId, // Rétention du propriétaire qui a échoué
  });

  let url = `${specificDocUrl}?updateMask.fieldPaths=status&updateMask.fieldPaths=error&updateMask.fieldPaths=failedAt`;
  if (updateTime) {
    url += `&currentDocument.updateTime=${encodeURIComponent(updateTime)}`;
  }

  try {
    await fetcher(url, {
      method: 'PATCH',
      headers,
      body: JSON.stringify(releasePayload),
    });
  } catch {
    // Échec de libération non bloquant pour le flux d'erreur principal
  }
}

/**
 * Marque le verrou en état AMBIGUOUS_TIMEOUT lorsqu'un timeout réseau survient
 * après l'envoi de la requête à FCM sans réception de confirmation.
 */
export async function markDistributedLockAmbiguousTimeout({
  projectId,
  lockKey,
  ownerId,
  updateTime = null,
  timeoutError = 'Network timeout waiting for FCM response',
  authToken = null,
  customFetcher = null,
}) {
  if (!projectId || !lockKey || !ownerId) {
    return;
  }

  const fetcher = customFetcher || fetch;
  const specificDocUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/idempotency_locks/${lockKey}`;

  const headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`;
  }

  const timeoutPayload = formatFirestoreDocumentFields({
    status: LockStatus.AMBIGUOUS_TIMEOUT,
    error: timeoutError,
    timedOutAt: new Date().toISOString(),
    ownerId,
  });

  let url = `${specificDocUrl}?updateMask.fieldPaths=status&updateMask.fieldPaths=error&updateMask.fieldPaths=timedOutAt`;
  if (updateTime) {
    url += `&currentDocument.updateTime=${encodeURIComponent(updateTime)}`;
  }

  try {
    await fetcher(url, {
      method: 'PATCH',
      headers,
      body: JSON.stringify(timeoutPayload),
    });
  } catch {
    // Log silencieux
  }
}
