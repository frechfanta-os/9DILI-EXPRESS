import test from 'node:test';
import assert from 'node:assert/strict';

import { validateFirebaseClaims, decodeJwtUnverified } from '../src/security.js';
import { parseFirestoreFields } from '../src/firestore.js';
import {
  ErrandEvents,
  checkAndRegisterIdempotency,
  resetIdempotencyStore,
  processErrandNotificationEvent,
} from '../src/events.js';
import worker from '../src/index.js';

// Helper pour créer un faux JWT non signé pour les tests
function makeTestJwt(payload) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const b64 = (obj) =>
    Buffer.from(JSON.stringify(obj))
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
  return `${b64(header)}.${b64(payload)}.mockSignature`;
}

test('Sécurité Firebase Auth — Validation des revendications JWT', async (t) => {
  const now = Math.floor(Date.now() / 1000);

  await t.test('Jeton valide accepté', () => {
    const payload = {
      sub: 'user_client_123',
      email: 'client@9dili.dz',
      aud: 'dili-express',
      iss: 'https://securetoken.google.com/dili-express',
      exp: now + 3600,
      auth_time: now - 60,
    };

    const res = validateFirebaseClaims(payload, 'dili-express');
    assert.equal(res.uid, 'user_client_123');
    assert.equal(res.email, 'client@9dili.dz');
  });

  await t.test('Jeton expiré rejeté', () => {
    const payload = {
      sub: 'user_client_123',
      aud: 'dili-express',
      iss: 'https://securetoken.google.com/dili-express',
      exp: now - 10, // Expiré
    };

    assert.throws(() => validateFirebaseClaims(payload, 'dili-express'), /expiré/);
  });

  await t.test('Audience non autorisée rejetée', () => {
    const payload = {
      sub: 'user_client_123',
      aud: 'wrong-project-id',
      iss: 'https://securetoken.google.com/dili-express',
      exp: now + 3600,
    };

    assert.throws(() => validateFirebaseClaims(payload, 'dili-express'), /Audience non autorisée/);
  });

  await t.test('Émetteur invalide rejeté', () => {
    const payload = {
      sub: 'user_client_123',
      aud: 'dili-express',
      iss: 'https://evil-issuer.com',
      exp: now + 3600,
    };

    assert.throws(() => validateFirebaseClaims(payload, 'dili-express'), /Émetteur non autorisé/);
  });

  await t.test('Jeton avec iat dans le futur rejeté', () => {
    const payload = {
      sub: 'user_client_123',
      aud: 'dili-express',
      iss: 'https://securetoken.google.com/dili-express',
      exp: now + 3600,
      iat: now + 1000, // Dans le futur
    };

    assert.throws(() => validateFirebaseClaims(payload, 'dili-express'), /iat invalide/);
  });

  await t.test('Jeton avec auth_time dans le futur rejeté', () => {
    const payload = {
      sub: 'user_client_123',
      aud: 'dili-express',
      iss: 'https://securetoken.google.com/dili-express',
      exp: now + 3600,
      auth_time: now + 1000, // Dans le futur
    };

    assert.throws(() => validateFirebaseClaims(payload, 'dili-express'), /auth_time invalide/);
  });
});

test('Sécurité Firebase Auth — Vérification cryptographique RS256 et JWKS', async () => {
  const { generateKeyPairSync } = await import('node:crypto');
  const { verifyFirebaseJwtSignature } = await import('../src/security.js');

  // Génération d'une vraie paire de clés RSA 2048 pour le test
  const { publicKey, privateKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
  });

  const jwkPublic = publicKey.export({ format: 'jwk' });
  jwkPublic.kid = 'test_key_kid_001';
  jwkPublic.alg = 'RS256';
  jwkPublic.use = 'sig';

  const mockJwksFetcher = async () => ({
    ok: true,
    headers: { get: () => 'max-age=3600' },
    json: async () => ({ keys: [jwkPublic] }),
  });

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', kid: 'test_key_kid_001', typ: 'JWT' };
  const payload = {
    sub: 'user_crypto_verified',
    aud: 'dili-express',
    iss: 'https://securetoken.google.com/dili-express',
    exp: now + 3600,
    iat: now,
  };

  const b64 = (obj) =>
    Buffer.from(JSON.stringify(obj))
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');

  const dataToSign = `${b64(header)}.${b64(payload)}`;

  // Signature réelle avec la clé privée
  const { createSign } = await import('node:crypto');
  const sign = createSign('RSA-SHA256');
  sign.update(dataToSign);
  const signature = sign
    .sign(privateKey, 'base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

  const signedJwt = `${dataToSign}.${signature}`;

  // 1. Validation de la signature valide
  const verifiedUser = await verifyFirebaseJwtSignature(signedJwt, 'dili-express', mockJwksFetcher);
  assert.equal(verifiedUser.uid, 'user_crypto_verified');

  // 2. Rejet en cas de signature altérée / corrompue
  const tamperedJwt = `${dataToSign}.${signature.slice(0, -4)}AAAA`;
  await assert.rejects(
    () => verifyFirebaseJwtSignature(tamperedJwt, 'dili-express', mockJwksFetcher),
    /Signature cryptographique RS256 invalide/
  );

  // 3. Rejet si kid inconnu
  const unknownKidJwt = `${b64({ alg: 'RS256', kid: 'unknown_kid' })}.${b64(payload)}.${signature}`;
  await assert.rejects(
    () => verifyFirebaseJwtSignature(unknownKidJwt, 'dili-express', mockJwksFetcher),
    /Clé publique Google introuvable/
  );
});

