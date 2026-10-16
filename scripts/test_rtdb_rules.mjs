import assert from 'node:assert';

const RTDB_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const PROJECT_ID = 'dili-express-default-rtdb';
const BASE_URL = `http://${RTDB_HOST}`;
const AUTH_URL = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`;

async function getAuthToken(email, password) {
  const res = await fetch(AUTH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true })
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`Auth emulator error: ${JSON.stringify(data)}`);
  }
  return { idToken: data.idToken, localId: data.localId };
}

async function request(path, options = {}) {
  const { method = 'GET', idToken = null, body = null } = options;
  const headers = { 'Content-Type': 'application/json' };
  let url = `${BASE_URL}/${path}.json?ns=${PROJECT_ID}`;
  if (idToken) {
    url += `&auth=${idToken}`;
  }

  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });

  const data = await res.json().catch(() => null);
  return { status: res.status, ok: res.ok, data };
}

async function runScenario(id, title, testFn) {
  try {
    await testFn();
    console.log(`[PASS] RTDB Scenario ${id}: ${title}`);
    return true;
  } catch (err) {
    console.error(`[FAIL] RTDB Scenario ${id}: ${title}`);
    console.error(`       Error: ${err.message}`);
    return false;
  }
}

async function main() {
  console.log(`=== 9DILI EXPRESS — TEST DES RÈGLES REALTIME DATABASE ===`);
  console.log(`Target: ${BASE_URL} (Namespace: ${PROJECT_ID})\n`);

  let passed = 0;
  let total = 6;

  // Création des comptes de test auprès de l'émulateur Auth
  const shopperA = await getAuthToken('shopper_a@test.dz', 'Password123!');
  const shopperB = await getAuthToken('shopper_b@test.dz', 'Password123!');
  const clientC = await getAuthToken('client_c@test.dz', 'Password123!');
  const errandId = 'mission_active_50';

  // 1. Accès public non authentifié rejeté
  if (await runScenario(1, 'Refus des accès non authentifiés (règle racine)', async () => {
    const unauthRead = await request(`presence/${shopperA.localId}`);
    assert.strictEqual(unauthRead.status, 401, 'Public read must be rejected with 401');
    const unauthWrite = await request(`presence/${shopperA.localId}`, {
      method: 'PUT',
      body: { isOnline: true, lastSeen: Date.now() }
    });
    assert.strictEqual(unauthWrite.status, 401, 'Public write must be rejected with 401');
  })) passed++;

  // 2. Le Shopper met à jour sa présence
  if (await runScenario(2, 'Le Shopper met à jour sa présence (isOnline, lastSeen)', async () => {
    const res = await request(`presence/${shopperA.localId}`, {
      method: 'PUT',
      idToken: shopperA.idToken,
      body: { isOnline: true, lastSeen: Date.now() }
    });
    assert.strictEqual(res.status, 200, `Shopper must update own presence: ${JSON.stringify(res.data)}`);
  })) passed++;

  // 3. Un utilisateur tente de modifier la présence d'un tiers
  if (await runScenario(3, 'Un utilisateur ne peut pas modifier la présence d\'autrui', async () => {
    const res = await request(`presence/${shopperA.localId}`, {
      method: 'PUT',
      idToken: shopperB.idToken,
      body: { isOnline: false, lastSeen: Date.now() }
    });
    assert.strictEqual(res.status, 401, 'Tampering with other presence must be rejected');
  })) passed++;

  // 4. Tentative d'injection de champs métier protégés (role, availableCash, admin)
  if (await runScenario(4, 'Interdiction d\'injecter des données métier (role, availableCash) dans RTDB', async () => {
    const res = await request(`shopper_locations/${shopperA.localId}`, {
      method: 'PUT',
      idToken: shopperA.idToken,
      body: {
        latitude: 36.7538,
        longitude: 3.0588,
        timestamp: Date.now(),
        role: 'admin', // INTERDIT
        availableCash: 999999 // INTERDIT
      }
    });
    assert.strictEqual(res.status, 401, 'Injecting business fields in RTDB location MUST be rejected');
  })) passed++;

  // 5. Validation des coordonnées géographiques (ex: latitude > 90 rejetée)
  if (await runScenario(5, 'Rejet des coordonnées géographiques hors limites', async () => {
    const res = await request(`shopper_locations/${shopperA.localId}`, {
      method: 'PUT',
      idToken: shopperA.idToken,
      body: {
        latitude: 195.0, // Invalide (> 90)
        longitude: 3.0588,
        timestamp: Date.now()
      }
    });
    assert.strictEqual(res.status, 401, 'Invalid coordinates must fail validation');
  })) passed++;

  // 6. Suivi de course active partagé uniquement entre Client et Shopper
  if (await runScenario(6, 'Suivi de course active restreint au Client et au Shopper', async () => {
    // Création par le Shopper assigné
    const createRes = await request(`errand_tracking/${errandId}`, {
      method: 'PUT',
      idToken: shopperA.idToken,
      body: {
        shopperId: shopperA.localId,
        clientId: clientC.localId,
        latitude: 36.7538,
        longitude: 3.0588,
        updatedAt: Date.now()
      }
    });
    assert.strictEqual(createRes.status, 200, `Shopper must be allowed to create tracking: ${JSON.stringify(createRes.data)}`);

    // Lecture par le client de la mission : autorisée
    const clientRead = await request(`errand_tracking/${errandId}`, { idToken: clientC.idToken });
    assert.strictEqual(clientRead.status, 200, 'Client of errand must be allowed to read tracking');

    // Lecture par un tiers non concerné : refusée
    const rogueRead = await request(`errand_tracking/${errandId}`, { idToken: shopperB.idToken });
    assert.strictEqual(rogueRead.status, 401, 'Unrelated third party must be denied tracking read');
  })) passed++;

  console.log(`\n=== RÉSULTATS DES SCÉNARIOS RTDB : ${passed}/${total} VALIDÉS ===\n`);
  if (passed !== total) {
    process.exit(1);
  }
}

main().catch((e) => {
  console.error('Fatal RTDB test error:', e);
  process.exit(1);
});
