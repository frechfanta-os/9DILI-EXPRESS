import assert from 'node:assert';

const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const PROJECT_ID = 'dili-express';
const BASE_URL = `http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function makeToken(uid) {
  if (!uid) return null;
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    user_id: uid,
    sub: uid,
    aud: PROJECT_ID,
    iss: `https://securetoken.google.com/${PROJECT_ID}`
  })).toString('base64url');
  return `${header}.${payload}.`;
}

async function request(path, options = {}) {
  const { method = 'GET', uid = null, body = null } = options;
  const headers = { 'Content-Type': 'application/json' };
  const token = makeToken(uid);
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const url = `${BASE_URL}/${path}`;
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
    console.log(`[PASS] Scenario ${id}: ${title}`);
    return true;
  } catch (err) {
    console.error(`[FAIL] Scenario ${id}: ${title}`);
    console.error(`       Error: ${err.message}`);
    return false;
  }
}

async function main() {
  console.log(`=== 9DILI EXPRESS — TEST DES RÈGLES DE SÉCURITÉ FIRESTORE ===`);
  console.log(`Target: ${BASE_URL}\n`);

  let passed = 0;
  let total = 10;

  // Initialisation : Création du profil d'un client et d'un shopper pour les tests
  const clientUid = 'client_audit_1';
  const shopperUid = 'shopper_audit_1';
  const rogueUid = 'rogue_user_1';
  const errandId = 'errand_audit_100';

  // 1. Un client authentifié lit son propre profil
  if (await runScenario(1, 'Un client authentifié crée et lit son propre profil', async () => {
    // Création conforme : rôle client, rating 5.0, availableCash 0.0
    const createRes = await request(`users?documentId=${clientUid}`, {
      method: 'POST',
      uid: clientUid,
      body: {
        fields: {
          uid: { stringValue: clientUid },
          fullName: { stringValue: 'Amine Client' },
          role: { stringValue: 'client' },
          rating: { doubleValue: 5.0 },
          availableCash: { doubleValue: 0.0 }
        }
      }
    });
    assert.strictEqual(createRes.status, 200, `Creation should succeed: ${JSON.stringify(createRes.data)}`);

    // Lecture de son propre profil
    const readRes = await request(`users/${clientUid}`, { uid: clientUid });
    assert.strictEqual(readRes.status, 200, 'Client should be allowed to read own profile');
  })) passed++;

  // 2. Un utilisateur tente de modifier son rôle
  if (await runScenario(2, 'Un utilisateur tente de falsifier son rôle en "admin"', async () => {
    const patchRes = await request(`users/${clientUid}?updateMask.fieldPaths=role`, {
      method: 'PATCH',
      uid: clientUid,
      body: {
        fields: {
          uid: { stringValue: clientUid },
          role: { stringValue: 'admin' }, // INTERDIT
          rating: { doubleValue: 5.0 },
          availableCash: { doubleValue: 0.0 }
        }
      }
    });
    assert.strictEqual(patchRes.status, 403, 'Tampering with role MUST be rejected with 403 Forbidden');
  })) passed++;

  // 3. Un utilisateur tente de modifier un solde (availableCash)
  if (await runScenario(3, 'Un utilisateur tente de falsifier son solde (availableCash)', async () => {
    const patchRes = await request(`users/${clientUid}?updateMask.fieldPaths=availableCash`, {
      method: 'PATCH',
      uid: clientUid,
      body: {
        fields: {
          uid: { stringValue: clientUid },
          role: { stringValue: 'client' },
          rating: { doubleValue: 5.0 },
          availableCash: { doubleValue: 999999.0 } // INTERDIT
        }
      }
    });
    assert.strictEqual(patchRes.status, 403, 'Tampering with availableCash MUST be rejected with 403 Forbidden');
  })) passed++;

  // Création du Shopper conforme
  await request(`users?documentId=${shopperUid}`, {
    method: 'POST',
    uid: shopperUid,
    body: {
      fields: {
        uid: { stringValue: shopperUid },
        fullName: { stringValue: 'Karim Shopper' },
        role: { stringValue: 'shopper' },
        rating: { doubleValue: 5.0 },
        availableCash: { doubleValue: 0.0 }
      }
    }
  });

  // Création d'une mission par le Client
  const errandCreateRes = await request(`errands?documentId=${errandId}`, {
    method: 'POST',
    uid: clientUid,
    body: {
      fields: {
        errandId: { stringValue: errandId },
        clientId: { stringValue: clientUid },
        status: { stringValue: 'pending' },
        title: { stringValue: 'Courses Alger' }
      }
    }
  });
  console.log('Errand creation status:', errandCreateRes.status, errandCreateRes.data?.error?.message || '');

  // Enregistrement du PIN secret par le client dans /secrets/pin
  const pinCreateRes = await request(`errands/${errandId}/secrets?documentId=pin`, {
    method: 'POST',
    uid: clientUid,
    body: {
      fields: {
        pin: { stringValue: '7412' }
      }
    }
  });
  console.log('PIN creation status:', pinCreateRes.status, pinCreateRes.data?.error?.message || '');

  // 4. Un shopper tente de lire le PIN d'une autre mission
  if (await runScenario(4, 'Un shopper tente d\'accéder à la sous-collection /secrets/pin', async () => {
    const pinRes = await request(`errands/${errandId}/secrets/pin`, { uid: shopperUid });
    assert.strictEqual(pinRes.status, 403, 'Shopper MUST NOT be allowed to read /secrets/pin (403 Forbidden)');
  })) passed++;

  // 5. Un utilisateur non autorisé tente de lire un ticket / secret
  if (await runScenario(5, 'Un tiers non autorisé tente de lire ou modifier /secrets/pin', async () => {
    const rogueRes = await request(`errands/${errandId}/secrets/pin`, { uid: rogueUid });
    assert.strictEqual(rogueRes.status, 403, 'Unauthorized user MUST be denied access with 403 Forbidden');
  })) passed++;

  // 6. Un shopper tente de s'attribuer une mission par une écriture directe non autorisée
  if (await runScenario(6, 'Un shopper tente de modifier le clientId ou voler l\'attribution', async () => {
    const hijackRes = await request(`errands/${errandId}?updateMask.fieldPaths=clientId`, {
      method: 'PATCH',
      uid: shopperUid,
      body: {
        fields: {
          clientId: { stringValue: shopperUid } // TENTATIVE DE DETOURNEMENT
        }
      }
    });
    assert.strictEqual(hijackRes.status, 403, 'Hijacking errand MUST be rejected with 403 Forbidden');
  })) passed++;

  // 7. Un utilisateur tente de falsifier un montant ou un statut sans ticket
  if (await runScenario(7, 'Passage illégal à "delivering" sans ticketAmount valide', async () => {
    const invalidStatusRes = await request(`errands/${errandId}?updateMask.fieldPaths=status`, {
      method: 'PATCH',
      uid: clientUid,
      body: {
        fields: {
          status: { stringValue: 'delivering' } // Impossible sans passer par le shopper assigné et ticket
        }
      }
    });
    assert.strictEqual(invalidStatusRes.status, 403, 'Illegal status transition without receipt must return 403');
  })) passed++;

  // 8. Une évaluation protégée (rating) est modifiée après création
  if (await runScenario(8, 'Tentative de falsification de la note (rating)', async () => {
    const patchRating = await request(`users/${clientUid}?updateMask.fieldPaths=rating`, {
      method: 'PATCH',
      uid: clientUid,
      body: {
        fields: {
          uid: { stringValue: clientUid },
          role: { stringValue: 'client' },
          rating: { doubleValue: 4.0 }, // Modification interdite
          availableCash: { doubleValue: 0.0 }
        }
      }
    });
    assert.strictEqual(patchRating.status, 403, 'Rating alteration MUST be rejected with 403');
  })) passed++;

  // 9. Un utilisateur non authentifié tente d'accéder aux ressources privées
  if (await runScenario(9, 'Accès non authentifié (anonyme) rejeté', async () => {
    const anonRes = await request(`users/${clientUid}`);
    assert.strictEqual(anonRes.status, 403, 'Anonymous access MUST return 403 Forbidden');
  })) passed++;

  // 10. Un utilisateur légitime exécute les opérations normales
  if (await runScenario(10, 'Opérations légitimes (client consulte PIN, lecture catalogue)', async () => {
    // Le client lit son propre PIN
    const clientPinRes = await request(`errands/${errandId}/secrets/pin`, { uid: clientUid });
    assert.strictEqual(clientPinRes.status, 200, 'Client MUST be allowed to read own PIN');

    // Lecture publique du catalogue de produits
    const catRes = await request('catalog_products/hamoud_selecto_1l', { uid: clientUid });
    // 200 ou 404 (document non créé), mais PAS 403 !
    assert.notStrictEqual(catRes.status, 403, 'Authenticated user must have read access to catalog');
  })) passed++;

  console.log(`\n=== RÉSULTATS DES SCÉNARIOS : ${passed}/${total} VALIDÉS ===\n`);
  if (passed !== total) {
    process.exit(1);
  }
}

main().catch((e) => {
  console.error('Fatal test error:', e);
  process.exit(1);
});