test('Firestore REST — Parsing des champs typés', () => {
  const rawFields = {
    storeName: { stringValue: 'Supérette Alger Centre' },
    ticketAmount: { doubleValue: 3200.5 },
    pinFailedAttempts: { integerValue: '2' },
    isWeighable: { booleanValue: true },
    emptyField: { nullValue: null },
    tags: {
      arrayValue: {
        values: [{ stringValue: 'urgent' }, { stringValue: 'frais' }],
      },
    },
    location: {
      geoPointValue: { latitude: 36.7538, longitude: 3.0588 },
    },
  };

  const parsed = parseFirestoreFields(rawFields);
  assert.equal(parsed.storeName, 'Supérette Alger Centre');
  assert.equal(parsed.ticketAmount, 3200.5);
  assert.equal(parsed.pinFailedAttempts, 2);
  assert.equal(parsed.isWeighable, true);
  assert.equal(parsed.emptyField, null);
  assert.deepEqual(parsed.tags, ['urgent', 'frais']);
  assert.deepEqual(parsed.location, { latitude: 36.7538, longitude: 3.0588 });
});

test('Événements Métier — Contrôle des Rôles et des États Firestore', async (t) => {
  const sampleErrand = {
    errandId: 'errand_001',
    clientId: 'client_alpha',
    shopperId: 'shopper_bravo',
    storeName: 'Supérette Didouche',
    status: 'delivering',
    securePin: '7821', // Secret critique
  };

  await t.test('SHOPPER_DELIVERING autorisé pour le shopper assigné en statut delivering', () => {
    const result = processErrandNotificationEvent(
      'shopper_bravo',
      sampleErrand,
      ErrandEvents.SHOPPER_DELIVERING
    );

    assert.equal(result.recipientUid, 'client_alpha');
    assert.equal(result.notification.errandId, 'errand_001');
    assert.match(result.notification.title, /Shopper.*Route/);
    // Vérification de sécurité : le PIN ne doit JAMAIS apparaître dans la notification
    assert.equal(JSON.stringify(result).includes('7821'), false);
  });

  await t.test('SHOPPER_DELIVERING rejeté si appelé par un tiers ou le client', () => {
    assert.throws(
      () =>
        processErrandNotificationEvent(
          'client_alpha',
          sampleErrand,
          ErrandEvents.SHOPPER_DELIVERING
        ),
      /Action non autorisée/
    );
  });

  await t.test('SHOPPER_DELIVERING rejeté si le statut Firestore ne correspond pas', () => {
    const wrongStatusErrand = { ...sampleErrand, status: 'pending' };
    assert.throws(
      () =>
        processErrandNotificationEvent(
          'shopper_bravo',
          wrongStatusErrand,
          ErrandEvents.SHOPPER_DELIVERING
        ),
      /État Firestore non conforme/
    );
  });

  await t.test('NEW_ERRAND_AVAILABLE broadcast vers topic available_errands en statut pending', () => {
    const pendingErrand = {
      errandId: 'errand_pending_1',
      clientId: 'client_alpha',
      shopperId: null,
      storeName: 'Boucherie El Biar',
      status: 'pending',
    };

    const result = processErrandNotificationEvent(
      'client_alpha',
      pendingErrand,
      ErrandEvents.NEW_ERRAND_AVAILABLE
    );

    assert.equal(result.isTopicBroadcast, true);
    assert.equal(result.topicName, 'available_errands');
    assert.match(result.notification.body, /Boucherie El Biar/);
  });
});

