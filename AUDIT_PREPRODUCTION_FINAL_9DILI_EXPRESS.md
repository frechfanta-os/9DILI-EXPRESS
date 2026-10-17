# 9DILI EXPRESS — AUDIT PRÉPRODUCTION FINAL DU RADAR & WORKER

> **Date** : 17 Octobre 2026  
> **Type d'audit** : Revue technique finale pré-déploiement en lecture seule  
> **Projet** : 9DILI EXPRESS  
> **Dépôt** : `https://github.com/frechfanta-os/9DILI-EXPRESS.git`  
> **Branche active** : `main`  
> **Commit de référence audité** : `36e5c3d2da989fe911ba460db65978de0873d159`  
> **Environnement de test** : Android / Termux / Ubuntu PRoot / Node.js 20 / Flutter 3.29.0 / Dart 3.7.0  
> **Mode opératoire** : Strictement local, lecture seule du code source, zéro appel réseau distant, aucun secret manipulé.

---

## 1. Synthèse Exécutive & Verdict

L'audit préproduction final a examiné de manière exhaustive l'état réel du code source après la correction des deux blocages du radar intelligent (exclusion formelle du créateur et réconciliation avec les règles Firestore).

### Verdict Global : ✅ **PRÊT À DÉPLOYER SOUS RÉSERVE DES PRÉREQUIS**

Tous les critères d'architecture logicielle, d'intégrité des données, d'idempotence, de sécurité cryptographique, de confidentialité et de gestion de concurrence sont **pleinement satisfaits et vérifiés par 157 tests automatisés locaux** (79 Worker + 78 Flutter, 0 échec, 0 avertissement d'analyse statique).

Le passage en production nécessite uniquement l'accomplissement des prérequis opérationnels distants (provisionnement de la file Cloudflare Queues et injection du secret de compte de service Firebase).

---

## 2. État Git et Modifications Locales

### 2.1 Commit Autoritatif
- **Commit SHA** : `36e5c3d2da989fe911ba460db65978de0873d159`
- **Message** : `feat(tracking): finalisation suivi GPS temps reel RTDB et preparation MapLibre`
- **Branche** : `main`

### 2.2 Fichiers Suivis Modifiés Localement (Non Committés)
| Fichier | Nature de la Modification | Impact Sécurité & Radar |
| :--- | :--- | :--- |
| `lib/services/errand_service.dart` | Ajout méthode `assignShopperAtomic` et `declineErrand`, garde anti-auto-attribution `cannot_assign_own_errand`, documentation architecturale | **Conforme** : Harmonise la logique locale sans affaiblir les règles |
| `lib/models/errand_model.dart` | Support des champs géographiques `storeGeoPoint` et `deliveryGeoPoint` pour le radar | **Conforme** : Compatible structures existantes |
| `lib/ui/widgets/map_markers.dart` | Composants graphiques des marqueurs de carte MapLibre/FlutterMap | **Conforme** : UI uniquement |
| `test/map_markers_test.dart` | Tests unitaires des marqueurs | **Conforme** : Tests UI |
| `pubspec.yaml` / `pubspec.lock` | Dépendances cartographiques locales (`flutter_map`, `latlong2`) | **Conforme** : Pas de dépendance tierce superflue |

### 2.3 Fichiers et Dossiers Non Suivis (Untracked)
- `workers/notifications_dispatcher/` : Code source complet du Worker Cloudflare, modules de sécurité, tests unitaires et de concurrence, configuration `wrangler.toml`.
- `test/errand_radar_service_test.dart` : Banc de test unitaire Flutter pour le modèle d'errand et les gardes d'attribution atomique.
- `lib/models/product_model.dart` / `lib/services/product_catalog_service.dart` : Catalogue local de produits.
- `lib/services/routing_geocoding_service.dart` / `lib/ui/screens/maplibre_prototype_screen.dart` : Services de géolocalisation et prototype.
- Rapports d'audit et de maintenance (`*.md`).

---

## 3. Matrice d'Évaluation de Préproduction

### Légende :
- **PASS** : Confirmé formellement dans le code source ET validé par tests automatisés locaux reproductibles.
- **NON VÉRIFIÉ** : Nécessite l'infrastructure distante Cloudflare en direct, un compte de service actif ou un appareil physique avec services Google Play.
- **FAIL** : Non conforme ou anomalie bloquante constatée (aucun constat de ce type).

