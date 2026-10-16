import assert from 'node:assert';

const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const RTDB_HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || '127.0.0.1:9000';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const PROJECT_ID = 'dili-express';
const RTDB_NS = 'dili-express-default-rtdb';

const FIRESTORE_BASE = `http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const RTDB_BASE = `http://${RTDB_HOST}`;
const AUTH_URL = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`;

// Helper: Authenticate with Auth Emulator to get genuine ID Token and localId
async function createTestAccount(email, password) {
  const res = await fetch(AUTH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true })
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`Auth emulator error: ${JSON.stringify(data)}`);
  }
  return { idToken: data.idToken, uid: data.localId, email };
}

// Firestore REST request
async function fsRequest(path, options = {}) {
  const { method = 'GET', idToken = null, body = null } = options;
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) {
    headers['Authorization'] = `Bearer ${idToken}`;
  }

  const url = `${FIRESTORE_BASE}/${path}`;
  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });

  const data = await res.json().catch(() => null);
  return { status: res.status, ok: res.ok, data };
}

// RTDB REST request
async function rtdbRequest(path, options = {}) {
  const { method = 'GET', idToken = null, body = null } = options;
  const headers = { 'Content-Type': 'application/json' };
  let url = `${RTDB_BASE}/${path}.json?ns=${RTDB_NS}`;
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

let scenarioCount = 0;
async function runStep(stepNum, description, fn) {
  scenarioCount++;
  try {
    await fn();
    console.log(`[PASS] Étape ${stepNum}: ${description}`);
    return true;
  } catch (err) {
    console.error(`[FAIL] Étape ${stepNum}: ${description}`);
    console.error(`       Détail de l'erreur: ${err.message}`);
    return false;
  }
}

