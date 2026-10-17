/**
 * Module de sécurité et vérification cryptographique des jetons Firebase Auth.
 * Utilise l'API Web Crypto standard pour valider les jetons JWT émis par Google.
 */

const GOOGLE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

let cachedJwks = null;
let jwksCacheExpiry = 0;

/**
 * Récupère le jeu de clés publiques JWKS de Google pour Firebase Auth avec cache mémoire.
 */
export async function getGoogleJwks(customFetcher = null) {
  const now = Date.now();
  if (cachedJwks && now < jwksCacheExpiry) {
    return cachedJwks;
  }

  try {
    const fetcher = customFetcher || fetch;
    const res = await fetcher(GOOGLE_JWKS_URL);
    if (!res.ok) {
      throw new Error(`Échec récupération clés JWKS Google: HTTP ${res.status}`);
    }

    const cacheHeader = res.headers?.get('cache-control');
    let maxAgeSeconds = 3600;
    if (cacheHeader) {
      const match = cacheHeader.match(/max-age=(\d+)/);
      if (match) maxAgeSeconds = parseInt(match[1], 10);
    }

    cachedJwks = await res.json();
    jwksCacheExpiry = now + maxAgeSeconds * 1000;
    return cachedJwks;
  } catch (err) {
    if (cachedJwks) return cachedJwks;
    throw err;
  }
}

/**
 * Convertit une chaîne base64url en Uint8Array.
 */
function base64UrlToUint8Array(base64Url) {
  const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
  const pad = base64.length % 4;
  const padded = pad ? base64 + '='.repeat(4 - pad) : base64;
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * Décode un JWT (header, payload, signature) sans vérification de signature.
 */
export function decodeJwtUnverified(token) {
  if (!token || typeof token !== 'string') {
    throw new Error('Token JWT invalide ou manquant.');
  }

  const parts = token.split('.');
  if (parts.length !== 3) {
    throw new Error('Structure JWT invalide (3 segments attendus).');
  }

  try {
    const header = JSON.parse(atob(parts[0].replace(/-/g, '+').replace(/_/g, '/')));
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    return { header, payload, signature: parts[2] };
  } catch {
    throw new Error('Impossible de décoder le format base64url du JWT.');
  }
}

/**
 * Valide les revendications standards d'un jeton Firebase ID (Issuer, Audience, Expiration, iat, auth_time, sub).
 */
export function validateFirebaseClaims(payload, expectedProjectId = 'dili-express') {
  const now = Math.floor(Date.now() / 1000);
  const clockSkewTolerance = 300; // 5 minutes de tolérance

  // 1. Expiration stricte : le jeton ne doit plus être accepté dès qu'il est expiré
  if (!payload.exp || payload.exp <= now) {
    throw new Error('Jeton Firebase expiré.');
  }

  // 2. Issued At (iat)
  if (payload.iat && payload.iat > (now + clockSkewTolerance)) {
    throw new Error('Jeton Firebase émis dans le futur (iat invalide).');
  }

  // 3. Auth Time
  if (payload.auth_time && payload.auth_time > (now + clockSkewTolerance)) {
    throw new Error('Date d\'authentification dans le futur (auth_time invalide).');
  }

  // 4. Audience (Project ID Firebase)
  if (payload.aud !== expectedProjectId) {
    throw new Error(`Audience non autorisée : reçu ${payload.aud}, attendu ${expectedProjectId}.`);
  }

  // 5. Issuer
  const expectedIssuer = `https://securetoken.google.com/${expectedProjectId}`;
  if (payload.iss !== expectedIssuer) {
    throw new Error(`Émetteur non autorisé : reçu ${payload.iss}, attendu ${expectedIssuer}.`);
  }

  // 6. Sujet / UID
  if (!payload.sub || typeof payload.sub !== 'string' || payload.sub.length === 0) {
    throw new Error('Identifiant utilisateur (sub/uid) manquant dans le jeton.');
  }

  return {
    uid: payload.sub,
    email: payload.email || null,
    authTime: payload.auth_time || null,
  };
}

/**
 * Vérifie cryptographiquement un jeton JWT avec les clés JWKS publiques de Google (RS256).
 */
export async function verifyFirebaseJwtSignature(token, expectedProjectId = 'dili-express', customFetcher = null) {
  const parts = token.split('.');
  if (parts.length !== 3) {
    throw new Error('Structure JWT invalide.');
  }

  const { header, payload } = decodeJwtUnverified(token);

  if (header.alg !== 'RS256') {
    throw new Error(`Algorithme non supporté: ${header.alg} (attendu: RS256).`);
  }
  if (!header.kid) {
    throw new Error('En-tête JWT dépourvu de kid.');
  }

  // Validation des revendications (claims)
  const user = validateFirebaseClaims(payload, expectedProjectId);

  // Recherche de la clé publique Google correspondante au kid
  const jwks = await getGoogleJwks(customFetcher);
  const matchingKey = (jwks.keys || []).find((k) => k.kid === header.kid);
  if (!matchingKey) {
    throw new Error(`Clé publique Google introuvable pour kid: ${header.kid}.`);
  }

  // Importation de la clé JWK via Web Crypto
  const cryptoKey = await crypto.subtle.importKey(
    'jwk',
    matchingKey,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['verify']
  );

  // Vérification de la signature
  const encoder = new TextEncoder();
  const signedData = encoder.encode(`${parts[0]}.${parts[1]}`);
  const signatureBytes = base64UrlToUint8Array(parts[2]);

  const isValid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    signatureBytes,
    signedData
  );

  if (!isValid) {
    throw new Error('Signature cryptographique RS256 invalide pour ce jeton Firebase.');
  }

  return user;
}

/**
 * Point d'entrée principal pour valider le header Authorization: Bearer <token>.
 */
export async function authenticateCaller(authHeader, projectId = 'dili-express', options = {}) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('En-tête Authorization manquant ou invalide (Format: Bearer <token>).');
  }

  const token = authHeader.substring(7).trim();

  // Mode test unitaire déconnecté ou contournement explicite pour tests
  if (options.skipSignatureVerification) {
    const { payload } = decodeJwtUnverified(token);
    return validateFirebaseClaims(payload, projectId);
  }

  // Validation cryptographique complète RS256 en staging et production
  return await verifyFirebaseJwtSignature(token, projectId, options.customFetcher);
}