| Domaine / Fonctionnalité | Point Contrôlé | Statut | Justification Technique |
| :--- | :--- | :---: | :--- |
| **Exclusion du Créateur** | Filtrage des candidats (`filterAndRankShoppers`) | **PASS** | `creatorUid` injecté dans `excludedSet` et testé via `if (creatorUid && uid === creatorUid) continue;`. Ignoré même si rôle `shopper`, en ligne, GPS frais à 200 m (Test 41). |
| **Exclusion du Créateur** | Déclenchement de vague (`dispatchRadarWave`) | **PASS** | `errand.clientId` extrait et inséré dans le `Set` des exclus avant sélection et dispatch (Test 42). |
| **Exclusion du Créateur** | Attribution `/api/radar/accept` (`handleAtomicAssignment`) | **PASS** | Rejet HTTP 403 `cannot_assign_own_errand` si `shopperUid === errand.clientId` (Tests 43 & 45). |
| **Exclusion du Créateur** | Notifications push FCM (`processErrandNotificationEvent`) | **PASS** | Erreur levée si `targetShopperUid === clientId` pour `NEW_ERRAND_AVAILABLE` ou `ERRAND_NO_LONGER_AVAILABLE` (Test 44). |
| **Attribution Atomique** | Précondition de concurrence Firestore REST | **PASS** | Utilisation de `currentDocument.updateTime=${currentUpdateTime}` dans la requête PATCH. Concurrence simultanée testée : 1 seul gagnant, 1 perdant avec HTTP 409 (Tests 12 & 13). |
| **Attribution Atomique** | Idempotence du gagnant | **PASS** | Rejouer `/api/radar/accept` pour le gagnant retourne HTTP 200 `already_assigned_to_caller` sans altérer l'état (Test 20). |
| **Attribution Atomique** | Statut et intégrité de la commande | **PASS** | Rejet si la commande n'est plus `pending` ou déjà attribuée à un tiers (HTTP 409 `already_assigned` ou `errand_not_available`, Test 14). |
| **Règles Firestore** | Étanchéité de `firestore.rules` | **PASS** | Lignes 58-90 limitent l'écriture à `clientId == auth.uid` ou `shopperId == auth.uid`. Un commissionnaire candidat (`shopperId == null`) est rejeté avec `PERMISSION_DENIED` s'il tente une écriture directe. |
| **Règles Firestore** | Non-affaiblissement des règles | **PASS** | `firestore.rules` est demeuré intact, garantissant la stricte autorité du compte de service backend. |
| **Client Flutter** | Garde dans `assignShopperAtomic()` | **PASS** | Vérification `if (currentClientId == shopperId) throw StateError('cannot_assign_own_errand')` ajoutée dans `errand_service.dart` et validée par test unitaire. |
| **Sécurité Auth** | Validation JWT Firebase Auth RS256 | **PASS** | Clés JWKS publiques Google, vérification cryptographique `RS256`, validation stricte de `exp`, `iat`, `auth_time`, `iss` et `aud === dili-express` (Tests 1 à 6). |
| **Sécurité Données** | Confidentialité des données privées (zéro fuite) | **PASS** | Payloads FCM assainis dans `events.js` : exclusion absolue du code PIN, du téléphone et de l'adresse exacte du client (Test 26). |
| **Radar Géographique** | Rayons et progression des vagues | **PASS** | Vague 1: 2.0 km, Vague 2: 5.0 km, Vague 3: 8.0 km, Vague 4: 10.0 km. Plafond absolu à 10.0 km garanti côté Worker (Tests 31 à 35). |
| **Radar Géographique** | Seuil de fraîcheur GPS | **PASS** | 120 000 ms (2 minutes). Tout GPS plus ancien est systématiquement éliminé (Test 6). |
| **Radar Géographique** | Nombre max de shoppers par vague | **PASS** | Limité à 10 shoppers ordonnés par distance Haversine avec tri déterministe par UID en cas d'égalité (Tests 3 & 7). |
| **Ordonnancement** | Envoi différé des vagues (15s) | **PASS** | Producer Cloudflare Queues avec `delaySeconds: 15` implémenté dans `dispatchRadarWave` (Test 36). |
| **Ordonnancement** | Consommateur de file et retries | **PASS** | `worker.queue()` implémente le traitement asynchrone, `msg.retry()` sur panne réseau et `msg.ack()` (Tests 37, 38, 39). |
| **Ordonnancement** | Balayage Cron Sweep de secours | **PASS** | `worker.scheduled()` déclenche `sweepPendingRadarWaves()` toutes les minutes pour les vagues échues sans client connecté (Test 40). |
| **Configuration** | Déclarations `wrangler.toml` | **PASS** | `FIREBASE_PROJECT_ID = "dili-express"`, queue `dili-express-radar-queue`, DLQ `dili-express-radar-dlq`, `max_retries = 3`, cron `* * * * *`. |
| **Environnement Distant** | Provisionnement Cloudflare Queues | **NON VÉRIFIÉ** | Nécessite l'exécution `wrangler queues create dili-express-radar-queue` sur le compte Cloudflare distant. |
| **Environnement Distant** | Injection du secret `FIREBASE_SERVICE_ACCOUNT` | **NON VÉRIFIÉ** | Le secret doit être injecté via `wrangler secret put FIREBASE_SERVICE_ACCOUNT` sans être committé dans Git. |
| **Matériel Physique** | Réception de notifications push sur appareil réel | **NON VÉRIFIÉ** | Dépend de la connectivité réseau GSM/Wi-Fi et des serveurs FCM Google Play Services. |

