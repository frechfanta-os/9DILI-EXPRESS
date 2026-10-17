/**
 * Service Métier du Radar Intelligent de Diffusion et d'Attribution Atomique.
 *
 * Principes stricts :
 * 1. Diffusion géolocalisée par vagues progressives (2 km initial, 10 shoppers max, 15s de délai).
 * 2. Filtrage d'éligibilité : compte shopper valide, en ligne, sans mission active, GPS récent (< 120s).
 * 3. Attribution exclusive atomique via Firestore REST avec précondition updateTime (Strictement 1 seul gagnant).
 * 4. Répulsion des courses concurrentes (HTTP 409 already_assigned) et idempotence pour le gagnant.
 * 5. Notifications ciblées unicast (zéro topic public divulguant des détails de commande).
 * 6. Zéro secret dans le client ou le code Git.
 */

import { RADAR_CONFIG } from './radar_config.js';
import { haversineDistanceKm, isValidCoordinates, isGpsFresh } from './geo.js';
import { parseFirestoreFields } from './firestore.js';
import { formatFirestoreDocumentFields } from './distributed_lock.js';
import { ErrandEvents, processErrandNotificationEvent } from './events.js';
import { sendFcmHttpV1Message, getGoogleOAuth2AccessToken } from './fcm.js';

/**
 * Calcule le rayon maximal effectif pour une vague donnée :
 * Vague 1 : 2.0 km
 * Vague 2 : 5.0 km
 * Vague 3 : 8.0 km
 * Vague 4 : 10.0 km (strictement plafonné)
 *
 * @param {number} waveNumber Numéro de la vague (1 à 4)
 * @returns {number} Rayon effectif en kilomètres (borné à MAX_RADIUS_KM)
 */
export function calculateWaveRadius(waveNumber) {
  if (waveNumber <= 1) return RADAR_CONFIG.INITIAL_RADIUS_KM;
  const theoretical = RADAR_CONFIG.INITIAL_RADIUS_KM + (waveNumber - 1) * RADAR_CONFIG.RADIUS_INCREMENT_KM;
  return Math.min(theoretical, RADAR_CONFIG.MAX_RADIUS_KM);
}

/**
 * Filtre et classe les shoppers éligibles par distance croissante selon les critères stricts du radar.
 *
 * @param {Array<Object>} shoppers Liste des shoppeurs disponibles
 * @param {Object} storeLocation Coordonnées du commerce { latitude, longitude }
 * @param {Object} [options]
 * @param {number} [options.radiusKm=2.0] Rayon maximal pour la vague
 * @param {number} [options.maxCandidates=10] Nombre maximum de candidats
 * @param {Array<string>|Set<string>} [options.excludedUids=[]] UIDs déjà notifiés ou ayant décliné
 * @param {string} [options.creatorUid] Identifiant du client créateur de la course à exclure absolument
 * @param {string} [options.clientId] Alias pour creatorUid
 * @param {number} [options.thresholdMs=120000] Seuil de fraîcheur GPS maximale
 * @param {number} [options.nowMs=Date.now()] Horodatage courant
 * @returns {Object} { selected, totalEligible, candidateCount }
 */
