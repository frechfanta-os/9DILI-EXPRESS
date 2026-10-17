# 9DILI EXPRESS — AUDIT BLOQUANT PRÉ-DÉPLOIEMENT (PREDEPLOY GATE)

> **Document** : `PREDEPLOY_GATE_9DILI_EXPRESS.md`  
> **Date** : 17 Octobre 2026  
> **Projet** : 9DILI EXPRESS (`com.ghdinteractivestudio.dili_express`)  
> **Dépôt** : `https://github.com/frechfanta-os/9DILI-EXPRESS.git`  
> **Branche de référence** : `main`  
> **Commit HEAD audité** : `36e5c3d2da989fe911ba460db65978de0873d159`  
> **Mode** : Strictement lecture seule locale, zéro mutation distante, zéro secret manipulé  
> **Décision Finale du Gate** : 🟡 **GO CONDITIONNEL** (Prêt pour préparation au déploiement, déploiement non autorisé)

---

## 1. Résumé Exécutif

Cet audit pré-déploiement exhaustif a pour mission de contrôler l'intégralité des prérequis techniques, cryptographiques, géographiques et opérationnels du Worker Cloudflare et de l'application Flutter avant toute mise en production.

### Résultats de Synthèse :
- **Tests Automatisés Locaux** : **157/157 tests passés avec succès** (79 Worker Node.js + 78 Flutter, 0 échec).
- **Analyse Statique Flutter (`flutter analyze`)** : **0 issue trouvée** (`No issues found!`).
- **Gestion des Secrets & Clés** : Aucun secret codé en dur, aucun fichier sensible (`.env`, `*.pem`, `*.json` de compte de service) présent dans le bundle.
- **Autorité Firestore & Règles de Sécurité** : Les règles de production (`firestore.rules`) sont intactes et interdisent catégoriquement tout contournement client par un tiers non assigné (`PERMISSION_DENIED`).
- **Garde Anti-Auto-Attribution** : Vérifiée au niveau du Worker (HTTP 403 `cannot_assign_own_errand`), des notifications FCM et du code client Flutter (`StateError`).
- **Radar Géographique** : Plafonnement absolu à 10.0 km, séquence des 4 vagues (2/5/8/10 km), fraîcheur GPS < 120s et départage déterministe certifiés.

---

## 2. Commit, Branche et État Git Exacts