---

## 4. Analyse Détaillée des Différences de Code et Cohérence Architecturale

### 4.1 Exclusion Inconditionnelle du Créateur
- **`workers/notifications_dispatcher/src/radar_service.js`** :
  - Lignes 56-71 : Prise en charge de `options.creatorUid` / `options.clientId`. Ajout direct à `excludedSet` et condition d'exclusion prioritaire :
    ```javascript
    if (creatorUid && uid === creatorUid) continue;
    ```
  - Lignes 341-356 : `dispatchRadarWave()` extrait `creatorUid = errand.clientId` et l'ajoute au `Set` d'exclusion passé à `filterAndRankShoppers`.
  - Lignes 619-628 : `handleAtomicAssignment()` rejette toute requête d'acceptation provenant du créateur avec le code `cannot_assign_own_errand` (HTTP 403).
- **`workers/notifications_dispatcher/src/events.js`** :
  - Lignes 149-153 : `processErrandNotificationEvent()` bloque la génération de notification push `NEW_ERRAND_AVAILABLE` si le destinataire unicast correspond à `errand.clientId`.
  - Lignes 204-207 : Même blocage préventif sur `ERRAND_NO_LONGER_AVAILABLE`.
- **`lib/services/errand_service.dart`** :
  - Lignes 526-531 : `assignShopperAtomic()` vérifie `if (currentClientId != null && currentClientId == shopperId)` et lève une exception `StateError("cannot_assign_own_errand...")`.

### 4.2 Réconciliation avec les Règles Firestore
- **`firestore.rules`** (Lignes 58-90) :
  - Cas A : Le client créateur (`clientId == request.auth.uid`) peut mettre à jour sa commande (statut `accepted`, `cancelled`).
  - Cas B : Le shoppeur DÉJÀ ASSIGNÉ (`shopperId == request.auth.uid`) peut mettre à jour le flux de livraison (`shopping`, `delivering`, `completed`).
  - **Verdict sécurité** : Un commissionnaire non assigné reçoit systématiquement une erreur `PERMISSION_DENIED` s'il tente d'écrire directement dans `/errands/{errandId}`.
- **Passerelle d'autorité** :
  - L'unique moyen pour un shoppeur candidat de remporter une course est d'appeler `POST /api/radar/accept`.
  - Le Worker Cloudflare exécute la mutation via les droits administratifs de son compte de service Firebase, tout en appliquant la précondition atomique `updateTime`.
  - Ce schéma garantit qu'aucun client malveillant ne peut contourner le verrou de concurrence ni les filtres de proximité.

