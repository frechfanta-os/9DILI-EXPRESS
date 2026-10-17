/**
 * Définition stricte des événements métier, validation d'état autoritatif et
 * assainissement des notifications (zéro fuite de données sensibles).
 */

export const ErrandEvents = {
  NEW_ERRAND_AVAILABLE: 'new_errand_available',
  BID_ACCEPTED: 'bid_accepted',
  ERRAND_ACCEPTED: 'errand_accepted',
  SHOPPER_ASSIGNED: 'shopper_assigned',
  ERRAND_NO_LONGER_AVAILABLE: 'errand_no_longer_available',
  RADAR_WAVE_DISPATCHED: 'radar_wave_dispatched',
  NO_SHOPPER_AVAILABLE: 'no_shopper_available',
  SHOPPER_DELIVERING: 'shopper_delivering',
  SHOPPER_ARRIVED: 'shopper_arrived',
  ERRAND_COMPLETED: 'errand_completed',
  ERRAND_CANCELLED: 'errand_cancelled',
};

// Cache d'idempotence et verrouillage en-vol en mémoire (durée de rétention : 15 minutes)
const idempotencyStore = new Map();
const IDEMPOTENCY_TTL_MS = 15 * 60 * 1000;

export const IdempotencyStatus = {
  IN_FLIGHT: 'in_flight',
  COMPLETED: 'completed',
};

/**
 * Nettoie les clés d'idempotence expirées.
 */
function cleanupExpiredIdempotencyKeys() {
  const now = Date.now();
  for (const [key, entry] of idempotencyStore.entries()) {
    if (now - entry.timestamp > IDEMPOTENCY_TTL_MS) {
      idempotencyStore.delete(key);
    }
  }
}

/**
 * Acquiert un verrou d'idempotence atomique pour prévenir les courses concurrentes
 * et les doublons d'envoi.
 */
export function acquireIdempotencyLock(errandId, eventType, clientKey = null) {
  cleanupExpiredIdempotencyKeys();

  const key = clientKey ? `custom_${clientKey}` : `${errandId}_${eventType}`;
  const existing = idempotencyStore.get(key);

  if (existing) {
    if (existing.status === IdempotencyStatus.IN_FLIGHT) {
      return {
        acquired: false,
        key,
        reason: 'in_flight',
        message: 'Une notification identique est déjà en cours de traitement simultané.',
      };
    }
    if (existing.status === IdempotencyStatus.COMPLETED) {
      return {
        acquired: false,
        key,
        reason: 'duplicate',
        message: 'Requête dupliquée : cet événement a déjà été notifié récemment.',
      };
    }
  }

  // Verrouillage immédiat en état IN_FLIGHT
  idempotencyStore.set(key, {
    status: IdempotencyStatus.IN_FLIGHT,
    timestamp: Date.now(),
  });

  return { acquired: true, key };
}

/**
 * Marque l'opération comme finalisée avec succès (état COMPLETED).
 */
export function commitIdempotency(key) {
  if (key && idempotencyStore.has(key)) {
    idempotencyStore.set(key, {
      status: IdempotencyStatus.COMPLETED,
      timestamp: Date.now(),
    });
  }
}

/**
 * Libère le verrou en cas d'échec transitoire pour permettre une retentative légitime.
 */
export function releaseIdempotencyLock(key) {
  if (key) {
    idempotencyStore.delete(key);
  }
}

/**
 * Rétro-compatibilité : vérifie et enregistre une clé d'idempotence.
 */
export function checkAndRegisterIdempotency(errandId, eventType, clientKey = null) {
  const lock = acquireIdempotencyLock(errandId, eventType, clientKey);
  if (!lock.acquired) return false;
  commitIdempotency(lock.key);
  return true;
}

/**
 * Réinitialise le store d'idempotence (pour tests).
 */
export function resetIdempotencyStore() {
  idempotencyStore.clear();
}