export function filterAndRankShoppers(shoppers, storeLocation, options = {}) {
  const requestedRadius = options.radiusKm !== undefined ? options.radiusKm : RADAR_CONFIG.INITIAL_RADIUS_KM;
  // Plafond strict absolu imposé côté Worker : ne peut jamais excéder MAX_RADIUS_KM (10.0 km)
  const radiusKm = Math.min(requestedRadius, RADAR_CONFIG.MAX_RADIUS_KM);
  const maxCandidates = options.maxCandidates || RADAR_CONFIG.MAX_SHOPPERS_PER_WAVE;
  const thresholdMs = options.thresholdMs || RADAR_CONFIG.GPS_FRESHNESS_THRESHOLD_MS;
  const nowMs = options.nowMs || Date.now();
  const excludedSet = new Set(options.excludedUids || []);
  const creatorUid = options.creatorUid || options.clientId || null;
  if (creatorUid) {
    excludedSet.add(creatorUid);
  }

  if (!storeLocation || !isValidCoordinates(storeLocation.latitude, storeLocation.longitude)) {
    throw new Error('Coordonnées du commerce invalides ou absentes.');
  }

  if (!Array.isArray(shoppers)) {
    return { selected: [], totalEligible: 0, candidateCount: 0 };
  }

  const eligibleCandidates = [];

  for (const s of shoppers) {
    if (!s || typeof s !== 'object') continue;
    const uid = s.uid || s.id;
    if (!uid) continue;

    // 0. Exclusion systématique et inconditionnelle du créateur de la course
    if (creatorUid && uid === creatorUid) continue;

    // 1. Compte et rôle shopper valide
    if (s.role !== 'shopper') continue;

    // 2. Disponibilité en ligne
    if (s.isOnline !== true) continue;

    // 3. Pas de mission active incompatible
    if (s.activeErrandId && s.activeErrandId.toString().trim() !== '') continue;

    // 4. Exclusion des shoppers déjà notifiés ou ayant décliné
    if (excludedSet.has(uid)) continue;

    // 5. Coordonnées GPS valides
    const loc = s.location || (s.latitude !== undefined && s.longitude !== undefined ? { latitude: s.latitude, longitude: s.longitude } : null);
    if (!loc || !isValidCoordinates(loc.latitude, loc.longitude)) continue;

    // 6. Fraîcheur GPS stricte (rejet des positions obsolètes > 120s)
    const lastUpdate = s.updatedAt || s.lastSeen;
    if (!isGpsFresh(lastUpdate, thresholdMs, nowMs)) continue;

    // 7. Calcul de la distance à vol d'oiseau (Haversine)
    const distanceKm = haversineDistanceKm(
      storeLocation.latitude,
      storeLocation.longitude,
      loc.latitude,
      loc.longitude
    );

    // 8. Dans le rayon de la vague
    if (distanceKm <= radiusKm) {
      eligibleCandidates.push({
        uid,
        distanceKm,
        location: loc,
        updatedAt: lastUpdate,
        fcmToken: s.fcmToken || null,
        fullName: s.fullName || 'Shopper',
      });
    }
  }

  // 9. Classement par distance croissante avec départage déterministe (alphabetical UID)
  eligibleCandidates.sort((a, b) => {
    if (a.distanceKm !== b.distanceKm) {
      return a.distanceKm - b.distanceKm;
    }
    return a.uid.localeCompare(b.uid);
  });

  const selected = eligibleCandidates.slice(0, maxCandidates);

  return {
    selected,
    totalEligible: eligibleCandidates.length,
    candidateCount: selected.length,
  };
}

/**
 * Récupère l'état persistant du radar depuis Firestore REST.
 */
export async function getRadarState(projectId, errandId, authToken = null, customFetcher = null) {
  if (!errandId) throw new Error('errandId obligatoire.');

  const fetcher = customFetcher || fetch;
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/radar_states/${errandId}`;
  const headers = { 'Accept': 'application/json' };
  if (authToken) headers['Authorization'] = `Bearer ${authToken}`;

  const res = await fetcher(url, { headers });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Erreur Firestore REST radarState: HTTP ${res.status}`);

  const data = await res.json();
  const parsed = parseFirestoreFields(data.fields);
  parsed.errandId = errandId;
  parsed.updateTime = data.updateTime;
  return parsed;
}

/**
 * Enregistre ou met à jour l'état persistant du radar dans Firestore REST.
 */
