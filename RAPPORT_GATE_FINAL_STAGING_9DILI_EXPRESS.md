# 9DILI EXPRESS — RAPPORT DE GATE FINAL AVANT STAGING ET COMMIT

**Projet** : 9DILI EXPRESS (Application mobile Flutter Android & Orchestrateur Cloudflare Edge)  
**Package Android** : `com.ghdinteractivestudio.dili_express`  
**Projet Firebase Actuel** : `dili-express` (Production — Plan Spark Gratuit)  
**Branche Git** : `main` | **HEAD Commit** : `36e5c3d`  
**Date d'évaluation** : 16 octobre 2026  
**Auteur** : Antigravity Architecture, Security & QA Pair Programmer  
**Statut Global** : **ACTION REQUISE SUR POINTS BLOQUANTS AVANT TOUT DÉPLOIEMENT OU COMMIT**  

---

## 1. Tableau Récapitulatif des Décisions par Point

| N° | Point de Contrôle | Décision d'Audit | Impact & Justification Synthétique |
| :---: | :--- | :---: | :--- |
| **1** | **Idempotence Distribuée** | 🔴 **BLOQUANT** | Le verrou `Map()` actuel est strictement local à l'isolate V8. Il n'est pas partagé entre instances Cloudflare multi-datacenters. Risque réel de double envoi lors de requêtes concurrentes inter-isolates. Solution distribuée Firestore documentée. |
| **2** | **Isolation Staging** | 🔴 **BLOQUANT** | `dili-express` est le projet Firebase de **production**. Tester les notifications topic (`available_errands`) en staging réveillerait les vrais livreurs de production. Un projet Firebase dédié `dili-express-staging` est formellement requis. |
| **3** | **Permissions IAM (Moindre Privilège)** | 🟢 **VALIDÉ** | Définition exacte des permissions `fcm.messages.create` et `datastore.entities.get`. Aucune ressource distante créée. Absence formelle de rôles excessifs (`owner`, `editor`, `firebase.admin`). |
| **4** | **Modèle de Coûts & Quotas Réels** | 🟢 **VALIDÉ** | Séparation stricte des 4 métriques. Rejet formel de toute « garantie » de N courses/jour. Plafonds réalistes documentés : budget lectures Firestore et saturation RTDB à 50 livraisons simultanées. |
| **5** | **État Git & Préparation du Commit** | 🟢 **VALIDÉ** | Audit rigoureux de `git status` et `git diff --check`. Inventaire précis des fichiers modifiés et non suivis préparés pour un commit futur sans aucune altération de l'arbre de travail. |

---

## 2. Analyse Approfondie des Points d'Audit

### Point 1 — Idempotence Distribuée (🔴 BLOQUANT)

#### A. Examen de l'implémentation existante (`src/events.js`)
L'implémentation actuelle repose sur :
```javascript
const idempotencyStore = new Map();
const IDEMPOTENCY_TTL_MS = 15 * 60 * 1000;
```
Les fonctions `acquireIdempotencyLock` et `releaseIdempotencyLock` manipulent cette structure en mémoire via `idempotencyStore.set()` et `idempotencyStore.delete()`.

#### B. Diagnostic multi-instances Cloudflare Worker
- **Non-partage de la mémoire** : Dans l'architecture serverless Edge de Cloudflare, les Workers s'exécutent dans des isolates V8 éphémères répartis sur plus de 300 datacenters. Chaque isolate dispose de sa propre mémoire heap hermétique.
- **Scénario de défaillance concurrentielle** : Si un utilisateur double-clique rapidement ou si une latence réseau conduit à deux requêtes HTTP routées vers deux datacenters différents (ex: PoP Marseille vs PoP Madrid) ou vers deux isolates démarrés en parallèle sur le même PoP, **chacun des isolates lira son propre `idempotencyStore` vide**, accordera le verrou `in_flight`, et enverra deux notifications FCM distinctes.
- **Cycle de vie et pannes** :
  - *Recyclage d'isolate* : Cloudflare recycle les isolates inactifs après quelques minutes ; le verrou en mémoire disparaît bien avant l'expiration théorique des 15 minutes.
  - *Échec après dispatch* : Si FCM a accepté la notification mais que le Worker subit une interruption avant de renvoyer le statut HTTP au client, une retentative ultérieure sur un nouvel isolate ne trouvera aucun historique et réémettra la notification.

