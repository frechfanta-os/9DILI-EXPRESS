/**
 * Module d'envoi FCM HTTP v1 avec gestion sécurisée des jetons OAuth2 Google.
 * Le secret du compte de service Google est conservé exclusivement dans les variables
 * d'environnement chiffrées du Worker (wrangler secret) et n'est jamais exposé à l'application.
 */

let cachedAccessToken = null;
let tokenExpiry = 0;

/**
 * Importe une clé privée PEM PKCS#8 pour Web Crypto API (RS256).
 */
async function importPrivateKey(pem) {
  // Nettoyage des balises PEM
  const cleanPem = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\r?\n|\r/g, '')
    .trim();

  const binaryDer = Uint8Array.from(atob(cleanPem), (c) => c.charCodeAt(0));

  return await crypto.subtle.importKey(
    'pkcs8',
    binaryDer.buffer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  );
}

/**
 * Encode un objet en Base64Url sans padding.
 */
function base64UrlEncode(obj) {
  const str = typeof obj === 'string' ? obj : JSON.stringify(obj);
  return btoa(str)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/**
 * Génère un jeton d'accès Google OAuth2 pour l'API FCM HTTP v1.
 */
export async function getGoogleOAuth2AccessToken(serviceAccount, customFetcher = null) {
  const now = Math.floor(Date.now() / 1000);

  // Utilisation du jeton en cache si encore valide (marge de 5 minutes)
  if (cachedAccessToken && now < tokenExpiry - 300) {
    return cachedAccessToken;
  }

  if (!serviceAccount || !serviceAccount.client_email || !serviceAccount.private_key) {
    throw new Error('Identifiants Google Service Account non configurés ou incomplets.');
  }

  // 1. En-tête et assertion JWT
  const header = { alg: 'RS256', typ: 'JWT' };
  const assertionPayload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  };

  const encodedHeader = base64UrlEncode(header);
  const encodedPayload = base64UrlEncode(assertionPayload);
  const dataToSign = new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`);

  // 2. Signature cryptographique RS256 via Web Crypto
  const cryptoKey = await importPrivateKey(serviceAccount.private_key);
  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    dataToSign
  );

  const signatureBase64 = btoa(
    String.fromCharCode(...new Uint8Array(signatureBuffer))
  )
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

  const signedJwt = `${encodedHeader}.${encodedPayload}.${signatureBase64}`;

  // 3. Échange de l'assertion auprès de l'endpoint Google OAuth2
  const fetcher = customFetcher || fetch;
  const tokenRes = await fetcher('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: signedJwt,
    }),
  });

  if (!tokenRes.ok) {
    const errorBody = await tokenRes.text();
    throw new Error(`Échec échange OAuth2 Google: HTTP ${tokenRes.status} (${errorBody})`);
  }

  const tokenData = await tokenRes.json();
  cachedAccessToken = tokenData.access_token;
  tokenExpiry = now + (tokenData.expires_in || 3600);

  return cachedAccessToken;
}

/**
 * Envoie un message de notification via l'API FCM HTTP v1.
 */
export async function sendFcmHttpV1Message({
  projectId,
  accessToken,
  targetFcmToken = null,
  targetTopic = null,
  title,
  body,
  data = {},
  customFetcher = null,
}) {
  if (!targetFcmToken && !targetTopic) {
    throw new Error('Ni token de destination ni topic spécifié pour FCM.');
  }

  const endpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const messagePayload = {
    notification: {
      title,
      body,
    },
    data: {
      ...data,
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },
    android: {
      priority: 'high',
      notification: {
        sound: 'default',
        channel_id: 'errand_updates_channel',
      },
    },
  };

  if (targetFcmToken) {
    messagePayload.token = targetFcmToken;
  } else {
    messagePayload.topic = targetTopic;
  }

  const fetcher = customFetcher || fetch;
  const res = await fetcher(endpoint, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ message: messagePayload }),
  });

  if (!res.ok) {
    const errText = await res.text();
    let isStaleToken = false;
    let errorCode = null;

    try {
      const errJson = JSON.parse(errText);
      const details = errJson.error?.details || [];
      const fcmDetail = details.find((d) => d['@type']?.includes('FcmError'));
      if (fcmDetail) {
        errorCode = fcmDetail.errorCode;
        if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
          isStaleToken = true;
        }
      }
    } catch {
      // Pas de format JSON structuré
    }

    const err = new Error(`Erreur envoi FCM HTTP v1: HTTP ${res.status} (${errText})`);
    err.status = res.status;
    err.isStaleToken = isStaleToken;
    err.errorCode = errorCode;
    throw err;
  }

  return await res.json();
}