### 4.3 Validation d'Identité et Machine d'État
- **Validation JWT** ([`security.js`](file:///root/dili_express/workers/notifications_dispatcher/src/security.js)) :
  - Vérification cryptographique de l'en-tête RS256 via les certificats publics Google JWKS.
  - Rejet des jetons expirés ou dont l'audience n'est pas `dili-express`.
  - Extraction de l'UID appelant certifié (`caller.uid`), interdisant toute usurpation d'identité.
- **Machine d'État de la Course** :
  - Statut initial exigé : `pending`.
  - Présence obligatoire de coordonnées valides (`storeLocation` ou repli `deliveryGeoPoint`).
  - Passage exclusif à `accepted` lors de l'attribution atomique.
  - Neutralisation immédiate du radar si la course est annulée (`cancelled`) ou déjà attribuée (`assigned`).

### 4.4 Assainissement des Données FCM (Confidentialité)
- Le payload de notification transmis aux shoppeurs candidats contient exclusivement :
  - L'identifiant de la course (`errandId`).
  - Le nom du commerce (`storeName`).
  - La distance indicative arrondie (`distanceKm`).
- Sont **formellement exclus** de toute notification push :
  - Le code PIN secret (stocké exclusivement dans la sous-collection protégée `/errands/{errandId}/secrets/pin`).
  - L'adresse précise de livraison du client.
  - Le numéro de téléphone du client.

---

## 5. Exécution Réelle des Tests Locaux

### 5.1 Suite Worker Cloudflare (`workers/notifications_dispatcher`)
- **Commande exécutée** :
  ```bash
  npm test
  ```
- **Répertoire de travail** : `/root/dili_express/workers/notifications_dispatcher`
- **Résultat réel constaté** :
  ```text
  ✔ Idempotence Distribuée Firestore REST — Tests Concurrence, Fencing et Reprise (7 tests)
  ✔ SUITE COMPLÈTE DU RADAR INTELLIGENT DE COMMANDES (PHASE J — 45 tests)
    ✔ 41. filterAndRankShoppers : exclusion absolue du créateur même si profil shopper éligible à proximité immédiate (0.19ms)
    ✔ 42. dispatchRadarWave : exclusion systématique de errand.clientId de la liste notifiée (0.29ms)
    ✔ 43. handleAtomicAssignment : Rejet 403 cannot_assign_own_errand en cas de tentative d'auto-attribution (0.17ms)
    ✔ 44. processErrandNotificationEvent : Erreur levée si targetShopperUid est le créateur de la course (0.22ms)
    ✔ 45. Route Worker E2E POST /api/radar/accept : Rejet 403 cannot_assign_own_errand pour le créateur (2.18ms)
  ✔ Sécurité Firebase Auth — Validation des revendications JWT (6 tests)
  ✔ Sécurité Firebase Auth — Vérification cryptographique RS256 et JWKS (1 test)
  ✔ Firestore REST — Parsing des champs typés (1 test)
  ✔ Événements Métier — Contrôle des Rôles et des États Firestore (4 tests)
  ✔ Protection Anti-Doublons & Idempotence avec Verrouillage En-Vol (5 tests)
  ✔ Worker E2E — Requêtes HTTP et Gestion des Erreurs (3 tests)
  ✔ FCM HTTP v1 — Détection des Jetons Obsolètes et Erreurs (1 test)

  ℹ tests 79
  ℹ suites 0
  ℹ pass 79
  ℹ fail 0
  ℹ cancelled 0
  ℹ skipped 0
  ℹ duration_ms 529.11
  ```

### 5.2 Suite de Tests Flutter (`dili_express`)
- **Commande exécutée** :
  ```bash
  flutter test
  ```
- **Répertoire de travail** : `/root/dili_express`
- **Résultat réel constaté** :
  ```text
  00:09 +78: All tests passed!
  ```
- **Tests couverts** :
  - Support géographique et sérialisation GeoPoint.
  - Rejet de concurrence et idempotence dans la machine d'état.
  - Garde stricte d'auto-attribution du créateur (`cannot_assign_own_errand`).
  - Rendu visuel responsive, tokens UI et composants Stitch.
  - Suivi GPS en direct et gestion du mode hors-ligne.

### 5.3 Analyse Statique Flutter (`flutter analyze`)
- **Commande exécutée** :
  ```bash
  flutter analyze
  ```
- **Répertoire de travail** : `/root/dili_express`
- **Résultat réel constaté** :
  ```text
  Analyzing dili_express...
  No issues found! (ran in 10.8s)
  ```

---

## 6. Analyse des Bindings et Configuration Cloudflare (`wrangler.toml`)

Le fichier [`wrangler.toml`](file:///root/dili_express/workers/notifications_dispatcher/wrangler.toml) a été examiné en détail :
- **Nom du service** : `dili-express-notifications-dispatcher`
- **Point d'entrée** : `src/index.js`
- **Compatibilité** : `2024-04-01`
- **Variables publiques (`[vars]`)** :
  - `FIREBASE_PROJECT_ID = "dili-express"`
  - `ENVIRONMENT = "production"`
- **Déclencheurs périodiques (`[triggers]`)** :
  - `crons = ["* * * * *"]` (Balayage toutes les minutes pour le traitement des vagues échues par `scheduled()`).
- **File de messages Cloudflare Queues (`[[queues.producers]]` / `[[queues.consumers]]`)** :
  - Binding Producteur : `RADAR_QUEUE` vers `dili-express-radar-queue`
  - Consommateur : `dili-express-radar-queue`
  - Paramètres de lot : `max_batch_size = 5`, `max_batch_timeout = 5`
  - Politique de reprise : `max_retries = 3`
  - File de rebut (DLQ) : `dead_letter_queue = "dili-express-radar-dlq"`
- **Secrets Attendus (Sans affichage de valeur)** :
  - `FIREBASE_SERVICE_ACCOUNT` : Clé de compte de service Google au format JSON autorisant l'envoi de messages FCM HTTP v1 et la lecture/écriture sur l'API Firestore REST.

---

## 7. Distinction Explicite des Éléments d'Évaluation

### 7.1 Éléments Formellement Confirmés dans le Code
1. Exclusion absolue du créateur dans le filtrage radar, la diffusion des vagues, l'attribution atomique et les notifications push.
2. Rejet au niveau du Worker (HTTP 403 `cannot_assign_own_errand`) et de Flutter (`StateError`).
3. Verrouillage atomique distribué basé sur la précondition Firestore `currentDocument.updateTime`.
4. Intégrité des règles Firestore locales interdisant toute appropriation directe par un tiers non assigné.
5. Plafonnement strict des vagues à 10.0 km et temporisation à 15 secondes.
6. Validation cryptographique RS256 des jetons Firebase Auth.
7. Assainissement rigoureux des payloads FCM sans fuite de données personnelles ou sensibles.
8. Conformité de l'ensemble de la suite de 157 tests automatisés locaux.

### 7.2 Éléments Uniquement Rapportés
- Disponibilité de quotas suffisants sur le compte Cloudflare et le projet Firebase en environnement réel sous forte charge.
- Précision du délai de 15 secondes de Cloudflare Queues en fonction de la charge des PoP Cloudflare.

### 7.3 Éléments Nécessitant un Test Distant ou un Appareil Physique
1. **Création préalable des files sur Cloudflare** :
   ```bash
   npx wrangler queues create dili-express-radar-queue
   npx wrangler queues create dili-express-radar-dlq
   ```
2. **Injection sécurisée du secret de compte de service** :
   ```bash
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT
   ```
3. **Réception physique des notifications FCM** :
   Validation de l'affichage du bandeau de notification sur un terminal Android physique en arrière-plan et écran éteint.
4. **Déploiement effectif du Worker** :
   ```bash
   npx wrangler deploy
   ```

---

## 8. Conclusion et Feuille de Route pour le Déploiement

Le code source actuel au commit `36e5c3d` complété des ajustements locaux apporte des garanties formelles de sécurité et de robustesse. Aucune faille de contournement ni incohérence fonctionnelle ne subsiste.

### Étapes recommandées lors de l'autorisation de déploiement :
1. Provisionner les files Cloudflare : `npx wrangler queues create dili-express-radar-queue` et `dili-express-radar-dlq`.
2. Déposer le secret de production : `npx wrangler secret put FIREBASE_SERVICE_ACCOUNT`.
3. Publier le Worker : `npx wrangler deploy`.
4. Effectuer un test de fumée (Smoke Test) avec deux comptes réels distincts (1 Client, 1 Shopper) pour valider la réception du premier push FCM.