#### C. Solution Distribuée Conforme aux Contraintes de Coût (0 $/mois)
Pour garantir une idempotence distribuée globale sans coût additionnel :
1. **Éviction des solutions payantes ou non adaptées** :
   - *Cloudflare Durable Objects* : Rejeter formellement car impose le plan Workers Paid (5 $/mois).
   - *Cloudflare KV* : Rejeter formellement car le quota d'écriture gratuit est limité à 1 000 écritures/jour et la consistance éventuelle (*eventual consistency*, jusqu'à 60 s) ne protège pas contre deux requêtes simultanées à la même seconde.
2. **Architecture Recommandée : Verrouillage Atomique Conditionnel Firestore REST** :
   - Utiliser l'API Firestore REST pour créer un document de verrouillage dans une collection `/idempotency_locks/{lockKey}` avec une précondition atomique :
     `precondition: { exists: false }`
   - Si deux isolates à travers le monde tentent d'écrire le même verrou à la même milliseconde, le moteur de stockage transactionnel de Google Cloud Firestore (Spanner) n'en valide qu'un seul et rejette immédiatement le second avec un code **HTTP 409 Conflict (ALREADY_EXISTS)**.
   - Dès la notification FCM délivrée, le document est mis à jour en `status: "completed"`.
   - *Consommation de quota* : 1 écriture par notification (soit 4 écritures par course complète). Pour 500 courses/jour, 2 000 écritures ne représentent que 10 % du quota gratuit d'écriture de Firestore Spark (20 000 écritures/jour). Coût total : **0,00 $**.

---

### Point 2 — Isolation Staging & Risques Production (🔴 BLOQUANT)

#### A. Statut du projet `dili-express`
- Le fichier `android/app/google-services.json` et la configuration Flutter `lib/firebase_options.dart` confirment formellement que `dili-express` est l'unique projet Firebase, actuellement configuré pour la **production**.

