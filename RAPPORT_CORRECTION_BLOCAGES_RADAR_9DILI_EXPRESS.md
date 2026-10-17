# 9DILI EXPRESS — RAPPORT DE CORRECTION DES BLOCAGES DU RADAR

> **Date** : 17 Octobre 2026  
> **Branche Git** : `main`  
> **Commit de référence audité** : `36e5c3d2da989fe911ba460db65978de0873d159`  
> **Statut** : ✅ **CORRECTIONS APPLIQUÉES ET VALIDÉES PAR TESTS AUTOMATISÉS**  
> **Environnement** : Android / Termux / Ubuntu PRoot / Node.js 20 / Flutter 3.29.0 / Dart 3.7.0  
> **Règles d'intervention** : Modifications strictement locales, aucun commit/push Git, aucun déploiement distant, aucun secret manipulé.

---

## 1. Synthèse Exécutive

Faisant suite aux conclusions de l'audit technique (`AUDIT_FINAL_RADAR_9DILI_EXPRESS.md`), une intervention de correction ciblée a été menée sur le code local de l'application Flutter et du Worker Cloudflare de notifications.

Les deux problématiques identifiées ont été traitées, résolues et verrouillées par des tests de régression automatisés :

1. **Exclusion stricte et inconditionnelle du créateur de la course** :
   - Élimination formelle du créateur (`errand.clientId`) des candidats au radar dans `filterAndRankShoppers()` et `dispatchRadarWave()`, même si ce dernier dispose du rôle `shopper`, est en ligne, avec un GPS valide à moins de 200 m du commerce.
   - Verrouillage anti-contournement dans `processErrandNotificationEvent()` (rejet de l'émission FCM) et dans `handleAtomicAssignment()` / `/api/radar/accept` (rejet HTTP 403 `cannot_assign_own_errand`).
2. **Réconciliation architecturale de l'attribution atomique avec les règles Firestore** :
   - Clarification et sécurisation de la frontière d'autorisation : confirmation que les règles Firestore de production (`firestore.rules`) interdisent à tout commissionnaire non assigné de s'auto-attribuer une course directement via le SDK client (`PERMISSION_DENIED`).
   - L'endpoint Worker `/api/radar/accept` constitue la passerelle exclusive et sécurisée pour les shoppeurs candidats, validant l'attribution atomique via l'API REST Firestore sous privilège de compte de service avec précondition `updateTime`.
   - Ajout d'une garde de sécurité explicite dans `assignShopperAtomic()` (`errand_service.dart`) et dans `handleAtomicAssignment()` (`radar_service.js`) interdisant expressément l'auto-attribution au créateur (`clientId == shopperId`).

### Résultats des Vérifications Locales
- **Worker Cloudflare (`workers/notifications_dispatcher`)** : **79/79 tests passés avec succès** (dont 5 nouveaux tests de sécurité dédiés aux correctifs).
- **Application Flutter (`dili_express`)** : **78/78 tests passés avec succès** (dont 1 nouveau test unitaire sur la garde d'auto-attribution).
- **Analyse Statique Flutter (`flutter analyze`)** : **0 issue trouvée** (codebase 100% propre).

---

## 2. Problème A — Exclusion Systématique du Créateur de la Course

### 2.1 Cause Racine Identifiée
Dans l'implémentation antérieure :
- `filterAndRankShoppers()` vérifiait uniquement `s.role === 'shopper'`, `s.isOnline === true`, la fraîcheur GPS et la distance. Si le client créateur possédait un profil hybride ou shopper actif, ses coordonnées GPS valides et sa proximité géographique l'incluaient dans les candidats de la vague 1.
- `dispatchRadarWave()` initialisait la liste d'exclusion uniquement avec `radarState.notifiedShoppers` et `radarState.declinedShoppers`, omettant d'y insérer `errand.clientId`.
- Aucune barrière n'empêchait le créateur d'appeler l'endpoint d'acceptation `/api/radar/accept` pour sa propre course.

### 2.2 Correctifs Techniques Appliqués

#### A. Filtrage et Classement (`workers/notifications_dispatcher/src/radar_service.js`)
- Signature enrichie avec support de `options.creatorUid` (ou alias `options.clientId`).
- Insertion systématique du `creatorUid` dans l'ensemble d'exclusion `excludedSet`.
- Garde prioritaire dans la boucle d'évaluation des candidats :
  ```javascript
  // 0. Exclusion systématique et inconditionnelle du créateur de la course
  if (creatorUid && uid === creatorUid) continue;
  ```

#### B. Déclenchement de Vague (`dispatchRadarWave`)
- Récupération autoritative de `creatorUid = errand.clientId`.
- Insertion immédiate dans le `Set` des exclus avant sélection :
  ```javascript
  const creatorUid = errand.clientId || null;
  const excluded = new Set([
    ...(radarState.notifiedShoppers || []),
    ...(radarState.declinedShoppers || []),
  ]);
  if (creatorUid) {
    excluded.add(creatorUid);
  }
  ```
- Transmission explicite du paramètre `creatorUid` à `filterAndRankShoppers()`.

#### C. Garde à l'Attribution Atomique (`handleAtomicAssignment`)
- Avant toute écriture ou confirmation idempotente, vérification stricte :
  ```javascript
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
  ```

#### D. Barrière Événements FCM (`workers/notifications_dispatcher/src/events.js`)
- Dans `processErrandNotificationEvent()` pour l'événement `NEW_ERRAND_AVAILABLE` :
  ```javascript
  if (options.targetShopperUid) {
    // Exclusion formelle : le créateur ne peut en aucun cas recevoir une offre radar pour sa propre course
    if (clientId && options.targetShopperUid === clientId) {
      throw new Error("Action non autorisée : le créateur ne peut pas recevoir d'offre pour sa propre course.");
    }
  ```
- Même garde de rejet ajoutée sur `ERRAND_NO_LONGER_AVAILABLE`.

---

## 3. Problème B — Attribution Atomique et Règles Firestore

### 3.1 Analyse Comparative des Chemins d'Attribution

| Chemin | Méthode / Endpoint | Initiateur | Règle Firestore (`firestore.rules`) | Verdict & Sécurité |
| :--- | :--- | :--- | :--- | :--- |
| **Acceptation d'une offre (Bid)** | `acceptBidAtomic()` (`errand_service.dart`) | Client créateur (`clientId`) | **Autorisé** (`resource.data.clientId == request.auth.uid` et statut passe à `accepted`) | Conforme aux règles Firestore. Transaction client sécurisée. |
| **Confirmation après appel** | `confirmErrandAssignment()` (`errand_service.dart`) | Client créateur (`clientId`) | **Autorisé** (`resource.data.clientId == request.auth.uid`) | Conforme. Le client confirme que l'appel a eu lieu. |
| **Acceptation Radar directe Client** | `assignShopperAtomic()` (`errand_service.dart`) | Shopper candidat (`auth.uid`) | **REJETÉ** (`PERMISSION_DENIED`) par les règles Firestore locales ! | **Sécurisé par design** : Un tiers non assigné ne peut pas modifier la course directement. |
| **Acceptation Radar via Worker** | `POST /api/radar/accept` (`radar_service.js`) | Shopper candidat (`auth.uid`) | **Autorisé via Service Account** (REST API Firestore avec précondition `currentDocument.updateTime`) | **Chemin officiel unique et autoritatif**. Verrouillage atomique distribué garanti. |

### 3.2 Analyse de `firestore.rules` (Intégrité Préservée)
Les lignes 58 à 90 de `firestore.rules` disposent :
```javascript
allow update: if isAuthenticated() && (
  // Cas A : Le client créateur modifie sa course (annulation, acceptation d'offre)
  (resource.data.clientId == request.auth.uid && ...) ||
  // Cas B : Le shoppeur DÉJÀ ASSIGNÉ met à jour sa position ou le flux de livraison
  (resource.data.shopperId == request.auth.uid && ...)
);
```

**Constats de sécurité majeurs :**
1. Un shoppeur candidat ayant reçu un push n'est ni le `clientId` (créateur), ni le `shopperId` (qui est alors `null`).
2. Tout contournement direct depuis l'application via le SDK Firestore client pour s'approprier la course est **mécaniquement bloqué** au niveau du moteur de règles Firebase avec une erreur de permission.
3. Il n'a **pas été nécessaire d'affaiblir les règles Firestore**, préservant ainsi la stricte isolation des données.
4. L'endpoint Worker `/api/radar/accept` assure le rôle de tiers de confiance :
   - Il valide l'identité du candidat via son jeton JWT Firebase Auth RS256.
   - Il vérifie que le candidat n'a pas décliné la course.
   - Il applique le patch atomique avec la précondition `currentDocument.updateTime` garantissant qu'un seul gagnant remporte la course et que tous les concurrents concurrents reçoivent un HTTP 409 `already_assigned`.

### 3.3 Mise à Jour de `assignShopperAtomic()` (`errand_service.dart`)
Pour garantir la cohérence absolue entre le client mobile et le Worker, `assignShopperAtomic()` a été mis à jour :
1. **Documentation architecturale exhaustive** expliquant la frontière entre le SDK client et le Worker backend.
2. **Garde d'auto-attribution** :
   ```dart
   final currentClientId = data['clientId'];
   if (currentClientId != null && currentClientId == shopperId) {
     throw StateError(
       "cannot_assign_own_errand: Le créateur de la course ne peut pas s'auto-attribuer sa propre course.",
     );
   }
   ```

---

## 4. Matrice de Tests Automatisés de Non-Régression

### 4.1 Tests Unitaires & E2E Worker Cloudflare (`radar.test.js`)

| N° | Intitulé du Test | Composant Cible | Résultat |
| :---: | :--- | :--- | :---: |
| **41** | Exclusion absolue du créateur même si profil shopper éligible à proximité immédiate (200 m, GPS frais 5s, rôle shopper) | `filterAndRankShoppers()` | **PASS** (0.19 ms) |
| **42** | Exclusion systématique de `errand.clientId` de la liste notifiée et de `radar_states` | `dispatchRadarWave()` | **PASS** (0.31 ms) |
| **43** | Rejet HTTP 403 `cannot_assign_own_errand` en cas de tentative d'auto-attribution par le créateur | `handleAtomicAssignment()` | **PASS** (0.19 ms) |
| **44** | Exception levée si `targetShopperUid` correspond au créateur lors de la préparation FCM | `processErrandNotificationEvent()` | **PASS** (0.27 ms) |
| **45** | Route Worker E2E `POST /api/radar/accept` : Rejet HTTP 403 `cannot_assign_own_errand` pour le créateur | `worker.fetch()` | **PASS** (2.29 ms) |

**Bilan Worker global** : **79 tests exécutés, 79 passés, 0 échec.**

### 4.2 Tests Flutter (`errand_radar_service_test.dart`)

| Test Flutter | Description | Résultat |
| :--- | :--- | :---: |
| **ErrandModel Support Géo** | Sérialisation / désérialisation GeoPoint et copyWith | **PASS** |
| **Machine d'État Radar** | Transition pending -> accepted et rejet concurrentiel | **PASS** |
| **Garde Auto-Attribution** | Interdiction formelle que le créateur devienne le shopper (`cannot_assign_own_errand`) | **PASS** |

**Bilan Flutter global** : **78 tests exécutés, 78 passés, 0 échec.**  
**Analyse statique** : `flutter analyze` -> `No issues found!`.

---

## 5. Points Non Vérifiés et Prérequis Déploiement

Conformément aux interdictions strictes de la mission, les points suivants n'ont pas été exécutés à distance :
1. **Aucun déploiement distant Cloudflare Workers** : Le code source est validé localement mais n'a pas été publié sur l'infrastructure Cloudflare de production via `wrangler deploy`.
2. **Aucune modification des règles Firestore distantes** : Les règles distantes du projet `dili-express` demeurent inchangées (les règles locales ont été vérifiées et ne nécessitent aucune modification).
3. **Secrets Cloudflare** : Le secret `FIREBASE_SERVICE_ACCOUNT` devra être configuré sur Cloudflare via `wrangler secret put FIREBASE_SERVICE_ACCOUNT` lors de la phase de déploiement autorisée par l'utilisateur.

---

## 6. Conclusion & Recommandation

Les deux anomalies soulevées par l'audit final sont **intégralement corrigées et validées**. L'architecture garantit désormais :
- Qu'aucun créateur ne peut recevoir une notification ou remporter sa propre commande sur le radar.
- Qu'aucun commissionnaire non assigné ne peut contourner le backend Worker Cloudflare.
- Que les règles Firestore conservent leur intégrité maximale sans compromis de sécurité.

Le code local est **prêt pour le déploiement direct en production** dès accord explicite de l'utilisateur.