### 2.1 Identifiants Git
- **Commit HEAD** : `36e5c3d2da989fe911ba460db65978de0873d159`
- **Commit de référence audité** : `36e5c3d2da989fe911ba460db65978de0873d159`
- **Écart avec la référence** : `0 commit` (parfaite identité d'historique).
- **Branche courante** : `main`.
- **Dernier commit committé** : `feat(tracking): finalisation suivi GPS temps reel RTDB et preparation MapLibre`.

### 2.2 État de l'Arbre de Travail (Working Tree)
Le dépôt n'est **pas propre** au sens Git car des fichiers modifiés et des fichiers non suivis nécessaires à la release sont présents dans le répertoire de travail :

#### Fichiers Suivis Modifiés (`git status --short`) :
```text
 M lib/models/errand_model.dart     (+8 lignes : support storeGeoPoint)
 M lib/services/errand_service.dart (+93 lignes : garde cannot_assign_own_errand, assignShopperAtomic, declineErrand)
 M lib/ui/widgets/map_markers.dart  (+217 lignes : composants 3D Stitch et loaders)
 M pubspec.lock                     (+32 lignes)
 M pubspec.yaml                     (+9 lignes : maplibre_gl et assets déclarés)
 M test/map_markers_test.dart       (+57 lignes : tests des marqueurs 3D)
```

#### Fichiers Non Suivis (Untracked) :
- `workers/notifications_dispatcher/` (14 fichiers constituant le Worker, ses tests et sa configuration).
- `assets/data/algeria_full_catalog.json` & `assets/images/map_markers/*.png` (11 marqueurs 3D).
- `lib/models/product_model.dart` & `lib/services/product_catalog_service.dart`.
- `lib/services/routing_geocoding_service.dart` & `lib/ui/screens/maplibre_prototype_screen.dart`.
- `test/errand_radar_service_test.dart`, `test/maplibre_prototype_screen_test.dart`, `test/product_catalog_service_test.dart`.
- Rapports d'audits documentaires (`*.md`).

---

## 3. Inventaire des Fichiers Destinés à la Release

### 3.1 Fichiers Validés pour le Bundle de Release
1. **Worker Cloudflare (`workers/notifications_dispatcher/`)** :
   - `package.json` (0 dépendance tierce externe, scripts npm).
   - `wrangler.toml` (Configuration des queues, DLQ, cron, vars).
   - `src/index.js`, `src/radar_config.js`, `src/radar_service.js`, `src/events.js`, `src/distributed_lock.js`, `src/security.js`, `src/fcm.js`, `src/firestore.js`, `src/geo.js`.
   - `test/distributed_lock.test.js`, `test/radar.test.js`, `test/worker.test.js`.
2. **Application Flutter (`lib/`, `assets/`, `test/`)** :
   - `lib/models/errand_model.dart`
   - `lib/services/errand_service.dart`
   - `lib/models/product_model.dart`
   - `lib/services/product_catalog_service.dart`
   - `lib/services/routing_geocoding_service.dart`
   - `lib/ui/screens/maplibre_prototype_screen.dart`
   - `lib/ui/widgets/map_markers.dart`
   - `assets/data/algeria_full_catalog.json`
   - `assets/images/map_markers/MARQUEURS-MAPLIBRE-3D01.png` à `3D11.png`
   - `pubspec.yaml` et `pubspec.lock`
   - Suites de tests dans `test/`.

### 3.2 Fichiers Exclus du Bundle de Production
- Tous les rapports Markdown (`AUDIT_*.md`, `RAPPORT_*.md`, `PLAN_*.md`, `PREDEPLOY_*.md`, `RELEASE_*.md`).
- Répertoires `.dart_tool/`, `build/`, `.gradle/`, `.idea/`.

---

## 4. Matrice de Contrôle Pré-Déploiement

| ID | Domaine Contrôlé | Statut | Justification Détaillée |
| :---: | :--- | :---: | :--- |
| **A-1** | Intégrité Git HEAD et branche | **PASS** | `36e5c3d` sur `main`. Aucune dérive d'historique. |
| **A-2** | Cohérence code testé vs code release | **PASS** | Les 157 tests ont été exécutés sur les fichiers exacts destinés à la release. |
| **B-1** | Absence de secrets codés en dur | **PASS** | Scan regex et inspection manuelle négatifs. Aucun token ou clé privée dans le code. |
| **B-2** | Étanchéité de `.gitignore` | **PASS** | Règle stricte excluant `*.pem`, `*.key`, `*.keystore`, `.env`, `service-account*.json`. |
| **B-3** | Déclaration du secret `FIREBASE_SERVICE_ACCOUNT` | **NON VÉRIFIÉ — AUTORISATION REQUISE** | Le secret n'est pas vérifiable en local car Wrangler distant nécessite une session authentifiée. |
| **C-1** | Configuration `wrangler.toml` (Nom, Vars) | **PASS** | `name = "dili-express-notifications-dispatcher"`, `FIREBASE_PROJECT_ID = "dili-express"`, `ENVIRONMENT = "production"`. |
| **C-2** | Bindings Queues (`RADAR_QUEUE`, DLQ) | **PASS** | Producteur `RADAR_QUEUE` lié à `dili-express-radar-queue`. Consommateur avec `max_retries = 3`, `max_batch_size = 5`, `dead_letter_queue = "dili-express-radar-dlq"`. |
| **C-3** | Déclencheur Cron (`* * * * *`) | **PASS** | Présent dans `wrangler.toml`. Déclenche `worker.scheduled()` pour balayer les vagues échues. |
| **C-4** | Précision temporelle Cron vs Queues | **PARTIAL** | **Précision documentée** : Le Cron à la minute ne traite pas toutes les 15s. Une tâche Queue différée de 15s indique son éligibilité, pas une livraison garantie à la milliseconde près. |
| **C-5** | Comportement sans secret du Worker | **PASS** | Pas de crash : `/health` répond HTTP 200, `/api/notify` bascule en mode simulation transparente (`simulated: true, configured: false`). |
| **C-6** | Provisionnement distant des Queues | **NON VÉRIFIÉ — AUTORISATION REQUISE** | La présence réelle des queues sur Cloudflare nécessite `wrangler queues list` sur le compte de production. |
| **D-1** | Validation cryptographique JWT RS256 | **PASS** | Validation complète des JWKS publiques Google, vérification de `exp`, `iat`, `auth_time`, `iss` et `aud === dili-express`. |
| **D-2** | Exclusion du créateur (Filtrage radar) | **PASS** | `creatorUid` exclu formellement dans `filterAndRankShoppers()` et `dispatchRadarWave()`. |
| **D-3** | Rejet d'auto-attribution créateur | **PASS** | HTTP 403 `cannot_assign_own_errand` retourné par `/api/radar/accept` et `handleAtomicAssignment()`. |
| **D-4** | Attribution atomique exclusive REST | **PASS** | Précondition `currentDocument.updateTime` dans Firestore REST PATCH. Gestion stricte du conflit HTTP 409 `already_assigned`. |
| **D-5** | Protection contre le contournement Firestore | **PASS** | Règles `firestore.rules` (Lignes 58-90) imposent `clientId == auth.uid` ou `shopperId == auth.uid`. Un candidat non attribué subit `PERMISSION_DENIED` sur écriture directe. |
| **D-6** | Confidentialité des notifications FCM | **PASS** | Payloads assainis dans `events.js` : aucun code PIN, aucun numéro de téléphone, aucune adresse exacte transmise. |
| **E-1** | Rayon radar (2/5/8/10 km, plafond 10 km) | **PASS** | Calculé dans `calculateWaveRadius()` et borné à `RADAR_CONFIG.MAX_RADIUS_KM` (10.0 km). |
| **E-2** | Fraîcheur GPS (120 secondes max) | **PASS** | Filtre `isGpsFresh()` avec seuil 120 000 ms validé par test unitaire. |
| **E-3** | Capacité et tri des vagues | **PASS** | Limité à 10 candidats par vague, tri par distance croissante et départage déterministe alphabétique par UID. |
| **F-1** | Tests automatisés Worker Node.js | **PASS** | `npm test` : **79 passés, 0 échec** (728 ms). |
| **F-2** | Tests automatisés Flutter | **PASS** | `flutter test` : **78 passés, 0 échec** (8 s). |
| **F-3** | Analyse statique de code Flutter | **PASS** | `flutter analyze` : **0 anomalie** (`No issues found!`). |
| **G-1** | Vérification distante Cloudflare | **NON VÉRIFIÉ — AUTORISATION REQUISE** | Aucune commande distante n'a été exécutée conformément aux interdictions. |
| **H-1** | Procédure de Smoke Test documentée | **PASS** | Protocole HTTP `/health` et test d'assignation préparés. |
| **H-2** | Procédure de Rollback documentée | **PASS** | `wrangler rollback` et désactivation de queue documentées sans risque de corruption Firestore. |

---

## 5. Résultats Réels des Tests Locaux

### 5.1 Suite Worker (`workers/notifications_dispatcher`)
- **Commande** : `npm test`
- **Répertoire** : `/root/dili_express/workers/notifications_dispatcher`
- **Code de sortie** : `0`
- **Statistiques** : **79 tests exécutés, 79 passés, 0 échec, 0 sauté**
- **Durée réelle** : 728.28 ms

### 5.2 Suite Flutter (`dili_express`)
- **Commande** : `flutter test`
- **Répertoire** : `/root/dili_express`
- **Code de sortie** : `0`
- **Statistiques** : **78 tests exécutés, 78 passés, 0 échec**
- **Durée réelle** : 8 secondes

### 5.3 Analyse Statique Flutter
- **Commande** : `flutter analyze`
- **Répertoire** : `/root/dili_express`
- **Code de sortie** : `0`
- **Résultat réel** : `No issues found! (ran in 13.2s)`

---

## 6. Analyse des Risques

### 6.1 Risques Bloquants Découverts
**Aucun risque bloquant découvert dans le code source ou la configuration locale.**  
Tous les scénarios critiques (double attribution, auto-attribution, contournement client, fuite de données) sont couverts et verrouillés.

### 6.2 Risques Non Bloquants (Opérationnels)
1. **Délai d'exécution des vagues Cloudflare Queues** :
   - Le délai de 15 secondes configuré (`delaySeconds: 15`) définit le moment où le message devient visible dans la file. Selon la charge réseau des centres de données Cloudflare, la consommation effective peut intervenir entre 15 et 20 secondes.
2. **Balayage Cron périodique de secours** :
   - Le Cron s'exécute à chaque minute (`* * * * *`). Il constitue un filet de sécurité fiable en cas de défaillance client, mais ne peut pas se substituer à la file pour une cadence à la sous-minute.
3. **Quotas du plan Firebase Spark** :
   - Les écritures Firestore par vague sont limitées à 1 mise à jour de document d'état (`radar_states/{errandId}`), restant strictement dans l'enveloppe gratuite (20 000 écritures/jour).

---

## 7. Contrôles Distants Encore Nécessaires (Avant Go-Live)

Ces trois vérifications exigent une connexion au compte Cloudflare de production et devront être exécutées lors de la phase de déploiement autorisée :

1. **Vérification de l'existence des Queues** :
   ```bash
   npx wrangler queues list
   ```
   *Attendu* : Présence de `dili-express-radar-queue` et `dili-express-radar-dlq`.
2. **Vérification de la présence du secret (sans affichage de valeur)** :
   ```bash
   npx wrangler secret list
   ```
   *Attendu* : Présence de la clé `FIREBASE_SERVICE_ACCOUNT` dans la liste des secrets du Worker.
3. **Vérification du sous-domaine Worker** :
   Confirmer l'URL canonique attribuée (ex: `https://dili-express-notifications-dispatcher.<subdomain>.workers.dev`).

---

## 8. Procédure de Smoke Test & Rollback

### 8.1 Smoke Test Post-Déploiement (Ordre d'Exécution)
1. **Healthcheck public** :
   ```bash
   curl -s "https://dili-express-notifications-dispatcher.<subdomain>.workers.dev/health"
   ```
   *Critère d'acceptation* : Réponse HTTP 200 contenant `"status":"ok"` et `"projectId":"dili-express"`.
2. **Rejet de requête non authentifiée** :
   ```bash
   curl -s -i -X POST "https://dili-express-notifications-dispatcher.<subdomain>.workers.dev/api/radar/accept" \
     -H "Content-Type: application/json" \
     -d '{"errandId":"test"}'
   ```
   *Critère d'acceptation* : Réponse HTTP 400 ou 401.
3. **Simulation isolée d'attribution** :
   Exécuter un test d'attribution avec un jeton Firebase Auth de test sur une commande fictive `test_smoke_errand`.

### 8.2 Critères d'Arrêt Immédiat (Triggers de Rollback)
- Erreurs HTTP 5xx supérieures à 5% sur `/api/radar/accept`.
- Double attribution constatée en base Firestore.
- Secret `FIREBASE_SERVICE_ACCOUNT` signalé corrompu ou invalide dans les logs Cloudflare.
- Indisponibilité du service FCM entraînant un blocage complet des livraisons.

### 8.3 Procédure de Rollback
```bash
cd /root/dili_express/workers/notifications_dispatcher
npx wrangler rollback
```
En cas de saturation de la file de messages :
```bash
npx wrangler queues consumer remove dili-express-radar-queue dili-express-notifications-dispatcher
```

---

## 9. Décision Finale

### 🟡 **GO CONDITIONNEL**

#### Justification :
- ✅ **Tests locaux réels** : 100% de réussite (157 tests, 0 échec, 0 avertissement statique).
- ✅ **Intégrité de la release** : Fichiers identifiés sans ambiguïté.
- ✅ **Sécurité et secrets** : Aucun secret exposé, règles Firestore intactes, rejet de l'auto-attribution vérifié.
- ✅ **Configurations locales** : Parfaitement cohérentes avec les besoins du radar.
- ⚠️ **Condition suspensive** : Le déploiement effectif reste subordonné à l'exécution ordonnée des prérequis distants (création des queues et injection du secret `FIREBASE_SERVICE_ACCOUNT`).

> **Rappel formel** : Aucune commande distante n'a été exécutée pendant cet audit. Ce rapport constitue une autorisation technique de préparation, et non un acte de déploiement.
