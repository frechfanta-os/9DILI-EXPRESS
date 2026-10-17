import test from 'node:test';
import assert from 'node:assert/strict';

import {
  LockStatus,
  formatFirestoreDocumentFields,
  acquireDistributedLock,
  commitDistributedLock,
  releaseDistributedLock,
  markDistributedLockAmbiguousTimeout,
} from '../src/distributed_lock.js';
import { parseFirestoreFields } from '../src/firestore.js';

/**
 * Simulateur fidèle de l'API Firestore REST pour les verrous atomiques distribués.
 * Reproduit les comportements réels de Google Cloud Firestore :
 * - Atomicité de création avec code HTTP 409 (ALREADY_EXISTS).
 * - Préconditions d'updateTime sur les requêtes PATCH (HTTP 412 PRECONDITION_FAILED).
 */
class MockFirestoreRestServer {
  constructor() {
    this.documents = new Map();
    this.sequence = 1;
  }

  createFetcher() {
    return async (url, options = {}) => {
      const parsedUrl = new URL(url);
      const pathname = parsedUrl.pathname;
      const method = options.method || 'GET';

      // 1. POST /databases/(default)/documents/idempotency_locks?documentId=...
      if (pathname.endsWith('/idempotency_locks') && method === 'POST') {
        const docId = parsedUrl.searchParams.get('documentId');
        if (this.documents.has(docId)) {
          return {
            status: 409,
            ok: false,
            json: async () => ({
              error: {
                code: 409,
                message: `Document already exists: projects/dili-express/databases/(default)/documents/idempotency_locks/${docId}`,
                status: 'ALREADY_EXISTS',
              },
            }),
            text: async () => 'Document already exists',
          };
        }

        const body = JSON.parse(options.body || '{}');
        const updateTime = new Date(Date.now() + this.sequence++).toISOString();
        const doc = {
          fields: body.fields || {},
          updateTime,
        };
        this.documents.set(docId, doc);

        return {
          status: 200,
          ok: true,
          json: async () => doc,
        };
      }

      // 2. GET /idempotency_locks/{docId}
      const getMatch = pathname.match(/\/idempotency_locks\/([^/]+)$/);
      if (getMatch && method === 'GET') {
        const docId = decodeURIComponent(getMatch[1]);
        if (!this.documents.has(docId)) {
          return {
            status: 404,
            ok: false,
            json: async () => ({ error: { code: 404, message: 'Document not found' } }),
          };
        }

        return {
          status: 200,
          ok: true,
          json: async () => this.documents.get(docId),
        };
      }

      // 3. PATCH /idempotency_locks/{docId}?currentDocument.updateTime=...
      if (getMatch && method === 'PATCH') {
        const docId = decodeURIComponent(getMatch[1]);
        if (!this.documents.has(docId)) {
          return { status: 404, ok: false, json: async () => ({ error: { code: 404 } }) };
        }

        const expectedUpdateTime = parsedUrl.searchParams.get('currentDocument.updateTime');
        const existingDoc = this.documents.get(docId);

        // Validation de précondition de concurrence optimiste
        if (expectedUpdateTime && existingDoc.updateTime !== expectedUpdateTime) {
          return {
            status: 412,
            ok: false,
            json: async () => ({
              error: {
                code: 412,
                message: 'Precondition check failed: updateTime mismatch',
                status: 'FAILED_PRECONDITION',
              },
            }),
            text: async () => 'Precondition check failed',
          };
        }

        const body = JSON.parse(options.body || '{}');
        const parsedBodyFields = parseFirestoreFields(body.fields);
        const existingFields = parseFirestoreFields(existingDoc.fields);

        // Vérification de propriété (Owner Fencing)
        if (body.fields?.ownerId) {
          const incomingOwner = parsedBodyFields.ownerId;
          const currentOwner = existingFields.ownerId;
          // Si le document a un propriétaire différent et n'est pas expiré
          if (incomingOwner && currentOwner && incomingOwner !== currentOwner && existingFields.status === 'in_flight') {
            const isExpired = Date.now() > new Date(existingFields.expiresAt).getTime();
            if (!isExpired && !parsedBodyFields.recoveredFromOwnerId) {
              return {
                status: 403,
                ok: false,
                text: async () => 'Owner fencing violation: lock owned by another worker',
              };
            }
          }
        }

        const mergedFields = { ...existingFields, ...parsedBodyFields };
        const newUpdateTime = new Date(Date.now() + this.sequence++).toISOString();
        const updatedDoc = {
          fields: formatFirestoreDocumentFields(mergedFields).fields,
          updateTime: newUpdateTime,
        };
        this.documents.set(docId, updatedDoc);

        return {
          status: 200,
          ok: true,
          json: async () => updatedDoc,
        };
      }

      return { status: 404, ok: false };
    };
  }
}