export async function saveRadarState(projectId, errandId, state, authToken = null, customFetcher = null) {
  if (!errandId || !state) throw new Error('errandId et state obligatoires.');

  const fetcher = customFetcher || fetch;
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/radar_states/${errandId}`;
  const headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  if (authToken) headers['Authorization'] = `Bearer ${authToken}`;

  const formatted = formatFirestoreDocumentFields({
    errandId,
    status: state.status || RADAR_CONFIG.STATUS.ACTIVE,
    currentWave: state.currentWave || 1,
    currentRadiusKm: state.currentRadiusKm || RADAR_CONFIG.INITIAL_RADIUS_KM,
    notifiedShoppers: JSON.stringify(Array.from(state.notifiedShoppers || [])),
    declinedShoppers: JSON.stringify(Array.from(state.declinedShoppers || [])),
    assignedShopperId: state.assignedShopperId || null,
    lastWaveDispatchedAt: state.lastWaveDispatchedAt || new Date().toISOString(),
    nextWaveDueAt: state.nextWaveDueAt || null,
    updatedAt: new Date().toISOString(),
  });

  const res = await fetcher(url, {
    method: 'PATCH',
    headers,
    body: JSON.stringify(formatted),
  });

  if (!res.ok) {
    throw new Error(`Erreur écriture radarState Firestore: HTTP ${res.status}`);
  }

  const resData = await res.json();
  return {
    ...state,
    updateTime: resData.updateTime,
  };
}

/**
 * Extrait les coordonnées géographiques du commerce d'une course.
 */
export function extractStoreCoordinates(errand) {
  if (!errand) return null;

  const tryParse = (val) => {
    if (!val) return null;
    if (typeof val === 'object') return val;
    if (typeof val === 'string') {
      try {
        return JSON.parse(val);
      } catch {
        return null;
      }
    }
    return null;
  };

  // 1. Coordonnées directes du commerce
  const storeLoc = tryParse(errand.storeLocation);
  if (storeLoc && isValidCoordinates(storeLoc.latitude, storeLoc.longitude)) {
    return { latitude: storeLoc.latitude, longitude: storeLoc.longitude };
  }

  const storeGeo = tryParse(errand.storeGeoPoint);
  if (storeGeo && isValidCoordinates(storeGeo.latitude, storeGeo.longitude)) {
    return { latitude: storeGeo.latitude, longitude: storeGeo.longitude };
  }

  if (isValidCoordinates(errand.storeLatitude, errand.storeLongitude)) {
    return { latitude: errand.storeLatitude, longitude: errand.storeLongitude };
  }

  // 2. Coordonnées de livraison (point de référence de la commande en fallback)
  const delivGeo = tryParse(errand.deliveryGeoPoint);
  if (delivGeo && isValidCoordinates(delivGeo.latitude, delivGeo.longitude)) {
    return { latitude: delivGeo.latitude, longitude: delivGeo.longitude };
  }

  const delivLoc = tryParse(errand.deliveryLocation);
  if (delivLoc && isValidCoordinates(delivLoc.latitude, delivLoc.longitude)) {
    return { latitude: delivLoc.latitude, longitude: delivLoc.longitude };
  }

  return null;
}

/**
 * Déclenche une vague de diffusion géolocalisée (Vague 1 ou subséquente).
 */
export async function dispatchRadarWave({
  projectId,
  errandId,
  callerUid = null,
  waveNumber = 1,
  radiusKm = null,
  shoppers = [],
  authToken = null,
  customFetcher = null,
  env = null,
  nowMs = Date.now(),
}) {
  const fetcher = customFetcher || fetch;

  // 1. Relire l'état autoritatif de la course
  const errandUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/errands/${errandId}`;
  const errandHeaders = { 'Accept': 'application/json' };
  if (authToken) errandHeaders['Authorization'] = `Bearer ${authToken}`;

  const errandRes = await fetcher(errandUrl, { headers: errandHeaders });
  if (errandRes.status === 404) {
    throw new Error(`Course '${errandId}' introuvable dans Firestore.`);
  }
  if (!errandRes.ok) {
    throw new Error(`Erreur lecture course Firestore: HTTP ${errandRes.status}`);
  }

  const errandRaw = await errandRes.json();
  const errand = parseFirestoreFields(errandRaw.fields);
  errand.errandId = errandId;

  // 2. Vérification d'état : doit être pending et non assignée
  if (errand.status !== 'pending' || (errand.shopperId && errand.shopperId.trim() !== '')) {
    return {
      success: false,
      stopped: true,
      reason: `La course n'est plus en attente (statut: ${errand.status}, shopperId: ${errand.shopperId}).`,
    };
  }

  // 3. Contrôle de l'émetteur (client créateur ou système)
  if (callerUid && callerUid !== errand.clientId && callerUid !== 'system_radar') {
    throw new Error('Action non autorisée : seul le client créateur peut initier le radar.');
  }

  // 4. Charger l'état persistant du radar
  let radarState = await getRadarState(projectId, errandId, authToken, fetcher);
  if (!radarState) {
    radarState = {
      errandId,
      status: RADAR_CONFIG.STATUS.ACTIVE,
      currentWave: 1,
      currentRadiusKm: RADAR_CONFIG.INITIAL_RADIUS_KM,
      notifiedShoppers: [],
      declinedShoppers: [],
      assignedShopperId: null,
      lastWaveDispatchedAt: new Date(nowMs).toISOString(),
      nextWaveDueAt: new Date(nowMs + RADAR_CONFIG.WAVE_DELAY_SECONDS * 1000).toISOString(),
    };
  } else {
    // Parser les tableaux JSON persistés
    if (typeof radarState.notifiedShoppers === 'string') {
      try { radarState.notifiedShoppers = JSON.parse(radarState.notifiedShoppers); } catch { radarState.notifiedShoppers = []; }
    }
    if (typeof radarState.declinedShoppers === 'string') {
      try { radarState.declinedShoppers = JSON.parse(radarState.declinedShoppers); } catch { radarState.declinedShoppers = []; }
    }
  }

  // Si le radar est déjà terminé, stopper
  if (radarState.status === RADAR_CONFIG.STATUS.ASSIGNED || radarState.status === RADAR_CONFIG.STATUS.CANCELLED) {
    return {
      success: false,
      stopped: true,
      reason: `Diffusion déjà terminée (${radarState.status}).`,
    };
  }

  // 5. Coordonnées de prise en charge
  const storeCoords = extractStoreCoordinates(errand);
  if (!storeCoords) {
    throw new Error('Coordonnées du commerce introuvables sur la course.');
  }

  const calculatedRadius = calculateWaveRadius(waveNumber);
  const effectiveRadius = Math.min(radiusKm || calculatedRadius, RADAR_CONFIG.MAX_RADIUS_KM);

  const creatorUid = errand.clientId || null;
  const excluded = new Set([
    ...(radarState.notifiedShoppers || []),
    ...(radarState.declinedShoppers || []),
  ]);
  if (creatorUid) {
    excluded.add(creatorUid);
  }

  // 6. Sélection et classement des candidats (exclusion formelle du créateur de la course)
  const { selected } = filterAndRankShoppers(shoppers, storeCoords, {
    radiusKm: effectiveRadius,
    maxCandidates: RADAR_CONFIG.MAX_SHOPPERS_PER_WAVE,
    excludedUids: excluded,
    creatorUid,
    thresholdMs: RADAR_CONFIG.GPS_FRESHNESS_THRESHOLD_MS,
    nowMs,
  });

  const newlyNotifiedUids = [];

  // 7. Envoi des notifications ciblées unicast
  let serviceAccount = null;
  if (env?.FIREBASE_SERVICE_ACCOUNT) {
    try {
      serviceAccount = typeof env.FIREBASE_SERVICE_ACCOUNT === 'string'
        ? JSON.parse(env.FIREBASE_SERVICE_ACCOUNT)
        : env.FIREBASE_SERVICE_ACCOUNT;
    } catch {
      // Secret non configuré ou invalide
    }
  }

  let accessToken = null;
  if (serviceAccount) {
    try {
      accessToken = await getGoogleOAuth2AccessToken(serviceAccount);
    } catch {
      accessToken = null;
    }
  }

  for (const candidate of selected) {
    newlyNotifiedUids.push(candidate.uid);
    radarState.notifiedShoppers.push(candidate.uid);

    // Construction de la notification assainie (zéro fuite d'adresse exacte ou de PIN)
    const notificationPayload = processErrandNotificationEvent(
      callerUid || errand.clientId,
      errand,
      ErrandEvents.NEW_ERRAND_AVAILABLE,
      {
        targetShopperUid: candidate.uid,
        distanceKm: candidate.distanceKm,
        isSystemDispatch: true,
      }
    );

    if (accessToken && candidate.fcmToken) {
      try {
        await sendFcmHttpV1Message({
          projectId,
          accessToken,
          targetFcmToken: candidate.fcmToken,
          title: notificationPayload.notification.title,
          body: notificationPayload.notification.body,
          data: {
            errandId,
            eventType: ErrandEvents.NEW_ERRAND_AVAILABLE,
            distanceKm: candidate.distanceKm.toString(),
            storeName: errand.storeName || 'Magasin',
          },
        });
      } catch {
        // En cas d'échec FCM d'un candidat individuel, on poursuit pour les autres
      }
    }
  }

  // 8. Mise à jour de l'état du radar
  radarState.currentWave = waveNumber;
  radarState.currentRadiusKm = effectiveRadius;
  radarState.lastWaveDispatchedAt = new Date(nowMs).toISOString();

  if (selected.length === 0 && waveNumber >= RADAR_CONFIG.MAX_WAVES) {
    radarState.status = RADAR_CONFIG.STATUS.EXHAUSTED;
    radarState.nextWaveDueAt = null;
  } else {
    radarState.status = RADAR_CONFIG.STATUS.ACTIVE;
    radarState.nextWaveDueAt = new Date(nowMs + RADAR_CONFIG.WAVE_DELAY_SECONDS * 1000).toISOString();
  }

  await saveRadarState(projectId, errandId, radarState, authToken, fetcher);

  // 9. Enfilement différé autonome via Cloudflare Queues si configuré (15s)
  let queueEnqueued = false;
  if (
    env?.RADAR_QUEUE &&
    typeof env.RADAR_QUEUE.send === 'function' &&
    radarState.status === RADAR_CONFIG.STATUS.ACTIVE &&
    waveNumber < RADAR_CONFIG.MAX_WAVES
  ) {
    try {
      await env.RADAR_QUEUE.send(
        {
          action: 'advance_radar_wave',
          errandId,
          waveNumber: waveNumber + 1,
          enqueuedAt: nowMs,
          expectedAt: nowMs + RADAR_CONFIG.WAVE_DELAY_SECONDS * 1000,
        },
        {
          delaySeconds: RADAR_CONFIG.WAVE_DELAY_SECONDS,
        }
      );
      queueEnqueued = true;
    } catch (queueErr) {
      console.warn(`[Queue Producer] Échec d'envoi du message différé pour errandId=${errandId}:`, queueErr.message);
    }
  }

  return {
    success: true,
    errandId,
    waveNumber,
    radiusKm: effectiveRadius,
    notifiedShoppersCount: newlyNotifiedUids.length,
    notifiedShoppers: newlyNotifiedUids,
    status: radarState.status,
    nextWaveDueAt: radarState.nextWaveDueAt,
    queueEnqueued,
  };
}

