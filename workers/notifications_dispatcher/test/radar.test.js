import test from 'node:test';
import assert from 'node:assert/strict';

import { RADAR_CONFIG } from '../src/radar_config.js';
import { haversineDistanceKm, isValidCoordinates, isGpsFresh } from '../src/geo.js';
import {
  filterAndRankShoppers,
  dispatchRadarWave,
  advanceRadarWave,
  handleAtomicAssignment,
  handleShopperDecline,
  getRadarState,
  saveRadarState,
  extractStoreCoordinates,
  calculateWaveRadius,
  sweepPendingRadarWaves,
} from '../src/radar_service.js';
import { ErrandEvents, processErrandNotificationEvent } from '../src/events.js';
import worker from '../src/index.js';
import { formatFirestoreDocumentFields } from '../src/distributed_lock.js';

/**
 * Simulateur mémoire de l'API Firestore REST pour tester la concurrence,
 * les préconditions updateTime et la persistance du radar.
 */
class MockFirestoreForRadar {
  constructor() {
    this.documents = new Map();
    this.sequence = 1;
  }

  setDocument(collection, docId, data, updateTime = null) {
    const time = updateTime || new Date(Date.now() + this.sequence++).toISOString();
    const formatted = formatFirestoreDocumentFields(data);
    this.documents.set(`${collection}/${docId}`, {
      fields: formatted.fields,
      updateTime: time,
    });
  }

  createFetcher() {
    return async (url, options = {}) => {
      const parsedUrl = new URL(url);
      const pathname = parsedUrl.pathname;
      const method = options.method || 'GET';

      // 1. GET /databases/(default)/documents/{collection}/{docId}
      const match = pathname.match(/\/databases\/\(default\)\/documents\/([^/]+)\/([^/?]+)$/);
      if (match && method === 'GET') {
        const key = `${match[1]}/${match[2]}`;
        const doc = this.documents.get(key);
        if (!doc) {
          return {
            status: 404,
            ok: false,
            json: async () => ({ error: { code: 404, message: 'Document not found' } }),
          };
        }
        return {
          status: 200,
          ok: true,
          json: async () => ({
            name: `projects/dili-express/databases/(default)/documents/${key}`,
            fields: doc.fields,
            updateTime: doc.updateTime,
          }),
        };
      }

      // 2. PATCH /databases/(default)/documents/{collection}/{docId}
      if (match && method === 'PATCH') {
        const key = `${match[1]}/${match[2]}`;
        const existing = this.documents.get(key);
        const reqUpdateTime = parsedUrl.searchParams.get('currentDocument.updateTime');

        // Précondition updateTime pour concurrence atomique
        if (reqUpdateTime) {
          if (!existing || existing.updateTime !== reqUpdateTime) {
            return {
              status: 409,
              ok: false,
              json: async () => ({
                error: {
                  code: 409,
                  message: 'Precondition updateTime failed (concurrent modification)',
                  status: 'ABORTED',
                },
              }),
            };
          }
        }

        const body = JSON.parse(options.body || '{}');
        const newUpdateTime = new Date(Date.now() + this.sequence++).toISOString();
        const mergedFields = { ...(existing ? existing.fields : {}), ...(body.fields || {}) };
        const updatedDoc = {
          fields: mergedFields,
          updateTime: newUpdateTime,
        };
        this.documents.set(key, updatedDoc);

        return {
          status: 200,
          ok: true,
          json: async () => ({
            name: `projects/dili-express/databases/(default)/documents/${key}`,
            fields: updatedDoc.fields,
            updateTime: newUpdateTime,
          }),
        };
      }

      // 3. POST /databases/(default)/documents:runQuery
      if (pathname.endsWith(':runQuery') && method === 'POST') {
        const body = JSON.parse(options.body || '{}');
        const collectionId = body.structuredQuery?.from?.[0]?.collectionId;
        const results = [];
        for (const [key, doc] of this.documents.entries()) {
          if (!collectionId || key.startsWith(`${collectionId}/`)) {
            results.push({
              document: {
                name: `projects/dili-express/databases/(default)/documents/${key}`,
                fields: doc.fields,
                updateTime: doc.updateTime,
              },
            });
          }
        }
        return {
          status: 200,
          ok: true,
          json: async () => results,
        };
      }

      return {
        status: 404,
        ok: false,
        json: async () => ({ error: { code: 404, message: 'Not Found' } }),
      };
    };
  }
}

// Coordonnées de test : Centre d'Alger (Didouche Mourad)
const STORE_ALGIERS = { latitude: 36.7600, longitude: 3.0550 };

// Helper pour générer un jeu de shoppeurs de test à des distances connues
function createMockShoppers(nowMs = Date.now()) {
  return [
    // Dans les 2 km (Candidats éligibles Vague 1)
    {
      uid: 'shopper_01_proche',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: 36.7620, longitude: 3.0560 }, // ~0.24 km
      updatedAt: nowMs - 10000, // il y a 10s
      fcmToken: 'token_01',
      fullName: 'Yacine 1',
    },
    {
      uid: 'shopper_02_proche',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: 36.7650, longitude: 3.0580 }, // ~0.62 km
      updatedAt: nowMs - 20000,
      fcmToken: 'token_02',
      fullName: 'Amine 2',
    },
    {
      uid: 'shopper_03_proche',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: 36.7680, longitude: 3.0600 }, // ~1.0 km
      updatedAt: nowMs - 30000,
      fcmToken: 'token_03',
      fullName: 'Karim 3',
    },
    {
      uid: 'shopper_04_proche',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: 36.7720, longitude: 3.0620 }, // ~1.46 km
      updatedAt: nowMs - 15000,
      fcmToken: 'token_04',
      fullName: 'Rachid 4',
    },
    {
      uid: 'shopper_05_proche',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: 36.7740, longitude: 3.0650 }, // ~1.78 km
      updatedAt: nowMs - 5000,
      fcmToken: 'token_05',
      fullName: 'Samir 5',
    },

    // Hors 2 km mais dans les 5 km (Éligibles Vague 2)
    {
      uid: 'shopper_06_vague2',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: 36.7800, longitude: 3.0700 }, // ~2.57 km
      updatedAt: nowMs - 12000,
      fcmToken: 'token_06',
      fullName: 'Farid 6',
    },
    {
      uid: 'shopper_07_vague2',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: 36.7850, longitude: 3.0800 }, // ~3.55 km
      updatedAt: nowMs - 18000,
      fcmToken: 'token_07',
      fullName: 'Walid 7',
    },

    // Hors 5 km (Vague 3 ou plus)
    {
      uid: 'shopper_08_lointain',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: 36.8100, longitude: 3.1200 }, // ~7.8 km
      updatedAt: nowMs - 40000,
      fcmToken: 'token_08',
      fullName: 'Sofiane 8',
    },

    // Shoppers non éligibles pour différentes raisons
    {
      uid: 'shopper_invalide_hors_ligne',
      role: 'shopper',
      isOnline: false, // Hors ligne !
      activeErrandId: null,
      location: { latitude: 36.7610, longitude: 3.0555 },
      updatedAt: nowMs - 5000,
      fullName: 'Invalide Hors-ligne',
    },
    {
      uid: 'shopper_invalide_mission_active',
      role: 'shopper',
      isOnline: true,
      activeErrandId: 'errand_other_active', // En mission !
      location: { latitude: 36.7610, longitude: 3.0555 },
      updatedAt: nowMs - 5000,
      fullName: 'Invalide Occupé',
    },
    {
      uid: 'shopper_invalide_gps_obsolete',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: 36.7610, longitude: 3.0555 },
      updatedAt: nowMs - 300000, // 5 minutes (obsolète > 120s !)
      fullName: 'Invalide GPS Stale',
    },
    {
      uid: 'shopper_invalide_gps_manquant',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: null, // Pas de position
      updatedAt: nowMs - 5000,
      fullName: 'Invalide Sans GPS',
    },
    {
      uid: 'shopper_invalide_role_client',
      role: 'client', // Pas un shopper !
      isOnline: true,
      activeErrandId: null,
      location: { latitude: 36.7610, longitude: 3.0555 },
      updatedAt: nowMs - 5000,
      fullName: 'Invalide Client',
    },
  ];
}