#### B. Périmètre des données accessibles
- Si un compte de service ayant `roles/datastore.viewer` sur `dili-express` est injecté dans le Worker staging, ce dernier possède la capacité de lire **l'intégralité des données réelles de production** (`/users`, `/errands`, `/bids`).
- Même si la logique métier du Worker vérifie que `callerUid === errand.clientId || callerUid === errand.shopperId` (ce qui empêche un utilisateur test de cibler la course d'un tiers), le risque d'erreur humaine en phase de test est critique :
  1. **Pollution de la base de production** : Toute course de test créée apparaîtra dans la collection `/errands` de production.
  2. **Pollution du topic FCM `available_errands` (RISQUE CRITIQUE)** : Lors du test de l'événement `new_errand_available`, le Worker publie sur le topic FCM `available_errands`. **Tous les livreurs de production en Algérie abonnés à ce topic recevraient une notification fantôme pour une course fictive**.

#### C. Recommandation Formelle
- **Création d'un Projet Firebase Dédié au Staging** : `dili-express-staging`.
  - Projet 100 % gratuit sur plan Firebase Spark.
  - Base Firestore isolée, utilisateurs isolés, topics FCM hermétiques.
  - Zéro interaction et zéro risque d'impact sur les utilisateurs réels de `dili-express`.

---

### Point 3 — Permissions Google Cloud IAM (Moindre Privilège) (🟢 VALIDÉ)

#### A. Permissions exactes nécessaires
1. **Émission FCM HTTP v1** :
   - API cible : `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`
   - Scope OAuth2 : `https://www.googleapis.com/auth/firebase.messaging`
   - Rôle standard : `roles/firebase.messagingAdmin`
   - Permission granulaire : `fcm.messages.create` (ou `firebase.messaging.messages.create`).
2. **Lecture autoritative Firestore REST** :
   - API cible : `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/...`
   - Scope OAuth2 : `https://www.googleapis.com/auth/datastore`
   - Rôle standard : `roles/datastore.viewer`
   - Permissions granulaires : `datastore.entities.get`, `datastore.entities.list`.
3. **Cas de l'idempotence distribuée via Firestore** :
   - Si la collection `/idempotency_locks` est utilisée pour le verrouillage distribué, la permission d'écriture `datastore.entities.create` sera requise sur ce chemin.

#### B. Rôles expressément proscrits
- ❌ `roles/owner` : Donne tous les droits d'administration sur l'ensemble des ressources Google Cloud.
- ❌ `roles/editor` : Permet la modification de tous les services et le déploiement de ressources payantes.
- ❌ `roles/firebase.admin` : Permet la suppression complète de bases de données et la manipulation de règles de sécurité.
- ❌ `roles/datastore.user` : Permet la modification ou suppression arbitraire de n'importe quel document Firestore.

*Statut* : Aucune clé, aucun compte de service ni aucun rôle n'a été créé sur Google Cloud.

---

### Point 4 — Coûts et Quotas Réels sous Plan Spark (🟢 VALIDÉ)

#### A. Décomposition des 4 Métriques Indépendantes

| Ressource | Quota Gratuit Applicable | Facteur Limitant | Impact Opérationnel |
| :--- | :--- | :--- | :--- |
| **Lectures Firestore** | 50 000 lectures / jour | Plafond journalier | Consommées par les ré-écoutes temps réel, le Worker, et la consultation du radar. |
| **Écritures Firestore** | 20 000 écritures / jour | Plafond journalier | Consommées par les étapes de la course (création, offre, ticket, clôture) et les verrous. |
| **Connexions RTDB (GPS)** | **100 connexions actives** | **Plafond instantané** | 2 connexions par course active (livreur + client). **Seuil de rupture : 50 courses en transit simultanées**. |
| **Bande Passante RTDB** | 10 Go / mois | Plafond mensuel | ~27 Ko par livraison de 15 min (throttling 5s). Très large (> 300 000 livraisons). |
| **Requêtes Cloudflare** | 100 000 requêtes / jour | Plafond journalier | 4 requêtes par course. Seuil de rupture à 25 000 courses/jour. |

#### B. Refus des « Garanties » Commerciales et Hypothèses Réelles
- **Il est techniquement erroné d'annoncer un volume garanti de « 2 500 courses/jour »**.
- En conditions réelles d'exploitation :
  - Chaque course génère entre 20 et 25 lectures Firestore (Worker autoritatif + snapshot listeners Flutter).
  - La consultation passive du radar par des livreurs en attente consomme du quota de lecture sans finaliser de course.
  - Le plafond RTDB (100 connexions) est une contrainte de **pic instantané** : à la 51ème livraison active à la même minute, la connexion RTDB sera rejetée, même si seulement 200 courses ont été passées dans la journée.
- **Seuils opérationnels réels sous plan 100 % gratuit Spark** :
  - **Budget journalier recommandé** : **1 000 à 1 200 courses complètes par jour**.
  - **Pic simultané admissible** : **50 livraisons en cours de route simultanément**.

---

### Point 5 — État Git et Préparation du Futur Commit (🟢 VALIDÉ)

#### A. Contrôle de l'Arbre de Travail
- `git status` et `git diff --check` ont été exécutés avec succès. Aucune erreur de fin de ligne, aucun conflit de fusion ni espace superflu.
- **Rappel strict** : Aucun fichier n'a été indexé (*staged*) et aucun commit n'a été généré.

#### B. Inventaire des Fichiers Prêts pour le Futur Commit

```
Fichiers suivis modifiés :
  modified:   lib/ui/widgets/map_markers.dart
  modified:   pubspec.lock
  modified:   pubspec.yaml
  modified:   test/map_markers_test.dart

Nouveaux fichiers applicatifs (Catalogue, Modèles, Services) :
  assets/images/map_markers/MARQUEURS-MAPLIBRE-3D01.png à 3D11.png (11 marqueurs)
  assets/data/algeria_full_catalog.json (2 261 produits)
  lib/models/product_model.dart
  lib/services/product_catalog_service.dart
  lib/services/routing_geocoding_service.dart
  lib/ui/screens/maplibre_prototype_screen.dart

Nouvelles suites de tests Flutter :
  test/product_catalog_service_test.dart (8 tests)
  test/maplibre_prototype_screen_test.dart (4 tests)

Nouveau module Cloudflare Worker (Orchestrateur FCM) :
  workers/notifications_dispatcher/package.json
  workers/notifications_dispatcher/wrangler.toml
  workers/notifications_dispatcher/src/index.js
  workers/notifications_dispatcher/src/security.js
  workers/notifications_dispatcher/src/events.js
  workers/notifications_dispatcher/src/firestore.js
  workers/notifications_dispatcher/src/fcm.js
  workers/notifications_dispatcher/test/worker.test.js (26 tests)

Documentation & Rapports d'Audit :
  RAPPORT_PROTOTYPE_MAPLIBRE_9DILI_EXPRESS.md
  RAPPORT_WORKER_CATALOGUE_MARQUEURS_9DILI_EXPRESS.md
  RAPPORT_AUDIT_PRE_DEPLOIEMENT_9DILI_EXPRESS.md
  PLAN_STAGING_9DILI_EXPRESS.md
  RAPPORT_GATE_FINAL_STAGING_9DILI_EXPRESS.md
```

---

## 3. Synthèse des Contrôles Locaux & Preuves d'Exécution

```
============================================================
SUITES DE TESTS AUTOMATISÉES (EXÉCUTION 100% LOCALE)
============================================================
1. Worker Notifications (Node.js v22.22.1) :
   - node --test test/*.test.js : 26 tests passés / 0 échec (durée: 587 ms)
   - Cryptographie RS256 Web Crypto : Validée
   - Anti-rejeu & In-flight lock : Validé
   - Classification d'erreurs FCM : Validée

2. Analyse Statique Flutter (Flutter 3.47.7 / Dart 3.13.5) :
   - flutter analyze : No issues found! (0 anomalie)

3. Tests Flutter (Unitaires & Widgets) :
   - flutter test : 72 tests passés / 0 échec
   - Rendu des 11 marqueurs 3D : Validé
   - Moteur de recherche catalogue Darja/Arabe/FR : Validé
   - Handshake sécurisé PIN/QR : Validé
============================================================
```

---

## 4. Recommandations et Plan d'Action Post-Gate

Avant d'autoriser le déploiement en staging et le commit Git, les deux actions correctives suivantes sont recommandées :

1. **Résolution du Point Bloquant 1 (Idempotence Distribuée)** :
   - Remplacer le `Map()` local dans `workers/notifications_dispatcher/src/events.js` par un appel REST Firestore conditionnel (`precondition: { exists: false }` sur `/idempotency_locks/{lockKey}`) afin de garantir une synchronisation atomique mondiale sur l'infrastructure Google Spanner sans surcoût.
2. **Résolution du Point Bloquant 2 (Isolation Staging)** :
   - Provisionner un projet Firebase Spark gratuit `dili-express-staging` (ou à défaut, restreindre strictement les tests staging à des identifiants et topics préfixés `staging_`) pour éviter toute diffusion de notifications fantômes sur le topic `available_errands` aux livreurs réels de production.

---

> [!IMPORTANT]
> **Statut de Clôture** : Aucune commande de déploiement distant (`wrangler deploy`), aucune injection de secret (`wrangler secret put`), aucune commande IAM distante, aucun `git commit` et aucun `git push` n'ont été exécutés. Antigravity reste en attente de vos instructions explicites.