/**
 * Fait avancer durablement le radar vers la vague suivante après écoulement du délai de 15s.
 */
export async function advanceRadarWave({
  projectId,
  errandId,
  shoppers = [],
  authToken = null,
  customFetcher = null,
  env = null,
  nowMs = Date.now(),
  force = false,
}) {
  const fetcher = customFetcher || fetch;

  // 1. Lire la course dans Firestore
  const errandUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/errands/${errandId}`;
  const headers = { 'Accept': 'application/json' };
  if (authToken) headers['Authorization'] = `Bearer ${authToken}`;

  const errandRes = await fetcher(errandUrl, { headers });
  if (!errandRes.ok) {
    return { stopped: true, reason: 'Course inaccessible ou introuvable.' };
  }

  const errandRaw = await errandRes.json();
  const errand = parseFirestoreFields(errandRaw.fields);
  errand.errandId = errandId;

  // Si déjà attribuée ou annulée : neutralisation définitive des vagues
  if (errand.status !== 'pending' || (errand.shopperId && errand.shopperId.trim() !== '')) {
    let radarState = await getRadarState(projectId, errandId, authToken, fetcher);
    if (radarState && radarState.status === RADAR_CONFIG.STATUS.ACTIVE) {
      radarState.status = errand.status === 'cancelled' ? RADAR_CONFIG.STATUS.CANCELLED : RADAR_CONFIG.STATUS.ASSIGNED;
      radarState.nextWaveDueAt = null;
      await saveRadarState(projectId, errandId, radarState, authToken, fetcher);
    }
    return {
      stopped: true,
      reason: `Course déjà attribuée ou statut non pending (${errand.status}).`,
    };
  }

  // 2. Lire l'état du radar
  const radarState = await getRadarState(projectId, errandId, authToken, fetcher);
  if (!radarState) {
    return { stopped: true, reason: 'État du radar introuvable.' };
  }

  if (radarState.status !== RADAR_CONFIG.STATUS.ACTIVE) {
    return { stopped: true, reason: `Radar non actif (${radarState.status}).` };
  }

  // 3. Vérifier l'échéance temporelle (15s)
  if (!force && radarState.nextWaveDueAt) {
    const dueTime = Date.parse(radarState.nextWaveDueAt);
    if (nowMs < dueTime) {
      const remainingSeconds = Math.ceil((dueTime - nowMs) / 1000);
      return {
        pending: true,
        remainingSeconds,
        message: `Délai de vague en cours (encore ${remainingSeconds}s).`,
      };
    }
  }

  const nextWave = (radarState.currentWave || 1) + 1;
  if (nextWave > RADAR_CONFIG.MAX_WAVES) {
    radarState.status = RADAR_CONFIG.STATUS.EXHAUSTED;
    radarState.nextWaveDueAt = null;
    await saveRadarState(projectId, errandId, radarState, authToken, fetcher);
    return {
      exhausted: true,
      message: 'Nombre maximal de vagues atteint sans acceptation.',
    };
  }

  const nextRadiusKm = calculateWaveRadius(nextWave);

  return dispatchRadarWave({
    projectId,
    errandId,
    callerUid: 'system_radar',
    waveNumber: nextWave,
    radiusKm: nextRadiusKm,
    shoppers,
    authToken,
    customFetcher: fetcher,
    env,
    nowMs,
  });
}

/**
 * ATTRIBUTION EXCLUSIVE ATOMIQUE
 *
 * Permet à un shoppeur d'accepter une course avec garantie stricte d'un seul gagnant.
 * Utilise la précondition updateTime de Firestore REST.
 * Rejette les requêtes concurrentes perdantes avec HTTP 409 already_assigned.
 * Idempotent pour le gagnant réitérant sa requête.
 */
export async function handleAtomicAssignment({
  projectId,
  errandId,
  shopperUid,
  authToken = null,
  customFetcher = null,
  env = null,
  nowMs = Date.now(),
}) {
  if (!projectId || !errandId || !shopperUid) {
    throw new Error('Paramètres obligatoires manquants: projectId, errandId, shopperUid.');
  }

  const fetcher = customFetcher || fetch;
  const errandUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/errands/${errandId}`;
  const headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  if (authToken) headers['Authorization'] = `Bearer ${authToken}`;

  // 1. Lire la course autoritativement depuis Firestore REST avec son updateTime
  const getRes = await fetcher(errandUrl, { headers: { 'Accept': 'application/json', ...(authToken ? { 'Authorization': `Bearer ${authToken}` } : {}) } });
  if (getRes.status === 404) {
    return {
      success: false,
      statusCode: 404,
      code: 'errand_not_found',
      message: `Course '${errandId}' introuvable.`,
    };
  }
  if (!getRes.ok) {
    throw new Error(`Erreur Firestore REST lecture course: HTTP ${getRes.status}`);
  }

  const errandRaw = await getRes.json();
  const errand = parseFirestoreFields(errandRaw.fields);
  errand.errandId = errandId;
  const currentUpdateTime = errandRaw.updateTime;

  // 1b. Interdiction formelle d'auto-attribution pour le créateur de la course
  if (errand.clientId && shopperUid === errand.clientId) {
    return {
      success: false,
      statusCode: 403,
      code: 'cannot_assign_own_errand',
      message: "Le créateur de la course ne peut pas s'auto-attribuer sa propre course.",
      errandId,
    };
  }

  // 2. Vérification idempotente : le shopper est-il DÉJÀ le gagnant ?
  if (errand.shopperId === shopperUid) {
    return {
      success: true,
      statusCode: 200,
      code: 'already_assigned_to_caller',
      message: 'Course déjà attribuée à votre profil (idempotence confirmée).',
      errandId,
      shopperId: shopperUid,
      status: errand.status,
    };
  }

  // 3. Vérification de concurrence : déjà attribuée à un tiers
  if (errand.shopperId && errand.shopperId.trim() !== '') {
    return {
      success: false,
      statusCode: 409,
      code: 'already_assigned',
      message: 'Cette course a déjà été attribuée à un autre shoppeur.',
      errandId,
    };
  }

  // 4. Vérification d'état métier : doit être pending
  if (errand.status !== 'pending') {
    return {
      success: false,
      statusCode: 409,
      code: 'errand_not_available',
      message: `La course est au statut '${errand.status}' et ne peut plus être acceptée.`,
      errandId,
    };
  }

  // 5. Vérifier que le shopper n'avait pas précédemment décliné
  const radarState = await getRadarState(projectId, errandId, authToken, fetcher);
  if (radarState) {
    let declinedList = radarState.declinedShoppers;
    if (typeof declinedList === 'string') {
      try { declinedList = JSON.parse(declinedList); } catch { declinedList = []; }
    }
    if (Array.isArray(declinedList) && declinedList.includes(shopperUid)) {
      return {
        success: false,
        statusCode: 403,
        code: 'previously_declined',
        message: 'Vous avez précédemment décliné cette course.',
        errandId,
      };
    }
  }

  // 6. ÉCRITURE CONDITIONNELLE ATOMIQUE FIRESTORE REST
  // Utilise updateMask et la précondition updateTime
  const patchPayload = formatFirestoreDocumentFields({
    shopperId: shopperUid,
    status: 'accepted',
    updatedAt: new Date(nowMs).toISOString(),
  });

  const patchUrl = `${errandUrl}?currentDocument.updateTime=${encodeURIComponent(currentUpdateTime)}&updateMask.fieldPaths=shopperId&updateMask.fieldPaths=status&updateMask.fieldPaths=updatedAt`;

  const patchRes = await fetcher(patchUrl, {
    method: 'PATCH',
    headers,
    body: JSON.stringify(patchPayload),
  });

  if (patchRes.ok) {
    // 7. VICTOIRE EXCLUSIVE : Ce shoppeur a remporté la course !
    if (radarState) {
      radarState.status = RADAR_CONFIG.STATUS.ASSIGNED;
      radarState.assignedShopperId = shopperUid;
      radarState.nextWaveDueAt = null;
      await saveRadarState(projectId, errandId, radarState, authToken, fetcher);
    }

    // 8. Notifications post-attribution
    let serviceAccount = null;
    if (env?.FIREBASE_SERVICE_ACCOUNT) {
      try {
        serviceAccount = typeof env.FIREBASE_SERVICE_ACCOUNT === 'string'
          ? JSON.parse(env.FIREBASE_SERVICE_ACCOUNT)
          : env.FIREBASE_SERVICE_ACCOUNT;
      } catch {
        serviceAccount = null;
      }
    }

    if (serviceAccount) {
      try {
        const accessToken = await getGoogleOAuth2AccessToken(serviceAccount);
        // A. Notifier le client de l'acceptation
        const clientNotif = processErrandNotificationEvent(
          shopperUid,
          { ...errand, shopperId: shopperUid, status: 'accepted' },
          ErrandEvents.ERRAND_ACCEPTED
        );

        // B. Notifier les candidats non retenus
        if (radarState && Array.isArray(radarState.notifiedShoppers)) {
          for (const candUid of radarState.notifiedShoppers) {
            if (candUid !== shopperUid) {
              // Notification de désactivation sans fuite de données
              processErrandNotificationEvent(
                shopperUid,
                { ...errand, shopperId: shopperUid, status: 'accepted' },
                ErrandEvents.ERRAND_NO_LONGER_AVAILABLE,
                { targetShopperUid: candUid }
              );
            }
          }
        }
      } catch {
        // Résilience : l'attribution est actée en base même si le push post-attribution échoue
      }
    }

    return {
      success: true,
      statusCode: 200,
      winner: true,
      errandId,
      shopperId: shopperUid,
      status: 'accepted',
      message: 'Course attribuée avec succès !',
    };
  }

  // 8. CONFLIT DE COURSE CONCURRENTE (HTTP 409 / Precondition Failed)
  // Un autre shoppeur simultané a réussi son écriture un instant plus tôt !
  return {
    success: false,
    statusCode: 409,
    code: 'already_assigned',
    message: 'Cette course a déjà été attribuée à un autre shoppeur lors de la compétition d\'acceptation.',
    errandId,
  };
}