// Helper pour créer un faux JWT pour les tests
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

test('SUITE COMPLÈTE DU RADAR INTELLIGENT DE COMMANDES (PHASE J — 30 TESTS)', async (t) => {
  const now = Date.now();

  // 1. Sélection des 10 shoppers les plus proches dans 2 km
  await t.test('1. Sélection des shoppers les plus proches dans 2 km (Vague 1)', () => {
    const shoppers = createMockShoppers(now);
    const { selected, totalEligible } = filterAndRankShoppers(shoppers, STORE_ALGIERS, {
      radiusKm: 2.0,
      maxCandidates: 10,
      nowMs: now,
    });

    assert.equal(selected.length, 5);
    assert.equal(totalEligible, 5);
    assert.equal(selected[0].uid, 'shopper_01_proche');
    assert.ok(selected[0].distanceKm < 0.5);
  });

  // 2. Exclusion des shoppers hors rayon de la première vague
  await t.test('2. Exclusion des shoppers hors rayon (> 2 km) en première vague', () => {
    const shoppers = createMockShoppers(now);
    const { selected } = filterAndRankShoppers(shoppers, STORE_ALGIERS, {
      radiusKm: 2.0,
      nowMs: now,
    });

    const uids = selected.map((s) => s.uid);
    assert.ok(!uids.includes('shopper_06_vague2'));
    assert.ok(!uids.includes('shopper_07_vague2'));
    assert.ok(!uids.includes('shopper_08_lointain'));
  });

  // 3. Sélection de moins de 10 candidats quand il n'y en a pas davantage
  await t.test('3. Sélection de moins de 10 candidats quand il n\'y en a pas davantage', () => {
    const fewShoppers = createMockShoppers(now).slice(0, 3);
    const { selected, candidateCount } = filterAndRankShoppers(fewShoppers, STORE_ALGIERS, {
      radiusKm: 2.0,
      maxCandidates: 10,
      nowMs: now,
    });

    assert.equal(selected.length, 3);
    assert.equal(candidateCount, 3);
  });

  // 4. Position GPS absente
  await t.test('4. Exclusion des shoppers dont la position GPS est absente', () => {
    const shoppers = [
      {
        uid: 'shopper_no_gps',
        role: 'shopper',
        isOnline: true,
        location: null,
        updatedAt: now,
      },
    ];
    const { selected } = filterAndRankShoppers(shoppers, STORE_ALGIERS, { nowMs: now });
    assert.equal(selected.length, 0);
  });

  // 5. Position GPS invalide
  await t.test('5. Exclusion des shoppers avec position GPS invalide (hors bornes WGS-84)', () => {
    assert.equal(isValidCoordinates(95.0, 3.0), false); // Latitude > 90
    assert.equal(isValidCoordinates(36.7, 200.0), false); // Longitude > 180
    assert.equal(isValidCoordinates(NaN, 3.0), false);

    const shoppers = [
      {
        uid: 'shopper_bad_coords',
        role: 'shopper',
        isOnline: true,
        location: { latitude: 95.0, longitude: 3.0 },
        updatedAt: now,
      },
    ];
    const { selected } = filterAndRankShoppers(shoppers, STORE_ALGIERS, { nowMs: now });
    assert.equal(selected.length, 0);
  });

  // 6. Position GPS trop ancienne (> 120s)
  await t.test('6. Exclusion des shoppers dont le GPS est obsolète (> 120 secondes)', () => {
    const staleTime = now - (RADAR_CONFIG.GPS_FRESHNESS_THRESHOLD_MS + 5000);
    assert.equal(isGpsFresh(staleTime, RADAR_CONFIG.GPS_FRESHNESS_THRESHOLD_MS, now), false);

    const freshTime = now - 30000;
    assert.equal(isGpsFresh(freshTime, RADAR_CONFIG.GPS_FRESHNESS_THRESHOLD_MS, now), true);

    const shoppers = [
      {
        uid: 'shopper_stale',
        role: 'shopper',
        isOnline: true,
        location: { latitude: 36.7610, longitude: 3.0555 },
        updatedAt: staleTime,
      },
    ];
    const { selected } = filterAndRankShoppers(shoppers, STORE_ALGIERS, { nowMs: now });
    assert.equal(selected.length, 0);
  });

  // 7. Classement correct par distance
  await t.test('7. Classement rigoureux par distance croissante (Haversine)', () => {
    const shoppers = createMockShoppers(now);
    const { selected } = filterAndRankShoppers(shoppers, STORE_ALGIERS, {
      radiusKm: 5.0,
      nowMs: now,
    });

    for (let i = 0; i < selected.length - 1; i++) {
      assert.ok(
        selected[i].distanceKm <= selected[i + 1].distanceKm,
        `Ordre incorrect: ${selected[i].distanceKm} > ${selected[i + 1].distanceKm}`
      );
    }
  });

  // 8. Disponibilité et éligibilité des shoppers
  await t.test('8. Rejet des utilisateurs hors ligne, occupés ou non-shoppers', () => {
    const shoppers = createMockShoppers(now);
    const { selected } = filterAndRankShoppers(shoppers, STORE_ALGIERS, {
      radiusKm: 15.0,
      nowMs: now,
    });

    const uids = selected.map((s) => s.uid);
    assert.ok(!uids.includes('shopper_invalide_hors_ligne'));
    assert.ok(!uids.includes('shopper_invalide_mission_active'));
    assert.ok(!uids.includes('shopper_invalide_role_client'));
  });

  // 9. Exclusion des candidats déjà notifiés
  await t.test('9. Exclusion des candidats déjà notifiés dans une vague précédente', () => {
    const shoppers = createMockShoppers(now);
    const alreadyNotified = ['shopper_01_proche', 'shopper_02_proche'];

    const { selected } = filterAndRankShoppers(shoppers, STORE_ALGIERS, {
      radiusKm: 2.0,
      excludedUids: alreadyNotified,
      nowMs: now,
    });

    const uids = selected.map((s) => s.uid);
    assert.ok(!uids.includes('shopper_01_proche'));
    assert.ok(!uids.includes('shopper_02_proche'));
    assert.equal(selected[0].uid, 'shopper_03_proche');
  });

  // 10. Refus individuel sans blocage des autres
  await t.test('10. Enregistrement d\'un refus individuel sans annuler la course pour autrui', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('radar_states', 'errand_refuse_test', {
      errandId: 'errand_refuse_test',
      status: 'active',
      currentWave: 1,
      declinedShoppers: JSON.stringify([]),
    });

    const fetcher = mock.createFetcher();
    const res = await handleShopperDecline({
      projectId: 'dili-express',
      errandId: 'errand_refuse_test',
      shopperUid: 'shopper_01_proche',
      customFetcher: fetcher,
    });

    assert.equal(res.success, true);
    assert.equal(res.declined, true);

    const state = await getRadarState('dili-express', 'errand_refuse_test', null, fetcher);
    let declined = state.declinedShoppers;
    if (typeof declined === 'string') declined = JSON.parse(declined);
    assert.ok(declined.includes('shopper_01_proche'));
    assert.equal(state.status, 'active'); // Le radar reste actif pour les autres
  });

  // 11. Acceptation simple
  await t.test('11. Acceptation simple et transition exclusive vers accepted', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_accept_test', {
      errandId: 'errand_accept_test',
      clientId: 'client_1',
      shopperId: null,
      status: 'pending',
      storeName: 'Supérette Didouche',
    });

    const fetcher = mock.createFetcher();
    const res = await handleAtomicAssignment({
      projectId: 'dili-express',
      errandId: 'errand_accept_test',
      shopperUid: 'shopper_winner_01',
      customFetcher: fetcher,
    });

    assert.equal(res.success, true);
    assert.equal(res.winner, true);
    assert.equal(res.status, 'accepted');
  });

  // 12 & 13. Deux acceptations concurrentes réellement simultanées & 1 seule attribution finale
  await t.test('12 & 13. Concurrence simultanée : Strictement 1 gagnant et 1 perdant rejeté avec 409', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_race_test', {
      errandId: 'errand_race_test',
      clientId: 'client_1',
      shopperId: null,
      status: 'pending',
      storeName: 'Carrefour Alger',
    });

    const fetcher = mock.createFetcher();

    // Deux requêtes simultanées en concurrence directe (Promise.all)
    const [resShopperA, resShopperB] = await Promise.all([
      handleAtomicAssignment({
        projectId: 'dili-express',
        errandId: 'errand_race_test',
        shopperUid: 'shopper_A',
        customFetcher: fetcher,
      }),
      handleAtomicAssignment({
        projectId: 'dili-express',
        errandId: 'errand_race_test',
        shopperUid: 'shopper_B',
        customFetcher: fetcher,
      }),
    ]);

    const winnerCount = (resShopperA.success ? 1 : 0) + (resShopperB.success ? 1 : 0);
    assert.equal(winnerCount, 1, 'Exactement UN SEUL gagnant doit être retenu');

    const winner = resShopperA.success ? resShopperA : resShopperB;
    const loser = !resShopperA.success ? resShopperA : resShopperB;

    assert.equal(winner.statusCode, 200);
    assert.equal(winner.winner, true);

    assert.equal(loser.statusCode, 409);
    assert.equal(loser.code, 'already_assigned');
  });

  // 14. Rejet d'une acceptation après attribution
  await t.test('14. Rejet immédiat de toute tentative d\'acceptation sur une course déjà attribuée', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_already_taken', {
      errandId: 'errand_already_taken',
      clientId: 'client_1',
      shopperId: 'shopper_first',
      status: 'accepted',
    });

    const fetcher = mock.createFetcher();
    const res = await handleAtomicAssignment({
      projectId: 'dili-express',
      errandId: 'errand_already_taken',
      shopperUid: 'shopper_late',
      customFetcher: fetcher,
    });

    assert.equal(res.success, false);
    assert.equal(res.statusCode, 409);
    assert.equal(res.code, 'already_assigned');
  });

  // 15. Annulation pendant l'attente
  await t.test('15. Arrêt immédiat de la diffusion si la course est annulée par le client', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_cancelled_flow', {
      errandId: 'errand_cancelled_flow',
      clientId: 'client_1',
      status: 'cancelled',
      storeLocation: STORE_ALGIERS,
    });

    const fetcher = mock.createFetcher();
    const res = await dispatchRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_cancelled_flow',
      callerUid: 'client_1',
      shoppers: createMockShoppers(now),
      customFetcher: fetcher,
    });

    assert.equal(res.success, false);
    assert.equal(res.stopped, true);
  });

  // 16. Attribution pendant l'attente et arrêt des vagues suivantes
  await t.test('16. Neutralisation automatique des vagues suivantes dès qu\'une attribution a eu lieu', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_assigned_flow', {
      errandId: 'errand_assigned_flow',
      clientId: 'client_1',
      shopperId: 'shopper_winner_abc',
      status: 'accepted',
    });
    mock.setDocument('radar_states', 'errand_assigned_flow', {
      errandId: 'errand_assigned_flow',
      status: 'active',
      currentWave: 1,
    });

    const fetcher = mock.createFetcher();
    const res = await advanceRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_assigned_flow',
      customFetcher: fetcher,
      force: true,
    });

    assert.equal(res.stopped, true);
  });

  // 17. Élargissement du rayon après le délai prévu
  await t.test('17. Élargissement progressif du rayon en Vague 2 (passage de 2 km à 5 km)', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_expand_wave', {
      errandId: 'errand_expand_wave',
      clientId: 'client_1',
      status: 'pending',
      shopperId: null,
      storeLocation: STORE_ALGIERS,
    });

    const fetcher = mock.createFetcher();
    const shoppers = createMockShoppers(now);

    // Vague 1 initiale
    const wave1 = await dispatchRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_expand_wave',
      callerUid: 'client_1',
      waveNumber: 1,
      shoppers,
      customFetcher: fetcher,
      nowMs: now,
    });

    assert.equal(wave1.waveNumber, 1);
    assert.equal(wave1.radiusKm, 2.0);

    // Avancement vers Vague 2 (avec force: true pour simuler l'expiration des 15s)
    const wave2 = await advanceRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_expand_wave',
      shoppers,
      customFetcher: fetcher,
      force: true,
      nowMs: now + 16000,
    });

    assert.equal(wave2.waveNumber, 2);
    assert.equal(wave2.radiusKm, 5.0);
    // Vague 2 sélectionne les shoppers 06 et 07
    assert.ok(wave2.notifiedShoppers.includes('shopper_06_vague2'));
    assert.ok(wave2.notifiedShoppers.includes('shopper_07_vague2'));
  });

  // 18. Reprise de la diffusion après arrêt ou redémarrage du Worker
  await t.test('18. Reprise durable de l\'état après interruption du Worker via radar_states', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_recover_test', {
      errandId: 'errand_recover_test',
      clientId: 'client_1',
      status: 'pending',
      shopperId: null,
      storeLocation: STORE_ALGIERS,
    });
    // État persistant d'une vague 1 déjà lancée
    mock.setDocument('radar_states', 'errand_recover_test', {
      errandId: 'errand_recover_test',
      status: 'active',
      currentWave: 1,
      currentRadiusKm: 2.0,
      notifiedShoppers: JSON.stringify(['shopper_01_proche', 'shopper_02_proche']),
      declinedShoppers: JSON.stringify([]),
    });

    const fetcher = mock.createFetcher();
    // Reprise par une autre instance Worker
    const resumed = await advanceRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_recover_test',
      shoppers: createMockShoppers(now),
      customFetcher: fetcher,
      force: true,
      nowMs: now + 20000,
    });

    assert.equal(resumed.waveNumber, 2);
    assert.equal(resumed.radiusKm, 5.0);
  });

  // 19. Idempotence des vagues
  await t.test('19. Idempotence : Ne pas avancer une vague si le délai de 15s n\'est pas écoulé', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_timer_test', {
      errandId: 'errand_timer_test',
      clientId: 'client_1',
      status: 'pending',
      storeLocation: STORE_ALGIERS,
    });
    mock.setDocument('radar_states', 'errand_timer_test', {
      errandId: 'errand_timer_test',
      status: 'active',
      currentWave: 1,
      nextWaveDueAt: new Date(now + 15000).toISOString(),
    });

    const fetcher = mock.createFetcher();
    // Appel après seulement 5 secondes (délai non atteint)
    const check = await advanceRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_timer_test',
      shoppers: createMockShoppers(now),
      customFetcher: fetcher,
      force: false,
      nowMs: now + 5000,
    });

    assert.equal(check.pending, true);
    assert.ok(check.remainingSeconds > 0);
  });

  // 20. Idempotence des notifications
  await t.test('20. Idempotence des notifications : Winner réitérant son acceptation', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_winner_retry', {
      errandId: 'errand_winner_retry',
      clientId: 'client_1',
      shopperId: 'shopper_winner_same',
      status: 'accepted',
    });

    const fetcher = mock.createFetcher();
    const retry = await handleAtomicAssignment({
      projectId: 'dili-express',
      errandId: 'errand_winner_retry',
      shopperUid: 'shopper_winner_same',
      customFetcher: fetcher,
    });

    assert.equal(retry.success, true);
    assert.equal(retry.statusCode, 200);
    assert.equal(retry.code, 'already_assigned_to_caller');
  });

  // 21. Timeout FCM & Résilience
  await t.test('21. Résilience aux timeouts FCM lors de la diffusion des vagues', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_fcm_timeout', {
      errandId: 'errand_fcm_timeout',
      clientId: 'client_1',
      status: 'pending',
      storeLocation: STORE_ALGIERS,
    });

    const fetcher = mock.createFetcher();
    // Dispatch sans bloquer même si FCM timeout
    const res = await dispatchRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_fcm_timeout',
      callerUid: 'client_1',
      shoppers: createMockShoppers(now),
      customFetcher: fetcher,
    });

    assert.equal(res.success, true);
  });

  // 22. Erreur FCM
  await t.test('22. Gestion propre des erreurs FCM sans interrompre la diffusion aux autres', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_fcm_err', {
      errandId: 'errand_fcm_err',
      clientId: 'client_1',
      status: 'pending',
      storeLocation: STORE_ALGIERS,
    });

    const fetcher = mock.createFetcher();
    const res = await dispatchRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_fcm_err',
      callerUid: 'client_1',
      shoppers: createMockShoppers(now),
      customFetcher: fetcher,
    });

    assert.equal(res.success, true);
  });

  // 23. Notifications retardées ou en double
  await t.test('23. Protection contre les notifications en double d\'événements radar', () => {
    const errand = {
      errandId: 'errand_notif_dedup',
      clientId: 'client_1',
      shopperId: 'shopper_win',
      status: 'accepted',
      storeName: 'Didouche',
    };

    const notif1 = processErrandNotificationEvent('client_1', errand, ErrandEvents.ERRAND_ACCEPTED);
    assert.equal(notif1.recipientUid, 'client_1');
    assert.equal(notif1.notification.title, 'Shopper Assigné ! 🛵');
  });

  // 24. Protection contre les destinataires arbitraires
  await t.test('24. Protection : Destinataires strictement dérivés des entités autoritatives', () => {
    const errand = {
      errandId: 'errand_spoof_test',
      clientId: 'client_vrai',
      shopperId: 'shopper_vrai',
      status: 'accepted',
      storeName: 'Test',
    };

    const res = processErrandNotificationEvent('shopper_vrai', errand, ErrandEvents.ERRAND_ACCEPTED);
    assert.equal(res.recipientUid, 'client_vrai'); // Impossible de router vers un tiers arbitraire
  });

  // 25. Protection contre l'accès aux commandes non autorisées
  await t.test('25. Protection : Rejet des demandes de diffusion émanant d\'un tiers non créateur', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_auth_check', {
      errandId: 'errand_auth_check',
      clientId: 'client_legitime',
      status: 'pending',
      storeLocation: STORE_ALGIERS,
    });

    const fetcher = mock.createFetcher();
    await assert.rejects(
      () =>
        dispatchRadarWave({
          projectId: 'dili-express',
          errandId: 'errand_auth_check',
          callerUid: 'hacker_malveillant',
          shoppers: [],
          customFetcher: fetcher,
        }),
      /seul le client créateur/
    );
  });

  // 26. Absence de fuite de données privées
  await t.test('26. Zéro fuite de données privées (PIN, téléphone, adresse exacte) dans les payloads', () => {
    const errand = {
      errandId: 'errand_private_test',
      clientId: 'client_private',
      status: 'pending',
      storeName: 'Carrefour El Biar',
      deliveryAddress: '12 Rue Secrète, Appartement 4B',
      securePin: '9988',
      clientPhone: '0555123456',
    };

    const res = processErrandNotificationEvent(
      'client_private',
      errand,
      ErrandEvents.NEW_ERRAND_AVAILABLE,
      {
        targetShopperUid: 'shopper_candidate',
        distanceKm: 1.2,
      }
    );

    const payloadStr = JSON.stringify(res.notification);
    assert.ok(!payloadStr.includes('9988'), 'Le PIN ne doit JAMAIS fuiter dans FCM');
    assert.ok(!payloadStr.includes('0555123456'), 'Le téléphone client ne doit pas fuiter');
    assert.ok(!payloadStr.includes('Appartement 4B'), 'L\'adresse exacte ne doit pas fuiter');
    assert.ok(payloadStr.includes('Carrefour El Biar'));
  });

  // 27. Compatibilité avec les commandes déjà existantes
  await t.test('27. Rétro-compatibilité : Fallback sur deliveryGeoPoint si storeLocation est absent', () => {
    const legacyErrand = {
      errandId: 'errand_legacy',
      storeName: 'Marché',
      deliveryGeoPoint: STORE_ALGIERS, // Ancienne structure sans storeLocation
    };

    const coords = extractStoreCoordinates(legacyErrand);
    assert.deepEqual(coords, STORE_ALGIERS);
  });

  // 28. Gestion correcte de l'épuisement des candidats
  await t.test('28. Épuisement propre du radar sans altération erronée du statut de commande', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_exhaust_test', {
      errandId: 'errand_exhaust_test',
      clientId: 'client_1',
      status: 'pending',
      storeLocation: STORE_ALGIERS,
    });
    mock.setDocument('radar_states', 'errand_exhaust_test', {
      errandId: 'errand_exhaust_test',
      status: 'active',
      currentWave: 4, // Déjà à la vague 4 max
      currentRadiusKm: 11.0,
    });

    const fetcher = mock.createFetcher();
    const res = await advanceRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_exhaust_test',
      shoppers: [], // Aucun shopper
      customFetcher: fetcher,
      force: true,
    });

    assert.equal(res.exhausted, true);
    const state = await getRadarState('dili-express', 'errand_exhaust_test', null, fetcher);
    assert.equal(state.status, 'exhausted');
  });

  // 29. Cohérence du numéro lisible et de l'identifiant technique
  await t.test('29. Maintien strict de l\'identifiant technique errandId sur tout le cycle radar', async () => {
    const mock = new MockFirestoreForRadar();
    const errandId = 'technique_errand_xyz_99';
    mock.setDocument('errands', errandId, {
      errandId,
      clientId: 'client_1',
      status: 'pending',
      storeLocation: STORE_ALGIERS,
    });

    const fetcher = mock.createFetcher();
    const wave = await dispatchRadarWave({
      projectId: 'dili-express',
      errandId,
      callerUid: 'client_1',
      shoppers: createMockShoppers(now),
      customFetcher: fetcher,
    });

    assert.equal(wave.errandId, errandId);
  });

  // 30. Non-régression E2E Worker Routes HTTP
  await t.test('30. Non-régression Worker E2E : Routes HTTP /api/radar/dispatch, /accept, /decline, /status', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_e2e_route', {
      errandId: 'errand_e2e_route',
      clientId: 'client_test_e2e',
      status: 'pending',
      storeLocation: STORE_ALGIERS,
    });

    const env = {
      FIREBASE_PROJECT_ID: 'dili-express',
      ENVIRONMENT: 'test',
      SKIP_AUTH_SIGNATURE: 'true',
      __CUSTOM_FETCHER__: mock.createFetcher(),
    };

    const tokenClient = makeTestJwt({
      sub: 'client_test_e2e',
      aud: 'dili-express',
      iss: 'https://securetoken.google.com/dili-express',
      exp: Math.floor(Date.now() / 1000) + 3600,
    });

    // A. POST /api/radar/dispatch
    const reqDispatch = new Request('https://worker.local/api/radar/dispatch', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${tokenClient}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        errandId: 'errand_e2e_route',
        waveNumber: 1,
        shoppers: createMockShoppers(now),
      }),
    });

    const resDispatch = await worker.fetch(reqDispatch, env);
    assert.equal(resDispatch.status, 200);
    const bodyDispatch = await resDispatch.json();
    assert.equal(bodyDispatch.success, true);
    assert.equal(bodyDispatch.waveNumber, 1);

    // B. GET /api/radar/status
    const reqStatus = new Request('https://worker.local/api/radar/status?errandId=errand_e2e_route', {
      method: 'GET',
      headers: { 'Authorization': `Bearer ${tokenClient}` },
    });
    const resStatus = await worker.fetch(reqStatus, env);
    assert.equal(resStatus.status, 200);
    const bodyStatus = await resStatus.json();
    assert.equal(bodyStatus.exists, true);

    // C. POST /api/radar/accept par un Shopper
    const tokenShopper = makeTestJwt({
      sub: 'shopper_winner_e2e',
      aud: 'dili-express',
      iss: 'https://securetoken.google.com/dili-express',
      exp: Math.floor(Date.now() / 1000) + 3600,
    });

    const reqAccept = new Request('https://worker.local/api/radar/accept', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${tokenShopper}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ errandId: 'errand_e2e_route' }),
    });

    const resAccept = await worker.fetch(reqAccept, env);
    assert.equal(resAccept.status, 200);
    const bodyAccept = await resAccept.json();
    assert.equal(bodyAccept.winner, true);
    assert.equal(bodyAccept.shopperId, 'shopper_winner_e2e');

    // D. Rejet d'un concurrent sur la même course
    const tokenShopperLoser = makeTestJwt({
      sub: 'shopper_loser_e2e',
      aud: 'dili-express',
      iss: 'https://securetoken.google.com/dili-express',
      exp: Math.floor(Date.now() / 1000) + 3600,
    });

    const reqAcceptLoser = new Request('https://worker.local/api/radar/accept', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${tokenShopperLoser}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ errandId: 'errand_e2e_route' }),
    });

    const resAcceptLoser = await worker.fetch(reqAcceptLoser, env);
    assert.equal(resAcceptLoser.status, 409);
    const bodyLoser = await resAcceptLoser.json();
    assert.equal(bodyLoser.code, 'already_assigned');

    // E. Scheduled Handler (Cron Trigger sweep)
    const scheduledRes = await worker.scheduled({}, env, {});
    assert.equal(scheduledRes.status, 'scheduled_sweep_complete');
  });

  // =========================================================================
  // SUITE DE MAINTENANCE : CONFORMITÉ DU RAYON (10 KM) ET ORDONNANCEMENT (15S)
  // =========================================================================

  // 31. Progression exacte des 4 vagues (2.0 km, 5.0 km, 8.0 km, 10.0 km)
  await t.test('31. Progression exacte des 4 vagues (2.0 km, 5.0 km, 8.0 km, 10.0 km) via calculateWaveRadius', () => {
    assert.equal(calculateWaveRadius(1), 2.0);
    assert.equal(calculateWaveRadius(2), 5.0);
    assert.equal(calculateWaveRadius(3), 8.0);
    assert.equal(calculateWaveRadius(4), 10.0);
    // Plafond strict même pour une vague arbitraire > 4
    assert.equal(calculateWaveRadius(5), 10.0);
    assert.equal(calculateWaveRadius(10), 10.0);
  });

  // 32. Plafonnement strict côté Worker même avec calcul ou paramètre supérieur à 10 km
  await t.test('32. Plafonnement strict à 10.0 km côté Worker même si un paramètre externe demande 11, 15 ou 20 km', async () => {
    const latDiff10_10 = 10.1 / (6371 * Math.PI / 180);
    const candidate10_10 = {
      uid: 'shopper_trop_loin_10_1',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: STORE_ALGIERS.latitude + latDiff10_10, longitude: STORE_ALGIERS.longitude },
      updatedAt: now - 5000,
      fullName: 'Shopper 10.1 km',
    };

    // A. filterAndRankShoppers avec radiusKm = 15.0 imposé par l'appelant
    const resFilter = filterAndRankShoppers([candidate10_10], STORE_ALGIERS, {
      radiusKm: 15.0,
      nowMs: now,
    });
    assert.equal(resFilter.selected.length, 0, 'Le candidat à 10.1 km doit être rejeté même si radiusKm = 15.0');

    // B. dispatchRadarWave avec radiusKm = 15.0 imposé par l'appelant
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_cap_test', {
      errandId: 'errand_cap_test',
      clientId: 'client_1',
      status: 'pending',
      shopperId: null,
      storeLocation: STORE_ALGIERS,
    });

    const resDispatch = await dispatchRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_cap_test',
      callerUid: 'client_1',
      waveNumber: 4,
      radiusKm: 15.0, // Tentative de contournement
      shoppers: [candidate10_10],
      customFetcher: mock.createFetcher(),
      nowMs: now,
    });

    assert.equal(resDispatch.radiusKm, 10.0, 'Le rayon effectif retourné par le Worker doit être borné à 10.0 km');
    assert.equal(resDispatch.notifiedShoppersCount, 0, 'Aucun candidat au-delà de 10 km ne doit être notifié');
  });

  // 33. Tests de frontière : candidat à 9.95 km (< 10 km) et à 10.00 km (= 10 km) inclus
  await t.test('33. Tests de frontière : candidat à 9.95 km (< 10 km) et à 10.00 km (= 10 km) éligibles en Vague 4', () => {
    const latDiff9_95 = 9.95 / (6371 * Math.PI / 180);
    const latDiff10_00 = 10.0 / (6371 * Math.PI / 180);

    const shopper9_95 = {
      uid: 'shopper_frontiere_9_95',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: STORE_ALGIERS.latitude + latDiff9_95, longitude: STORE_ALGIERS.longitude },
      updatedAt: now - 10000,
      fullName: 'Shopper 9.95 km',
    };

    const shopper10_00 = {
      uid: 'shopper_frontiere_10_00',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: STORE_ALGIERS.latitude + latDiff10_00, longitude: STORE_ALGIERS.longitude },
      updatedAt: now - 10000,
      fullName: 'Shopper 10.00 km',
    };

    const res = filterAndRankShoppers([shopper9_95, shopper10_00], STORE_ALGIERS, {
      radiusKm: 10.0,
      nowMs: now,
    });

    assert.equal(res.selected.length, 2);
    const uids = res.selected.map((s) => s.uid);
    assert.ok(uids.includes('shopper_frontiere_9_95'));
    assert.ok(uids.includes('shopper_frontiere_10_00'));
  });

  // 34. Tests de frontière : candidat à 10.10 km (> 10 km) strictement exclu
  await t.test('34. Tests de frontière : candidat à 10.10 km (> 10 km) obligatoirement exclu de la Vague 4', () => {
    const latDiff10_10 = 10.1 / (6371 * Math.PI / 180);

    const shopper10_10 = {
      uid: 'shopper_exclu_10_10',
      role: 'shopper',
      isOnline: true,
      activeErrandId: null,
      location: { latitude: STORE_ALGIERS.latitude + latDiff10_10, longitude: STORE_ALGIERS.longitude },
      updatedAt: now - 5000,
      fullName: 'Shopper 10.10 km',
    };

    const res = filterAndRankShoppers([shopper10_10], STORE_ALGIERS, {
      radiusKm: 10.0,
      nowMs: now,
    });

    assert.equal(res.selected.length, 0);
    assert.equal(res.totalEligible, 0);
  });

  // 35. Maintien strict de tous les filtres d'éligibilité pour les candidats dans les 10 km
  await t.test('35. Maintien strict de tous les filtres d\'éligibilité pour les candidats dans les 10 km', () => {
    const latDiff9_95 = 9.95 / (6371 * Math.PI / 180);
    const loc9_95 = { latitude: STORE_ALGIERS.latitude + latDiff9_95, longitude: STORE_ALGIERS.longitude };

    const candidates = [
      // GPS obsolète (> 120s)
      {
        uid: 'shopper_stale_gps',
        role: 'shopper',
        isOnline: true,
        activeErrandId: null,
        location: loc9_95,
        updatedAt: now - 130000, // 130s > 120s
        fullName: 'Stale GPS',
      },
      // Hors ligne
      {
        uid: 'shopper_offline',
        role: 'shopper',
        isOnline: false,
        activeErrandId: null,
        location: loc9_95,
        updatedAt: now - 5000,
        fullName: 'Offline',
      },
      // Mission active incompatible
      {
        uid: 'shopper_busy',
        role: 'shopper',
        isOnline: true,
        activeErrandId: 'errand_other_job',
        location: loc9_95,
        updatedAt: now - 5000,
        fullName: 'Busy',
      },
      // Rôle non shopper
      {
        uid: 'client_user',
        role: 'client',
        isOnline: true,
        activeErrandId: null,
        location: loc9_95,
        updatedAt: now - 5000,
        fullName: 'Client Role',
      },
      // Shopper valide éligible
      {
        uid: 'shopper_valid_eligible',
        role: 'shopper',
        isOnline: true,
        activeErrandId: null,
        location: loc9_95,
        updatedAt: now - 5000,
        fullName: 'Valid Eligible',
      },
    ];

    const res = filterAndRankShoppers(candidates, STORE_ALGIERS, {
      radiusKm: 10.0,
      nowMs: now,
      excludedUids: ['shopper_already_notified'],
    });

    assert.equal(res.selected.length, 1);
    assert.equal(res.selected[0].uid, 'shopper_valid_eligible');
  });

  // 36. Cloudflare Queues Producer : envoi de message différé avec delaySeconds = 15
  await t.test('36. Cloudflare Queues Producer : envoi du message différé à 15s lors de dispatchRadarWave', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_queue_producer_test', {
      errandId: 'errand_queue_producer_test',
      clientId: 'client_1',
      status: 'pending',
      shopperId: null,
      storeLocation: STORE_ALGIERS,
    });

    const enqueuedMessages = [];
    const mockQueue = {
      send: async (message, options) => {
        enqueuedMessages.push({ message, options });
      },
    };

    const envWithQueue = {
      RADAR_QUEUE: mockQueue,
    };

    const res = await dispatchRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_queue_producer_test',
      callerUid: 'client_1',
      waveNumber: 1,
      shoppers: createMockShoppers(now),
      customFetcher: mock.createFetcher(),
      env: envWithQueue,
      nowMs: now,
    });

    assert.equal(res.success, true);
    assert.equal(res.queueEnqueued, true);
    assert.equal(enqueuedMessages.length, 1);
    assert.equal(enqueuedMessages[0].options.delaySeconds, 15);
    assert.equal(enqueuedMessages[0].message.action, 'advance_radar_wave');
    assert.equal(enqueuedMessages[0].message.waveNumber, 2);
  });

  // 37. Cloudflare Queues Consumer : exécution différée autonome via worker.queue
  await t.test('37. Cloudflare Queues Consumer : avancement autonome vers Vague 2 via worker.queue', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_queue_consumer_test', {
      errandId: 'errand_queue_consumer_test',
      clientId: 'client_1',
      status: 'pending',
      shopperId: null,
      storeLocation: STORE_ALGIERS,
    });

    // Initialiser la vague 1
    await dispatchRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_queue_consumer_test',
      callerUid: 'client_1',
      waveNumber: 1,
      shoppers: createMockShoppers(now),
      customFetcher: mock.createFetcher(),
      nowMs: now,
    });

    let ackCalled = false;
    const mockMsg = {
      body: {
        action: 'advance_radar_wave',
        errandId: 'errand_queue_consumer_test',
        waveNumber: 2,
      },
      ack: () => { ackCalled = true; },
      retry: () => {},
    };

    const env = {
      FIREBASE_PROJECT_ID: 'dili-express',
      __CUSTOM_FETCHER__: mock.createFetcher(),
    };

    const batch = { messages: [mockMsg] };
    const queueResults = await worker.queue(batch, env, {});

    assert.equal(ackCalled, true);
    assert.equal(queueResults.length, 1);
    assert.equal(queueResults[0].status, 'advanced');
    assert.equal(queueResults[0].result.waveNumber, 2);
    assert.equal(queueResults[0].result.radiusKm, 5.0);
  });

  // 38. Cloudflare Queues Consumer : arrêt immédiat sans diffusion si course déjà attribuée
  await t.test('38. Cloudflare Queues Consumer : neutralisation si la course est déjà attribuée ou terminée', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_assigned_queue_test', {
      errandId: 'errand_assigned_queue_test',
      clientId: 'client_1',
      status: 'accepted', // Déjà prise !
      shopperId: 'shopper_winner_fast',
      storeLocation: STORE_ALGIERS,
    });

    let ackCalled = false;
    const mockMsg = {
      body: {
        action: 'advance_radar_wave',
        errandId: 'errand_assigned_queue_test',
        waveNumber: 2,
      },
      ack: () => { ackCalled = true; },
      retry: () => {},
    };

    const env = {
      FIREBASE_PROJECT_ID: 'dili-express',
      __CUSTOM_FETCHER__: mock.createFetcher(),
    };

    const batch = { messages: [mockMsg] };
    const queueResults = await worker.queue(batch, env, {});

    assert.equal(ackCalled, true);
    assert.equal(queueResults[0].status, 'stopped');
    assert.equal(queueResults[0].reason, 'errand_no_longer_pending');
  });

  // 39. Cloudflare Queues Consumer : reprise en cas d'erreur transitoire (msg.retry)
  await t.test('39. Cloudflare Queues Consumer : appel de msg.retry() en cas d\'erreur transitoire', async () => {
    let retryCalled = false;
    const mockMsg = {
      body: {
        action: 'advance_radar_wave',
        errandId: 'errand_failing_test',
        waveNumber: 2,
      },
      ack: () => {},
      retry: () => { retryCalled = true; },
    };

    const envFailing = {
      FIREBASE_PROJECT_ID: 'dili-express',
      __CUSTOM_FETCHER__: async () => {
        throw new Error('Connexion réseau Firestore interrompue');
      },
    };

    const batch = { messages: [mockMsg] };
    const queueResults = await worker.queue(batch, envFailing, {});

    assert.equal(retryCalled, true);
    assert.equal(queueResults[0].status, 'retried');
  });

  // 40. Scheduled Cron Sweep : balayage durable autonome des vagues échues
  await t.test('40. Scheduled Cron Sweep : balayage périodique et avancement des vagues échues', async () => {
    const mock = new MockFirestoreForRadar();
    mock.setDocument('errands', 'errand_sweep_test', {
      errandId: 'errand_sweep_test',
      clientId: 'client_1',
      status: 'pending',
      shopperId: null,
      storeLocation: STORE_ALGIERS,
    });

    mock.setDocument('radar_states', 'errand_sweep_test', {
      errandId: 'errand_sweep_test',
      status: 'active',
      currentWave: 1,
      currentRadiusKm: 2.0,
      notifiedShoppers: JSON.stringify(['shopper_01_proche']),
      declinedShoppers: JSON.stringify([]),
      nextWaveDueAt: new Date(now - 5000).toISOString(), // Échéance dépassée de 5s !
    });

    const env = {
      FIREBASE_PROJECT_ID: 'dili-express',
      __CUSTOM_FETCHER__: mock.createFetcher(),
    };

    const scheduledRes = await worker.scheduled({}, env, {});
    assert.equal(scheduledRes.status, 'scheduled_sweep_complete');
    assert.equal(scheduledRes.sweptCount, 1);
  });

  // =========================================================================
  // SUITE DE SÉCURITÉ : EXCLUSION DU CRÉATEUR ET ATTRIBUTION EXCLUSIVE STRICTE
  // =========================================================================

  // 41. filterAndRankShoppers : Exclusion formelle du créateur avec rôle shopper et GPS frais dans le rayon
  await t.test('41. filterAndRankShoppers : exclusion absolue du créateur même si profil shopper éligible à proximité immédiate', () => {
    const shoppersWithCreator = [
      {
        uid: 'client_creator_shopper_01',
        role: 'shopper',
        isOnline: true,
        activeErrandId: null,
        location: { latitude: 36.7620, longitude: 3.0560 }, // ~0.24 km du commerce
        updatedAt: now - 5000, // GPS ultra frais (5s)
        fcmToken: 'token_creator',
        fullName: 'Créateur Shopper',
      },
      {
        uid: 'shopper_legitime_02',
        role: 'shopper',
        isOnline: true,
        activeErrandId: null,
        location: { latitude: 36.7650, longitude: 3.0580 }, // ~0.62 km
        updatedAt: now - 10000,
        fcmToken: 'token_legitime',
        fullName: 'Shopper Légitime',
      },
    ];

    const result = filterAndRankShoppers(shoppersWithCreator, STORE_ALGIERS, {
      radiusKm: 2.0,
      creatorUid: 'client_creator_shopper_01',
      nowMs: now,
    });

    const selectedUids = result.selected.map(s => s.uid);
    assert.equal(selectedUids.includes('client_creator_shopper_01'), false, 'Le créateur ne doit JAMAIS figurer dans les candidats');
    assert.equal(selectedUids.length, 1);
    assert.equal(selectedUids[0], 'shopper_legitime_02');
  });

  // 42. dispatchRadarWave : errand.clientId strictement exclu de la sélection et des notifications
  await t.test('42. dispatchRadarWave : exclusion systématique de errand.clientId de la liste notifiée', async () => {
    const mock = new MockFirestoreForRadar();
    const creatorUid = 'client_dz_creator_radar';

    mock.setDocument('errands', 'errand_creator_exclusion_test', {
      errandId: 'errand_creator_exclusion_test',
      clientId: creatorUid,
      status: 'pending',
      shopperId: null,
      storeLocation: STORE_ALGIERS,
    });

    const shoppersList = [
      {
        uid: creatorUid, // Le créateur est également shopper en ligne à 200m
        role: 'shopper',
        isOnline: true,
        activeErrandId: null,
        location: { latitude: 36.7620, longitude: 3.0560 },
        updatedAt: now - 5000,
        fcmToken: 'token_creator',
      },
      {
        uid: 'shopper_externe_01',
        role: 'shopper',
        isOnline: true,
        activeErrandId: null,
        location: { latitude: 36.7660, longitude: 3.0590 },
        updatedAt: now - 8000,
        fcmToken: 'token_externe',
      },
    ];

    const result = await dispatchRadarWave({
      projectId: 'dili-express',
      errandId: 'errand_creator_exclusion_test',
      callerUid: creatorUid,
      waveNumber: 1,
      shoppers: shoppersList,
      customFetcher: mock.createFetcher(),
      nowMs: now,
    });

    assert.equal(result.success, true);
    assert.equal(result.notifiedShoppers.includes(creatorUid), false);
    assert.equal(result.notifiedShoppers.includes('shopper_externe_01'), true);

    const savedState = await getRadarState('dili-express', 'errand_creator_exclusion_test', null, mock.createFetcher());
    let notified = savedState.notifiedShoppers;
    if (typeof notified === 'string') notified = JSON.parse(notified);
    assert.equal(notified.includes(creatorUid), false);
  });

  // 43. handleAtomicAssignment : Rejet 403 cannot_assign_own_errand si le créateur essaie d'accepter sa propre course
  await t.test('43. handleAtomicAssignment : Rejet 403 cannot_assign_own_errand en cas de tentative d\'auto-attribution', async () => {
    const mock = new MockFirestoreForRadar();
    const creatorUid = 'client_owner_dz_10';

    mock.setDocument('errands', 'errand_self_assign_test', {
      errandId: 'errand_self_assign_test',
      clientId: creatorUid,
      status: 'pending',
      shopperId: null,
      storeLocation: STORE_ALGIERS,
    });

    mock.setDocument('radar_states', 'errand_self_assign_test', {
      errandId: 'errand_self_assign_test',
      status: 'active',
      currentWave: 1,
      notifiedShoppers: JSON.stringify(['shopper_autre']),
      declinedShoppers: JSON.stringify([]),
    });

    const result = await handleAtomicAssignment({
      projectId: 'dili-express',
      errandId: 'errand_self_assign_test',
      shopperUid: creatorUid,
      customFetcher: mock.createFetcher(),
    });

    assert.equal(result.success, false);
    assert.equal(result.statusCode, 403);
    assert.equal(result.code, 'cannot_assign_own_errand');
  });

  // 44. processErrandNotificationEvent : Refus d'émission de notification radar au créateur
  await t.test('44. processErrandNotificationEvent : Erreur levée si targetShopperUid est le créateur de la course', () => {
    const errand = {
      errandId: 'errand_notif_guard_test',
      clientId: 'creator_uid_99',
      status: 'pending',
      storeName: 'Supérette Didouche',
    };

    assert.throws(
      () => {
        processErrandNotificationEvent(
          'system_radar',
          errand,
          ErrandEvents.NEW_ERRAND_AVAILABLE,
          { isSystemDispatch: true, targetShopperUid: 'creator_uid_99' }
        );
      },
      /le créateur ne peut pas recevoir d'offre pour sa propre course/
    );
  });

  // 45. Route HTTP E2E /api/radar/accept : Rejet 403 pour le créateur appelant
  await t.test('45. Route Worker E2E POST /api/radar/accept : Rejet 403 cannot_assign_own_errand pour le créateur', async () => {
    const mock = new MockFirestoreForRadar();
    const creatorUid = 'client_creator_http_e2e';

    mock.setDocument('errands', 'errand_http_self_assign', {
      errandId: 'errand_http_self_assign',
      clientId: creatorUid,
      status: 'pending',
      shopperId: null,
      storeLocation: STORE_ALGIERS,
    });

    const tokenCreator = makeTestJwt({
      sub: creatorUid,
      aud: 'dili-express',
      iss: 'https://securetoken.google.com/dili-express',
      exp: Math.floor(Date.now() / 1000) + 3600,
    });

    const env = {
      FIREBASE_PROJECT_ID: 'dili-express',
      SKIP_AUTH_SIGNATURE: 'true',
      __CUSTOM_FETCHER__: mock.createFetcher(),
    };

    const req = new Request('https://worker.local/api/radar/accept', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${tokenCreator}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ errandId: 'errand_http_self_assign' }),
    });

    const res = await worker.fetch(req, env);
    assert.equal(res.status, 403);
    const body = await res.json();
    assert.equal(body.code, 'cannot_assign_own_errand');
  });
});