async function main() {
  console.log('================================================================');
  console.log('9DILI EXPRESS — SUITE DE VALIDATION FONCTIONNELLE & E2E');
  console.log('Target Firestore: ' + FIRESTORE_BASE);
  console.log('Target RTDB: ' + RTDB_BASE + ' (ns: ' + RTDB_NS + ')');
  console.log('Target Auth: ' + AUTH_URL);
  console.log('================================================================\n');

  let passed = 0;
  const total = 11;
  const errandId = `errand_e2e_${Date.now()}`;
  const clientEmail = `client_${Date.now()}@test.dz`;
  const shopperEmail = `shopper_${Date.now()}@test.dz`;

  // Préparation : Création des identités auprès de Firebase Auth
  const clientUser = await createTestAccount(clientEmail, 'PasswordClient123!');
  const shopperUser = await createTestAccount(shopperEmail, 'PasswordShopper123!');
  const rogueUser = await createTestAccount(`rogue_${Date.now()}@test.dz`, 'PasswordRogue123!');

  // Étape 1 : Inscription et connexion d'un client
  if (await runStep(1, "Inscription et initialisation du profil Client", async () => {
    const res = await fsRequest(`users?documentId=${clientUser.uid}`, {
      method: 'POST',
      idToken: clientUser.idToken,
      body: {
        fields: {
          uid: { stringValue: clientUser.uid },
          fullName: { stringValue: 'Samir Client E2E' },
          role: { stringValue: 'client' },
          rating: { doubleValue: 5.0 },
          availableCash: { doubleValue: 0.0 }
        }
      }
    });
    assert.strictEqual(res.status, 200, `Profile creation should return 200, got ${res.status}`);
  })) passed++;

  // Étape 2 : Création d'une mission par le Client
  if (await runStep(2, "Création de la mission et enregistrement sécurisé du PIN", async () => {
    // 2.1 Création mission
    const errandRes = await fsRequest(`errands?documentId=${errandId}`, {
      method: 'POST',
      idToken: clientUser.idToken,
      body: {
        fields: {
          errandId: { stringValue: errandId },
          clientId: { stringValue: clientUser.uid },
          storeName: { stringValue: 'Supermarché Ardis Alger' },
          deliveryAddress: { stringValue: 'Hydra, Alger' },
          estimatedBudget: { doubleValue: 3500.0 },
          status: { stringValue: 'pending' }
        }
      }
    });
    assert.strictEqual(errandRes.status, 200, `Errand creation should return 200, got ${errandRes.status}`);

    // 2.2 Enregistrement du PIN secret dans /secrets/pin (Strictement réservé au client)
    const pinRes = await fsRequest(`errands/${errandId}/secrets?documentId=pin`, {
      method: 'POST',
      idToken: clientUser.idToken,
      body: {
        fields: {
          pin: { stringValue: '8492' }
        }
      }
    });
    assert.strictEqual(pinRes.status, 200, `PIN storage should return 200, got ${pinRes.status}`);
  })) passed++;

  // Étape 3 : Connexion d'un Shopper et consultation des missions autorisées
  if (await runStep(3, "Connexion du Shopper et consultation des missions disponibles (Radar)", async () => {
    // Initialisation profil Shopper
    await fsRequest(`users?documentId=${shopperUser.uid}`, {
      method: 'POST',
      idToken: shopperUser.idToken,
      body: {
        fields: {
          uid: { stringValue: shopperUser.uid },
          fullName: { stringValue: 'Lyes Shopper E2E' },
          role: { stringValue: 'shopper' },
          rating: { doubleValue: 5.0 },
          availableCash: { doubleValue: 0.0 }
        }
      }
    });

    // Consultation de la mission par le shopper
    const readRes = await fsRequest(`errands/${errandId}`, {
      idToken: shopperUser.idToken
    });
    assert.strictEqual(readRes.status, 200, `Shopper must be able to view pending errands, got ${readRes.status}`);
    assert.strictEqual(readRes.data.fields.status.stringValue, 'pending');
  })) passed++;

  // Étape 4 : Acceptation d'une mission et vérification de son attribution
  if (await runStep(4, "Attribution de la mission au Shopper par le Client (status: accepted)", async () => {
    const assignRes = await fsRequest(`errands/${errandId}?updateMask.fieldPaths=status&updateMask.fieldPaths=shopperId&updateMask.fieldPaths=negotiatedCommission`, {
      method: 'PATCH',
      idToken: clientUser.idToken,
      body: {
        fields: {
          status: { stringValue: 'accepted' },
          shopperId: { stringValue: shopperUser.uid },
          negotiatedCommission: { doubleValue: 450.0 }
        }
      }
    });
    assert.strictEqual(assignRes.status, 200, `Assignment should return 200, got ${assignRes.status}`);

    // Passage en mode achats en magasin (shopping) par le shopper assigné
    const shopRes = await fsRequest(`errands/${errandId}?updateMask.fieldPaths=status`, {
      method: 'PATCH',
      idToken: shopperUser.idToken,
      body: {
        fields: {
          status: { stringValue: 'shopping' }
        }
      }
    });
    assert.strictEqual(shopRes.status, 200, `Transition to shopping should return 200, got ${shopRes.status}`);
  })) passed++;

  // Étape 5 : Enregistrement d'un montant de ticket positif et d'une référence valide (Spark sans Storage)
  if (await runStep(5, "Enregistrement du montant exact (3120 DA) et de la référence ticket", async () => {
    const ticketRes = await fsRequest(`errands/${errandId}?updateMask.fieldPaths=ticketAmount&updateMask.fieldPaths=ticketRef`, {
      method: 'PATCH',
      idToken: shopperUser.idToken,
      body: {
        fields: {
          ticketAmount: { doubleValue: 3120.0 },
          ticketRef: { stringValue: 'TCK-ARDIS-84920' }
        }
      }
    });
    assert.strictEqual(ticketRes.status, 200, `Ticket recording should return 200, got ${ticketRes.status}`);
  })) passed++;

  // Étape 6 : Vérification que le montant seul ne suffit pas pour autoriser la livraison
  if (await runStep(6, "Rejet strict du passage à 'delivering' sans référence/justificatif valide", async () => {
    // Test négatif sur une autre mission temporaire avec montant seul mais sans ticketRef ni photo
    const badErrandId = `errand_fake_${Date.now()}`;
    await fsRequest(`errands?documentId=${badErrandId}`, {
      method: 'POST',
      idToken: clientUser.idToken,
      body: {
        fields: {
          errandId: { stringValue: badErrandId },
          clientId: { stringValue: clientUser.uid },
          shopperId: { stringValue: shopperUser.uid },
          status: { stringValue: 'shopping' }
        }
      }
    });

    // Tentative frauduleuse de passer en delivering avec ticketAmount seul
    const badTransition = await fsRequest(`errands/${badErrandId}?updateMask.fieldPaths=status&updateMask.fieldPaths=ticketAmount`, {
      method: 'PATCH',
      idToken: shopperUser.idToken,
      body: {
        fields: {
          status: { stringValue: 'delivering' },
          ticketAmount: { doubleValue: 2000.0 }
          // Pas de ticketRef ni ticketPhotoUrl
        }
      }
    });
    assert.strictEqual(badTransition.status, 403, `Must reject delivering without proof (403), got ${badTransition.status}`);
  })) passed++;

  // Étape 7 : Vérification que le Shopper ne peut pas lire le PIN secret du client
  if (await runStep(7, "Confidentialité absolue : Le Shopper ne peut pas lire /secrets/pin", async () => {
    const pinLeakRes = await fsRequest(`errands/${errandId}/secrets/pin`, {
      idToken: shopperUser.idToken
    });
    assert.strictEqual(pinLeakRes.status, 403, `Shopper MUST receive 403 on client secret PIN, got ${pinLeakRes.status}`);

    // Vérification que le client y a bien accès
    const clientPinRes = await fsRequest(`errands/${errandId}/secrets/pin`, {
      idToken: clientUser.idToken
    });
    assert.strictEqual(clientPinRes.status, 200, `Client must be able to read own PIN, got ${clientPinRes.status}`);
    assert.strictEqual(clientPinRes.data.fields.pin.stringValue, '8492');
  })) passed++;

  // Étape 8 : Validation du PIN par le mécanisme de remise
  if (await runStep(8, "Vérification du code PIN lors de la remise en main propre", async () => {
    // Passage à delivering d'abord (autorisé car ticketAmount et ticketRef présents)
    const deliverRes = await fsRequest(`errands/${errandId}?updateMask.fieldPaths=status`, {
      method: 'PATCH',
      idToken: shopperUser.idToken,
      body: {
        fields: {
          status: { stringValue: 'delivering' }
        }
      }
    });
    assert.strictEqual(deliverRes.status, 200, `Transition to delivering must succeed, got ${deliverRes.status}`);

    // Tentative avec mauvais PIN -> 403 Forbidden
    const wrongPinRes = await fsRequest(`errands/${errandId}/verification?documentId=delivery_pin`, {
      method: 'POST',
      idToken: shopperUser.idToken,
      body: {
        fields: { pin: { stringValue: '0000' } }
      }
    });
    assert.strictEqual(wrongPinRes.status, 403, `Wrong PIN submission must be rejected, got ${wrongPinRes.status}`);

    // Soumission du bon PIN -> 200 Success
    const correctPinRes = await fsRequest(`errands/${errandId}/verification?documentId=delivery_pin`, {
      method: 'POST',
      idToken: shopperUser.idToken,
      body: {
        fields: { pin: { stringValue: '8492' } }
      }
    });
    assert.strictEqual(correctPinRes.status, 200, `Correct PIN must be accepted, got ${correctPinRes.status}`);
  })) passed++;

  // Étape 9 : Transition vers les états autorisés, puis clôture de la mission
  if (await runStep(9, "Clôture de la mission (status: completed)", async () => {
    const completeRes = await fsRequest(`errands/${errandId}?updateMask.fieldPaths=status`, {
      method: 'PATCH',
      idToken: shopperUser.idToken,
      body: {
        fields: {
          status: { stringValue: 'completed' }
        }
      }
    });
    assert.strictEqual(completeRes.status, 200, `Errand completion must succeed, got ${completeRes.status}`);
  })) passed++;

  // Étape 10 : Nettoyage de la position et des abonnements après clôture (RTDB)
  if (await runStep(10, "Purge des données de suivi GPS dans Realtime Database à la clôture", async () => {
    // 10.1 Le shopper avait poussé sa position active pendant la livraison
    const pushPosRes = await rtdbRequest(`active_errands/${errandId}`, {
      method: 'PUT',
      idToken: shopperUser.idToken,
      body: {
        errandId,
        shopperId: shopperUser.uid,
        clientId: clientUser.uid,
        latitude: 36.7525,
        longitude: 3.0420,
        updatedAt: Date.now()
      }
    });
    assert.strictEqual(pushPosRes.status, 200, `Push active position should succeed, got ${pushPosRes.status}`);

    // 10.2 Nettoyage systématique à la fin de la course (conformité Spark)
    const deleteRes = await rtdbRequest(`active_errands/${errandId}`, {
      method: 'DELETE',
      idToken: shopperUser.idToken
    });
    assert.strictEqual(deleteRes.status, 200, `Clean up of active errand must return 200, got ${deleteRes.status}`);

    // 10.3 Vérification que le nœud est null
    const checkRes = await rtdbRequest(`active_errands/${errandId}`, {
      idToken: clientUser.idToken
    });
    assert.strictEqual(checkRes.data, null, 'Active errand node must be completely deleted from RTDB');
  })) passed++;

  // Étape 11 : Déconnexion et gestion des erreurs réseau (RTDB onDisconnect et Auth)
  if (await runStep(11, "Validation de la présence Shopper et rejet des jetons invalides", async () => {
    // 11.1 Mise à jour de présence du Shopper
    const presRes = await rtdbRequest(`presence/${shopperUser.uid}`, {
      method: 'PUT',
      idToken: shopperUser.idToken,
      body: {
        isOnline: true,
        lastSeen: Date.now()
      }
    });
    assert.strictEqual(presRes.status, 200, `Presence update should succeed, got ${presRes.status}`);

    // 11.2 Rejet catégorique d'une requête sans token (accès anonyme ou session expirée)
    const anonRes = await rtdbRequest(`presence/${shopperUser.uid}`, {
      method: 'PUT',
      idToken: null,
      body: { isOnline: false, lastSeen: Date.now() }
    });
    assert.strictEqual(anonRes.status, 401, `Anonymous RTDB write must return 401, got ${anonRes.status}`);

    // 11.3 Rejet d'un utilisateur tiers essayant de modifier la présence du Shopper
    const roguePres = await rtdbRequest(`presence/${shopperUser.uid}`, {
      method: 'PUT',
      idToken: rogueUser.idToken,
      body: { isOnline: false, lastSeen: Date.now() }
    });
    assert.strictEqual(roguePres.status, 401, `Rogue user cannot alter shopper presence, got ${roguePres.status}`);
  })) passed++;

  console.log(`\n================================================================`);
  console.log(`BILAN DU PARCOURS FONCTIONNEL E2E : ${passed}/${total} ÉTAPES VALIDÉES`);
  console.log('================================================================\n');

  if (passed !== total) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Erreur fatale lors de l\'exécution du workflow:', err);
  process.exit(1);
});