test('Idempotence Distribuée Firestore REST — Tests Concurrence, Fencing et Reprise', async (t) => {
  const server = new MockFirestoreRestServer();
  const fetcher = server.createFetcher();
  const projectId = 'dili-express';

  await t.test('1. Création atomique initiale accorde le verrou avec fencingToken = 1', async () => {
    const lock1 = await acquireDistributedLock({
      projectId,
      lockKey: 'errand_1001_shopper_delivering',
      ownerId: 'worker_node_alpha',
      ttlSeconds: 5,
      customFetcher: fetcher,
    });

    assert.equal(lock1.acquired, true);
    assert.equal(lock1.ownerId, 'worker_node_alpha');
    assert.equal(lock1.fencingToken, 1);
    assert.ok(lock1.updateTime);
  });

  await t.test('2. Requête concurrente simultanée sur autre PoP rejetée (HTTP 409 -> in_flight)', async () => {
    // Une 2ème requête sur un datacenter Cloudflare différent
    const lock2 = await acquireDistributedLock({
      projectId,
      lockKey: 'errand_1001_shopper_delivering',
      ownerId: 'worker_node_bravo',
      ttlSeconds: 5,
      customFetcher: fetcher,
    });

    assert.equal(lock2.acquired, false);
    assert.equal(lock2.reason, 'in_flight');
    assert.match(lock2.message, /traitement simultané/);
  });

  await t.test('3. Confirmation FCM valide le statut SENT et bloque les doublons futurs', async () => {
    const existingDoc = server.documents.get('errand_1001_shopper_delivering');
    assert.ok(existingDoc);

    // Clôture nominale après confirmation FCM
    await commitDistributedLock({
      projectId,
      lockKey: 'errand_1001_shopper_delivering',
      ownerId: 'worker_node_alpha',
      updateTime: existingDoc.updateTime,
      messageId: 'projects/dili-express/messages/msg_fcm_001',
      customFetcher: fetcher,
    });

    // Tentative ultérieure par un tiers
    const lockDup = await acquireDistributedLock({
      projectId,
      lockKey: 'errand_1001_shopper_delivering',
      ownerId: 'worker_node_charlie',
      customFetcher: fetcher,
    });

    assert.equal(lockDup.acquired, false);
    assert.equal(lockDup.reason, 'duplicate');
    assert.equal(lockDup.messageId, 'projects/dili-express/messages/msg_fcm_001');
  });

  await t.test('4. Libération sur échec (FAILED) permet une retentative légitime', async () => {
    // Acquisition initiale
    const lockFail = await acquireDistributedLock({
      projectId,
      lockKey: 'errand_1002_bid_accepted',
      ownerId: 'worker_fail_test',
      ttlSeconds: 5,
      customFetcher: fetcher,
    });
    assert.equal(lockFail.acquired, true);

    // Échec avant envoi FCM (ex: erreur Firestore de validation)
    await releaseDistributedLock({
      projectId,
      lockKey: 'errand_1002_bid_accepted',
      ownerId: 'worker_fail_test',
      updateTime: lockFail.updateTime,
      errorReason: 'auth_validation_failed',
      customFetcher: fetcher,
    });

    // Nouvelle tentative
    const lockRetry = await acquireDistributedLock({
      projectId,
      lockKey: 'errand_1002_bid_accepted',
      ownerId: 'worker_retry_test',
      ttlSeconds: 5,
      customFetcher: fetcher,
    });

    assert.equal(lockRetry.acquired, true);
    assert.equal(lockRetry.retried, true);
    assert.equal(lockRetry.fencingToken, 2);
  });

  await t.test('5. Crash Recovery : Reprise automatique après expiration logique', async () => {
    // Instance qui plante : TTL expiré (0 seconde)
    const lockCrash = await acquireDistributedLock({
      projectId,
      lockKey: 'errand_1003_shopper_arrived',
      ownerId: 'worker_zombie_1',
      ttlSeconds: -1, // Déjà expiré
      customFetcher: fetcher,
    });
    assert.equal(lockCrash.acquired, true);

    // Nouvelle requête après crash
    const lockRecovered = await acquireDistributedLock({
      projectId,
      lockKey: 'errand_1003_shopper_arrived',
      ownerId: 'worker_healthy_2',
      ttlSeconds: 10,
      customFetcher: fetcher,
    });

    assert.equal(lockRecovered.acquired, true);
    assert.equal(lockRecovered.recovered, true);
    assert.equal(lockRecovered.ownerId, 'worker_healthy_2');
    assert.equal(lockRecovered.fencingToken, 2);
  });

  await t.test('6. Fencing Token : Requête zombie incapable d\'écraser ou libérer le verrou repris', async () => {
    // La requête zombie_1 tente maintenant de faire un commit ou release après avoir perdu le verrou
    const zombieDoc = server.documents.get('errand_1003_shopper_arrived');
    const parsedZombie = parseFirestoreFields(zombieDoc.fields);

    // Le propriétaire actuel dans Firestore est healthy_2
    assert.equal(parsedZombie.ownerId, 'worker_healthy_2');

    // Zombie tente un commit avec son ancien updateTime
    await assert.rejects(
      async () => {
        await commitDistributedLock({
          projectId,
          lockKey: 'errand_1003_shopper_arrived',
          ownerId: 'worker_zombie_1',
          updateTime: 'old_expired_update_time_123',
          messageId: 'fake_msg',
          customFetcher: fetcher,
        });
      },
      /Échec du commit de verrou/
    );
  });

  await t.test('7. Timeout ambigu FCM (AMBIGUOUS_TIMEOUT) suspend les retentatives aveugles', async () => {
    const lockAmbiguous = await acquireDistributedLock({
      projectId,
      lockKey: 'errand_1004_completed',
      ownerId: 'worker_timeout_node',
      ttlSeconds: 10,
      customFetcher: fetcher,
    });
    assert.equal(lockAmbiguous.acquired, true);

    // Simulation d'une coupure réseau pendant que FCM traitait la requête
    await markDistributedLockAmbiguousTimeout({
      projectId,
      lockKey: 'errand_1004_completed',
      ownerId: 'worker_timeout_node',
      updateTime: lockAmbiguous.updateTime,
      timeoutError: 'FCM connection reset by peer after 5000ms',
      customFetcher: fetcher,
    });

    // Nouvelle requête cliente reçue
    const lockRetryAfterTimeout = await acquireDistributedLock({
      projectId,
      lockKey: 'errand_1004_completed',
      ownerId: 'worker_retry_node',
      customFetcher: fetcher,
    });

    assert.equal(lockRetryAfterTimeout.acquired, false);
    assert.equal(lockRetryAfterTimeout.reason, 'ambiguous_timeout');
    assert.match(lockRetryAfterTimeout.message, /ambigu/);
  });
});
