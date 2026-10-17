/**
 * Configuration Centralisée du Radar Intelligent de Diffusion des Commandes.
 *
 * Paramètres maîtrisés pour respecter les quotas gratuits du plan Firebase Spark
 * et optimiser la réactivité de prise en charge des livraisons.
 */

export const RADAR_CONFIG = {
  // Rayon initial de recherche à vol d'oiseau (km)
  INITIAL_RADIUS_KM: 2.0,

  // Rayon maximal de diffusion (km) - Plafond absolu strict
  MAX_RADIUS_KM: 10.0,

  // Incrément de rayon à chaque vague successive (km)
  // Vague 1: 2.0 km | Vague 2: 5.0 km | Vague 3: 8.0 km | Vague 4: 10.0 km (strictement plafonné)
  RADIUS_INCREMENT_KM: 3.0,

  // Nombre maximum de shoppers notifiés par vague
  MAX_SHOPPERS_PER_WAVE: 10,

  // Délai de temporisation durable avant déclenchement de la vague suivante (secondes)
  WAVE_DELAY_SECONDS: 15,

  // Nombre maximal de vagues avant épuisement de la diffusion
  MAX_WAVES: 4,

  // Seuil de fraîcheur GPS maximale tolérée (millisecondes)
  // 120 000 ms = 2 minutes. Toute position GPS plus ancienne est déclarée obsolète et exclue.
  GPS_FRESHNESS_THRESHOLD_MS: 120 * 1000,

  // Durée de validité du verrou d'orchestration radar (secondes)
  RADAR_LOCK_TTL_SECONDS: 60,

  // Statuts de l'état de diffusion du radar
  STATUS: {
    IDLE: 'idle',
    ACTIVE: 'active',
    ASSIGNED: 'assigned',
    EXHAUSTED: 'exhausted',
    CANCELLED: 'cancelled',
  },
};
