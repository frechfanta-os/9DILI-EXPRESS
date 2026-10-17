/**
 * Module d'interrogation de l'état autoritatif Firestore via l'API REST officielle.
 * Évite tout recours aux Cloud Functions ou au SDK lourd en environnement Edge.
 */

/**
 * Convertit un document Firestore REST (avec typage strict) en objet JavaScript standard.
 */
export function parseFirestoreFields(fields) {
  if (!fields || typeof fields !== 'object') return {};

  const result = {};
  for (const [key, valueObj] of Object.entries(fields)) {
    if (valueObj.stringValue !== undefined) {
      result[key] = valueObj.stringValue;
    } else if (valueObj.integerValue !== undefined) {
      result[key] = parseInt(valueObj.integerValue, 10);
    } else if (valueObj.doubleValue !== undefined) {
      result[key] = parseFloat(valueObj.doubleValue);
    } else if (valueObj.booleanValue !== undefined) {
      result[key] = valueObj.booleanValue;
    } else if (valueObj.timestampValue !== undefined) {
      result[key] = valueObj.timestampValue;
    } else if (valueObj.nullValue !== undefined) {
      result[key] = null;
    } else if (valueObj.mapValue !== undefined) {
      result[key] = parseFirestoreFields(valueObj.mapValue.fields);
    } else if (valueObj.arrayValue !== undefined) {
      result[key] = (valueObj.arrayValue.values || []).map((v) => {
        if (v.stringValue !== undefined) return v.stringValue;
        if (v.integerValue !== undefined) return parseInt(v.integerValue, 10);
        if (v.doubleValue !== undefined) return parseFloat(v.doubleValue);
        if (v.booleanValue !== undefined) return v.booleanValue;
        return v;
      });
    } else if (valueObj.geoPointValue !== undefined) {
      result[key] = {
        latitude: valueObj.geoPointValue.latitude,
        longitude: valueObj.geoPointValue.longitude,
      };
    } else {
      result[key] = null;
    }
  }

  return result;
}

/**
 * Récupère une course depuis Firestore de manière autoritative.
 */
export async function getAuthoritativeErrand(projectId, errandId, authToken = null, customFetcher = null) {
  if (!errandId) throw new Error('errandId obligatoire.');

  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/errands/${errandId}`;
  const headers = { 'Accept': 'application/json' };
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`;
  }

  const fetcher = customFetcher || fetch;
  const res = await fetcher(url, { headers });

  if (res.status === 404) {
    return null;
  }
  if (!res.ok) {
    throw new Error(`Erreur Firestore REST: HTTP ${res.status}`);
  }

  const data = await res.json();
  const parsed = parseFirestoreFields(data.fields);
  parsed.errandId = errandId;
  return parsed;
}

/**
 * Récupère le jeton FCM d'un utilisateur depuis son profil Firestore /users/{userId}.
 */
export async function getUserFcmToken(projectId, userId, authToken = null, customFetcher = null) {
  if (!userId) return null;

  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${userId}`;
  const headers = { 'Accept': 'application/json' };
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`;
  }

  const fetcher = customFetcher || fetch;
  const res = await fetcher(url, { headers });

  if (!res.ok) return null;

  const data = await res.json();
  const parsed = parseFirestoreFields(data.fields);
  return parsed.fcmToken || null;
}
