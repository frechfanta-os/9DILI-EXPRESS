/**
 * Calculs géographiques et validation des coordonnées pour 9DILI EXPRESS.
 */

/**
 * Calcule la distance orthodromique (à vol d'oiseau) entre deux coordonnées GPS
 * en kilomètres selon la formule de Haversine.
 *
 * @param {number} lat1 Latitude point 1
 * @param {number} lon1 Longitude point 1
 * @param {number} lat2 Latitude point 2
 * @param {number} lon2 Longitude point 2
 * @returns {number} Distance en kilomètres (arrondie à 2 décimales)
 */
export function haversineDistanceKm(lat1, lon1, lat2, lon2) {
  if (
    typeof lat1 !== 'number' ||
    typeof lon1 !== 'number' ||
    typeof lat2 !== 'number' ||
    typeof lon2 !== 'number'
  ) {
    throw new TypeError('Toutes les coordonnées doivent être des nombres.');
  }

  const R = 6371.0; // Rayon moyen de la Terre en kilomètres
  const toRad = (deg) => (deg * Math.PI) / 180.0;

  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const distance = R * c;

  // Arrondi à 2 décimales pour cohérence
  return Math.round(distance * 100) / 100;
}

/**
 * Valide si les coordonnées sont des nombres finis compris dans les bornes WGS-84.
 * Latitude : [-90.0, 90.0], Longitude : [-180.0, 180.0]
 */
export function isValidCoordinates(lat, lon) {
  if (typeof lat !== 'number' || typeof lon !== 'number') return false;
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return false;
  return lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0;
}

/**
 * Vérifie si une position GPS est suffisamment fraîche par rapport au seuil configuré.
 *
 * @param {number|string|Date} updatedAt Horodatage de dernière mise à jour
 * @param {number} thresholdMs Seuil maximal d'obsolescence (ex: 120 000 ms = 2 min)
 * @param {number} [nowMs] Horodatage courant de référence
 * @returns {boolean}
 */
export function isGpsFresh(updatedAt, thresholdMs = 120000, nowMs = Date.now()) {
  if (!updatedAt) return false;

  let timestampMs;
  if (typeof updatedAt === 'number') {
    timestampMs = updatedAt;
  } else if (typeof updatedAt === 'string') {
    timestampMs = Date.parse(updatedAt);
  } else if (updatedAt instanceof Date) {
    timestampMs = updatedAt.getTime();
  } else {
    return false;
  }

  if (isNaN(timestampMs)) return false;

  const ageMs = nowMs - timestampMs;
  // Rejette les timestamps dans le futur de plus de 10s ou plus vieux que le seuil
  return ageMs >= -10000 && ageMs <= thresholdMs;
}