/**
 * Enregistre le refus individuel d'un shopper sans affecter les autres shoppers ni la course.
 */
export async function handleShopperDecline({
  projectId,
  errandId,
  shopperUid,
  authToken = null,
  customFetcher = null,
}) {
  if (!errandId || !shopperUid) {
    throw new Error('errandId et shopperUid obligatoires.');
  }

  const fetcher = customFetcher || fetch;
  let radarState = await getRadarState(projectId, errandId, authToken, fetcher);

  if (!radarState) {
    radarState = {
      errandId,
      status: RADAR_CONFIG.STATUS.ACTIVE,
      currentWave: 1,
      currentRadiusKm: RADAR_CONFIG.INITIAL_RADIUS_KM,
      notifiedShoppers: [],
      declinedShoppers: [shopperUid],
      assignedShopperId: null,
      lastWaveDispatchedAt: new Date().toISOString(),
      nextWaveDueAt: null,
    };
  } else {
    let declined = radarState.declinedShoppers;
    if (typeof declined === 'string') {
      try { declined = JSON.parse(declined); } catch { declined = []; }
    }
    if (!Array.isArray(declined)) declined = [];

    if (!declined.includes(shopperUid)) {
      declined.push(shopperUid);
    }
    radarState.declinedShoppers = declined;
  }

  await saveRadarState(projectId, errandId, radarState, authToken, fetcher);

  return {
    success: true,
    errandId,
    shopperId: shopperUid,
    declined: true,
    message: 'Refus enregistré avec succès. Vous ne recevrez plus d\'alertes pour cette course.',
  };
}