test('Protection Anti-Doublons & Idempotence avec Verrouillage En-Vol (In-Flight Lock)', async (t) => {
  const { acquireIdempotencyLock, commitIdempotency, releaseIdempotencyLock } = await import('../src/events.js');
  resetIdempotencyStore();

  await t.test('Acquisition initiale du verrou accordée', () => {
    const lock1 = acquireIdempotencyLock('errand_100', 'shopper_arrived');
    assert.equal(lock1.acquired, true);
    assert.equal(lock1.key, 'errand_100_shopper_arrived');
  });

  await t.test('Appel concurrent simultané rejeté (in_flight)', () => {
    // Le premier appel est encore en-vol
    const lock2 = acquireIdempotencyLock('errand_100', 'shopper_arrived');
    assert.equal(lock2.acquired, false);
    assert.equal(lock2.reason, 'in_flight');
    assert.match(lock2.message, /traitement simultané/);
  });

  await t.test('Validation finale (commit) et rejet des doublons subséquents', () => {
    commitIdempotency('errand_100_shopper_arrived');

    const lock3 = acquireIdempotencyLock('errand_100', 'shopper_arrived');
    assert.equal(lock3.acquired, false);
    assert.equal(lock3.reason, 'duplicate');
    assert.match(lock3.message, /déjà été notifié/);
  });

  await t.test('Libération sur erreur (release) autorise une retentative légitime', () => {
    const lockFail = acquireIdempotencyLock('errand_101', 'bid_accepted');
    assert.equal(lockFail.acquired, true);

    // Simulation d'une coupure réseau -> libération du verrou
    releaseIdempotencyLock(lockFail.key);

    const lockRetry = acquireIdempotencyLock('errand_101', 'bid_accepted');
    assert.equal(lockRetry.acquired, true, 'La retentative après libération doit réussir');
  });

  await t.test('Rétro-compatibilité checkAndRegisterIdempotency', () => {
    const fresh = checkAndRegisterIdempotency('errand_200', 'completed');
    assert.equal(fresh, true);

    const dup = checkAndRegisterIdempotency('errand_200', 'completed');
    assert.equal(dup, false);
  });
});

test('Worker E2E — Requêtes HTTP et Gestion des Erreurs', async (t) => {
  const env = {
    FIREBASE_PROJECT_ID: 'dili-express',
    ENVIRONMENT: 'test',
  };

  await t.test('GET /health retourne 200 OK', async () => {
    const req = new Request('https://worker.local/health');
    const res = await worker.fetch(req, env);
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.status, 'ok');
    assert.equal(data.service, '9dili-express-notifications-dispatcher');
  });

  await t.test('POST /api/notify sans Authorization retourne 400', async () => {
    const req = new Request('https://worker.local/api/notify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ errandId: 'e1', eventType: 'shopper_arrived' }),
    });

    const res = await worker.fetch(req, env);
    assert.equal(res.status, 400);
    const data = await res.json();
    assert.equal(data.success, false);
    assert.match(data.error, /Authorization/);
  });

  await t.test('Route inconnue retourne 404', async () => {
    const req = new Request('https://worker.local/unknown-path');
    const res = await worker.fetch(req, env);
    assert.equal(res.status, 404);
  });
});

test('FCM HTTP v1 — Détection des Jetons Obsolètes et Erreurs', async (t) => {
  const { sendFcmHttpV1Message } = await import('../src/fcm.js');

  await t.test('Détection automatique du code UNREGISTERED (Jeton obsolète)', async () => {
    const mockFcmErrorResponse = {
      error: {
        code: 404,
        message: 'Requested entity was not found.',
        status: 'NOT_FOUND',
        details: [
          {
            '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
            errorCode: 'UNREGISTERED',
          },
        ],
      },
    };

    const mockFetcher = async () => ({
      ok: false,
      status: 404,
      text: async () => JSON.stringify(mockFcmErrorResponse),
    });

    await assert.rejects(
      async () => {
        await sendFcmHttpV1Message({
          projectId: 'dili-express',
          accessToken: 'mock_access_token',
          targetFcmToken: 'stale_token_abc',
          title: 'Test',
          body: 'Corps test',
          customFetcher: mockFetcher,
        });
      },
      (err) => {
        assert.equal(err.status, 404);
        assert.equal(err.isStaleToken, true);
        assert.equal(err.errorCode, 'UNREGISTERED');
        return true;
      }
    );
  });
});