/**
 * Valide l'adéquation entre l'appelant authentifié, l'état Firestore et l'événement demandé.
 * Retourne la charge utile FCM assainie et l'identifiant du destinataire.
 */
export function processErrandNotificationEvent(callerUid, errand, eventType, options = {}) {
  if (!errand || typeof errand !== 'object') {
    throw new Error('Course introuvable dans Firestore.');
  }

  const errandId = errand.errandId;
  const clientId = errand.clientId;
  const shopperId = errand.shopperId;
  const status = errand.status;
  const storeName = errand.storeName || 'Magasin';

  let recipientUid = null;
  let isTopicBroadcast = false;
  let topicName = null;
  let title = '';
  let body = '';

  switch (eventType) {
    case ErrandEvents.NEW_ERRAND_AVAILABLE:
      // Déclenché par le Client créateur ou le système de radar
      if (callerUid && callerUid !== clientId && !options.isSystemDispatch) {
        throw new Error('Action non autorisée : seul le client créateur peut diffuser une nouvelle demande.');
      }
      if (status !== 'pending') {
        throw new Error(`État Firestore non conforme : attendu 'pending', actuel '${status}'.`);
      }

      if (options.targetShopperUid) {
        // Exclusion formelle : le créateur ne peut en aucun cas recevoir une offre radar pour sa propre course
        if (clientId && options.targetShopperUid === clientId) {
          throw new Error("Action non autorisée : le créateur ne peut pas recevoir d'offre pour sa propre course.");
        }
        // Ciblage unicast individuel du shopper éligible (Radar intelligent)
        isTopicBroadcast = false;
        recipientUid = options.targetShopperUid;
        title = 'Nouvelle Course à Proximité 🛍️';
        const distText = options.distanceKm !== undefined ? ` (${options.distanceKm} km)` : '';
        body = `Course disponible à ${storeName}${distText}. Consultez le radar pour accepter !`;
      } else {
        // Rétro-compatibilité broadcast topic
        isTopicBroadcast = true;
        topicName = 'available_errands';
        title = '9DILI EXPRESS 🛍️';
        body = `Nouvelle course disponible à ${storeName}. Consultez le radar !`;
      }
      break;

    case ErrandEvents.BID_ACCEPTED:
      // Déclenché par le Client lorsque l'offre d'un shopper est retenue
      if (callerUid !== clientId) {
        throw new Error('Action non autorisée : seul le client peut valider une offre.');
      }
      if (status !== 'accepted' && status !== 'shopping') {
        throw new Error(`État Firestore non conforme : attendu 'accepted', actuel '${status}'.`);
      }
      if (!shopperId) {
        throw new Error('Aucun Shopper assigné à cette course.');
      }
      recipientUid = shopperId;
      title = 'Offre Validée ! 🎉';
      body = `Le client a accepté votre proposition pour ${storeName}. Vous pouvez démarrer les achats.`;
      break;

    case ErrandEvents.ERRAND_ACCEPTED:
      // Notification au Client créateur qu'un shopper a accepté la course
      if (status !== 'accepted' && status !== 'shopping') {
        throw new Error(`État Firestore non conforme : attendu 'accepted', actuel '${status}'.`);
      }
      recipientUid = clientId;
      title = 'Shopper Assigné ! 🛵';
      body = `Votre course à ${storeName} a été acceptée par votre shoppeur.`;
      break;

    case ErrandEvents.SHOPPER_ASSIGNED:
      // Notification au Shopper gagnant
      if (!shopperId) {
        throw new Error('Aucun Shopper assigné à cette course.');
      }
      recipientUid = shopperId;
      title = 'Mission Remportée ! 🎉';
      body = `Vous êtes assigné à la course pour ${storeName}. Rendez-vous en magasin !`;
      break;

    case ErrandEvents.ERRAND_NO_LONGER_AVAILABLE:
      // Notification aux autres candidats informés de l'attribution concurrente
      if (!options.targetShopperUid) {
        throw new Error('targetShopperUid requis pour errand_no_longer_available.');
      }
      if (clientId && options.targetShopperUid === clientId) {
        throw new Error("Action non autorisée : le créateur ne peut pas recevoir d'invalidation pour sa propre course.");
      }
      recipientUid = options.targetShopperUid;
      title = 'Course Déjà Prise ⏱️';
      body = `La course pour ${storeName} a été attribuée à un autre shoppeur.`;
      break;

    case ErrandEvents.NO_SHOPPER_AVAILABLE:
      // Notification au Client lors de l'épuisement du radar
      recipientUid = clientId;
      title = 'Aucun Shopper Disponible 📍';
      body = `Aucun shoppeur disponible n'a pu prendre en charge votre course pour ${storeName}.`;
      break;

    case ErrandEvents.SHOPPER_DELIVERING:
      // Déclenché par le Shopper lorsque le ticket est payé et qu'il commence la livraison
      if (callerUid !== shopperId) {
        throw new Error('Action non autorisée : seul le Shopper assigné peut notifier le départ en livraison.');
      }
      if (status !== 'delivering') {
        throw new Error(`État Firestore non conforme : attendu 'delivering', actuel '${status}'.`);
      }
      recipientUid = clientId;
      title = 'Votre Shopper est en Route 🛵';
      body = `Vos articles ont été achetés à ${storeName}. Le livreur se dirige vers votre adresse.`;
      break;

    case ErrandEvents.SHOPPER_ARRIVED:
      // Déclenché par le Shopper à l'arrivée chez le client
      if (callerUid !== shopperId) {
        throw new Error('Action non autorisée : seul le Shopper assigné peut signaler son arrivée.');
      }
      if (status !== 'delivering') {
        throw new Error(`État Firestore non conforme : attendu 'delivering', actuel '${status}'.`);
      }
      recipientUid = clientId;
      title = 'Votre Shopper est Arrivé 📍';
      body = 'Le livreur est au point de remise. Préparez votre règlement en espèces et votre code PIN.';
      break;

    case ErrandEvents.ERRAND_COMPLETED:
      // Déclenché lors de la remise validée par le handshake
      if (callerUid !== shopperId) {
        throw new Error('Action non autorisée : seul le Shopper assigné peut clôturer la remise.');
      }
      if (status !== 'completed') {
        throw new Error(`État Firestore non conforme : attendu 'completed', actuel '${status}'.`);
      }
      recipientUid = clientId;
      title = 'Livraison Terminée avec Succès ✅';
      body = `Votre commande à ${storeName} a été livrée. Merci de faire confiance à 9DILI EXPRESS !`;
      break;

    case ErrandEvents.ERRAND_CANCELLED:
      // Déclenché lors de l'annulation par l'un des deux participants
      if (callerUid !== clientId && callerUid !== shopperId && !options.isSystemDispatch) {
        throw new Error('Action non autorisée : seul un participant à la course peut notifier une annulation.');
      }
      if (status !== 'cancelled') {
        throw new Error(`État Firestore non conforme : attendu 'cancelled', actuel '${status}'.`);
      }
      // La notification va à l'autre partie
      recipientUid = callerUid === clientId ? shopperId : clientId;
      title = 'Course Annulée ⚠️';
      body = `La course pour ${storeName} a été annulée.`;
      break;

    default:
      throw new Error(`Type d'événement inconnu ou non supporté : '${eventType}'.`);
  }

  // CONTRÔLE DE SÉCURITÉ ABSOLU : Assainissement de la charge utile FCM
  // Aucun code PIN, aucune coordonnée GPS brute, aucun token technique.
  const sanitizedNotification = {
    title,
    body,
    errandId,
    eventType,
    timestamp: new Date().toISOString(),
  };

  return {
    isTopicBroadcast,
    topicName,
    recipientUid,
    notification: sanitizedNotification,
  };
}