/**
 * Balayage périodique durable des vagues de radar en attente (Cron Trigger Fallback).
 *
 * Permet de faire progresser automatiquement les vagues dont l'échéance (nextWaveDueAt)
 * est expirée, même si l'application client est fermée ou si la file de messages est indisponible.
 *
 * @param {Object} params
 * @param {string} params.projectId Identifiant du projet Firebase
 * @param {Object} [params.env] Environnement Cloudflare Worker
 * @param {Function} [params.customFetcher] Fetcher personnalisé pour tests unitaires
 * @param {number} [params.nowMs=Date.now()] Horodatage courant
 * @returns {Promise<Object>} Résumé du balayage
 */
export async function sweepPendingRadarWaves({
  projectId,
  env = null,
  customFetcher = null,
  nowMs = Date.now(),
}) {
  const fetcher = customFetcher || fetch;
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`;

  // Requête structurée Firestore pour récupérer les radar_states au statut 'active'
  const structuredQuery = {
    structuredQuery: {
      from: [{ collectionId: 'radar_states' }],
      where: {
        fieldFilter: {
          field: { fieldPath: 'status' },
          op: 'EQUAL',
          value: { stringValue: RADAR_CONFIG.STATUS.ACTIVE },
        },
      },
      limit: 20,
    },
  };

  let res;
  try {
    res = await fetcher(url, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(structuredQuery),
    });
  } catch (err) {
    return { success: false, error: err.message, sweptCount: 0 };
  }

  if (!res.ok) {
    return { success: false, status: res.status, sweptCount: 0 };
  }

  const items = await res.json();
  let sweptCount = 0;
  const processed = [];

  for (const item of (Array.isArray(items) ? items : [])) {
    if (!item.document) continue;
    const fields = parseFirestoreFields(item.document.fields);
    const errandId = fields.errandId || item.document.name.split('/').pop();

    if (fields.nextWaveDueAt) {
      const dueTime = new Date(fields.nextWaveDueAt).getTime();
      if (nowMs >= dueTime) {
        try {
          const adv = await advanceRadarWave({
            projectId,
            errandId,
            authToken: null,
            customFetcher: fetcher,
            env,
            nowMs,
            force: true,
          });
          sweptCount++;
          processed.push({ errandId, result: adv });
        } catch (sweepErr) {
          console.warn(`[Cron Sweeper] Échec avancement vague errandId=${errandId}:`, sweepErr.message);
        }
      }
    }
  }

  return { success: true, sweptCount, processed };
}
