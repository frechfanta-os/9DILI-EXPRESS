# REVUE TECHNIQUE ET AUDIT FINAL DU RADAR INTELLIGENT 9DILI EXPRESS

**Projet :** 9DILI EXPRESS (Flutter Android · Cloudflare Workers · Firebase `dili-express`)  
**Branche Git :** `main` | **Commit de référence :** `36e5c3d2da989fe911ba460db65978de0873d159`  
**Date d'audit :** 16-17 Octobre 2026  
**Type d'évaluation :** Audit technique pré-déploiement en lecture seule stricte (zéro modification source, zéro commande distante, zéro déploiement)  
**Auteur de l'audit :** Antigravity Engine (Senior System & Cloud Architecture Auditor)  

---

## 1. Synthèse Exécutive et Décision Finale

| Indicateur | Valeur / Statut | Commentaire |
| :--- | :--- | :--- |
| **Décision Finale** | 🛑 **BLOQUÉ** | Le radar **ne peut pas** être autorisé au déploiement en production dans son état actuel. |
| **Statut Tests Worker** | ✅ **64 / 64 PASS** (100%) | Exécutés localement via Node.js / Jest en 539 ms. |
| **Statut Tests Flutter** | ✅ **77 / 77 PASS** (100%) | Exécutés localement via `flutter test` en 7s. |
| **Analyse Statique Flutter** | ✅ **0 issue** | `flutter analyze` passé avec succès en 17.4s. |
| **Intégrité Git** | ✅ **Propre** | `git diff --check` = 0 anomalie. Aucun secret committé. |
| **Attribution Atomique** | ✅ **CONFORME** | Précondition `currentDocument.updateTime` sur Firestore REST. |
| **Confidentialité & FCM** | ✅ **CONFORME** | Unicast strict. Zéro fuite de données personnelles ou sensibles. |
| **Respect Plafond 10 km** | ❌ **NON CONFORME (FAIL)** | `MAX_RADIUS_KM = 15.0` et calcul Vague 4 atteignant **11.0 km**. |
| **Autonomie Cron 15s** | ⚠️ **NON RESPECTÉ (CRON SEUL)** | Cron Cloudflare limité à 1 min ; `scheduled()` est un stub vide. |

### Décision Formelle :
> 🛑 **DÉPLOIEMENT BLOQUÉ**  
> Deux anomalies bloquantes empêchent l'autorisation de mise en production :
> 1. **Dépassement du rayon maximal (Point Bloquant Métier)** : Le code source calcule un rayon de **11.0 km** en Vague 4 au lieu d'un plafond strict de **10.0 km**, et `RADAR_CONFIG.MAX_RADIUS_KM` est configuré à `15.0`.
> 2. **Ordonnancement autonome des vagues à 15s non assuré par le Cron (Point Bloquant Opérationnel)** : Le déclencheur Cloudflare Cron Trigger ne descend pas en dessous de 60 secondes (limite plateforme), et le handler `scheduled()` dans `src/index.js` n'interroge pas Firestore pour faire avancer les vagues. Le délai de 15 secondes n'est fonctionnel que si l'API `/api/radar/next-wave` est appelée activement par le client ou un orchestrateur externe.

---

## 2. Inventaire Exhaustif des Fichiers Audités

Tous les fichiers mentionnés ci-dessous ont été intégralement audités et vérifiés sur le disque local dans `/root/dili_express/` :

```
dili_express/
├── workers/notifications_dispatcher/
│   ├── src/
│   │   ├── index.js                     # Point d'entrée Worker, routage HTTP et handler scheduled()
│   │   ├── radar_config.js              # Paramètres métriques du radar (rayons, timeouts, limites)
│   │   ├── radar_service.js             # Cœur algorithmique : requêtes RTDB/Firestore, vagues, attribution
│   │   ├── geo.js                       # Trigonométrie Haversine et bounding box GPS
│   │   ├── fcm.js                       # Notifications HTTP v1 via compte de service OAuth2
│   │   ├── firestore.js                 # Couche REST Firestore & gestion des documents/locks
│   │   ├── events.js                    # Templates de notification (sanitization stricte)
│   │   ├── security.js                  # Validation JWT RS256 Firebase Auth
│   │   ├── distributed_lock.js          # Verrou distribué Firestore
│   │   └── validation.js                # Validation de schéma des requêtes entrantes
│   ├── tests/
│   │   ├── radar_service.test.js        # 16 tests unitaires du radar (géofencing, attribution, etc.)
│   │   ├── geo.test.js                  # 9 tests unitaires de géométrie (Haversine, bounding box)
│   │   ├── fcm.test.js                  # Tests du client FCM HTTP v1
│   │   ├── events.test.js               # Tests des payloads événementiels
│   │   ├── security.test.js             # Tests de signature JWT et validation d'audience
│   │   └── distributed_lock.test.js     # Tests de concurrence du verrou distribué
│   ├── wrangler.toml                    # Configuration de déploiement Cloudflare Workers
│   └── package.json                     # Dépendances Node.js / Jest
├── lib/
│   ├── services/
│   │   ├── order_radar_service.dart     # Service client Flutter d'interaction avec le radar
│   │   ├── realtime_tracking_service.dart # Gestion du streaming GPS et présence RTDB
│   │   ├── github_update_service.dart   # Vérification OTA & intégrité SHA-256
│   │   └── location_service.dart        # Acquisition de position GPS Android
│   ├── screens/
│   │   ├── shopper_order_radar_screen.dart # Écran UI Radar pour shoppeurs avec compte à rebours
│   │   └── delivery_tracking_screen.dart   # Écran de suivi GPS temps réel
│   └── models/
│       └── errand.dart                  # Modèle de course et statuts
├── test/
│   ├── order_radar_service_test.dart    # 5 tests unitaires du service radar Flutter
│   ├── shopper_order_radar_screen_test.dart # 7 tests de widgets pour l'écran radar
│   ├── realtime_tracking_service_test.dart  # 8 tests de tracking RTDB
│   └── widget_test.dart                 # Tests d'intégration écran et validation
├── firestore.rules                      # Règles de sécurité Firestore de production
└── database.rules.json                  # Règles de sécurité Realtime Database
```

---

## 3. Matrice de Contrôle et Conformité Détaillée

| Identifiant | Intitulé du Contrôle | Statut | Référence Code | Constat & Justification Technique |
| :--- | :--- | :---: | :--- | :--- |
| **CTRL-GEO-01** | Calcul de distance Haversine | **CONFORME** | `src/geo.js:31-50` | Formule Haversine exacte ($R = 6371.0\text{ km}$), conversion radian rigoureuse, tolérance numérique $< 0.1\%$. Validé par 9 tests dans `tests/geo.test.js`. |
| **CTRL-GEO-02** | Filtrage Bounding Box GPS | **CONFORME** | `src/geo.js:71-91` | Calcul correct de $\Delta\text{lat}$ et $\Delta\text{lon} = \Delta\text{lat} / \cos(\text{lat})$. Évite le scan total des shoppeurs hors zone. |
| **CTRL-GEO-03** | Rayon initial Vague 1 = 2.0 km | **CONFORME** | `src/radar_config.js:36` | `INITIAL_RADIUS_KM: 2.0`. Vague 1 initialise bien la recherche à 2.0 km à vol d'oiseau. |
| **CTRL-GEO-04** | Progression géométrique des vagues | **NON CONFORME** | `src/radar_service.js:314, 497` | Progression calculée : $2.0 \to 5.0 \to 8.0 \to \mathbf{11.0\text{ km}}$. La 4ème vague dépasse le plafond prévu. |
| **CTRL-GEO-05** | Filtrage shoppeurs en ligne | **CONFORME** | `src/radar_service.js:235-242` | Vérification stricte du flag `isOnline === true` dans `/shopper_locations/{shopperId}` (RTDB). |
| **CTRL-GEO-06** | Exclusion du client créateur | **CONFORME** | `src/radar_service.js:231-234` | Le shoppeur candidat est exclu si `shopperId === errand.clientId`. Un client ne peut pas recevoir sa propre course. |
| **CTRL-GEO-07** | Exclusion shoppeurs déjà notifiés / occupés | **CONFORME** | `src/radar_service.js:244-255` | Exclusion des shoppeurs figurant dans `notifiedShoppers` de la vague précédente, et exclusion des shoppeurs dont le statut de mission est actif (`BUSY`, `IN_DELIVERY`). |
| **CTRL-GEO-08** | Plafond strict à 10.0 km | **NON CONFORME** | `src/radar_config.js:39` | `MAX_RADIUS_KM: 15.0`. Le plafond est fixé à 15.0 km au lieu de 10.0 km, autorisant des diffusions jusqu'à 11.0 km en Vague 4. |
| **CTRL-GEO-09** | Expiration position GPS (> 15 min) | **CONFORME** | `src/radar_service.js:225-230` | Les positions GPS datant de plus de `MAX_LOCATION_AGE_MS` ($900\,000\text{ ms} = 15\text{ min}$) sont catégoriquement rejetées. |
| **CTRL-SCHED-01** | Ordonnancement automatique 15s | **NON RESPECTÉ (CRON)** | `wrangler.toml:18`, `src/index.js:77-83` | Cloudflare Cron Trigger configuré à `* * * * *` (minimum 60s). Le handler `scheduled()` est un stub vide. Le délai de 15s ne fonctionne que via des appels HTTP successifs. |
| **CTRL-ATOM-01** | Attribution atomique exclusive | **CONFORME** | `src/radar_service.js:540-580` | Utilisation de la précondition `currentDocument.updateTime` dans l'API REST Firestore. Concurrence gérée sans double attribution. |
| **CTRL-ATOM-02** | Gestion concurrence HTTP 200 vs 409 | **CONFORME** | `src/radar_service.js:585-612` | Le gagnant reçoit `HTTP 200` (`status: accepted`). Les requêtes concurrentes ultérieures reçoivent `HTTP 409` (`status: already_assigned`). Le gagnant qui re-tente reçoit `HTTP 200` idempotent. |
| **CTRL-ATOM-03** | Cohérence transactionnelle Flutter | **CONFORME** | `order_radar_service.dart:184-210` | Implémentation miroir utilisant `FirebaseFirestore.instance.runTransaction` avec vérification de l'état `pending` avant écriture. |
| **CTRL-RULES-01** | Sécurité des Règles Firestore | **CONFORME (VIA WORKER)** | `firestore.rules:45-60` | Les règles Firestore bloquent l'écriture directe d'un shoppeur non encore assigné. L'attribution atomique DOIT passer par le Worker disposant du Service Account admin. |
| **CTRL-FCM-01** | Confidentialité & Ciblage Unicast | **CONFORME** | `src/events.js:12-45`, `src/fcm.js:65-90` | Ciblage direct par `token`. Payload épuré : nom magasin, distance, montant pourboire. Zéro adresse client, zéro PIN, zéro numéro de téléphone. |
| **CTRL-SEC-01** | Authentification JWT & Sécurité API | **CONFORME** | `src/security.js:40-110` | Validation RS256 stricte des jetons Firebase Auth, vérification du `kid`, validation d'audience `dili-express` et émetteur `securetoken.google.com/dili-express`. |

---

## 4. Preuves d'Exécution des Tests Réels

Les suites de tests ont été exécutées localement dans l'environnement PRoot sans aucune simulation :

### 4.1. Tests Unitaires du Worker (`npm test`)
```
> notifications-dispatcher@1.0.0 test
> jest --runInBand --no-cache

PASS tests/geo.test.js
PASS tests/radar_service.test.js
PASS tests/events.test.js
PASS tests/security.test.js
PASS tests/fcm.test.js
PASS tests/distributed_lock.test.js

Test Suites: 6 passed, 6 total
Tests:       64 passed, 64 total
Snapshots:   0 total
Time:        0.539 s
Ran all test suites.
```
*Taux de réussite Worker : 100% (64 tests réussis sur 64).*

### 4.2. Tests Unitaires & Widgets Flutter (`flutter test`)
```
00:07 +77: All tests passed!
```
*Taux de réussite Flutter : 100% (77 tests réussis sur 77, incluant les tests de `order_radar_service_test.dart` et `shopper_order_radar_screen_test.dart`).*

### 4.3. Analyse Statique Flutter (`flutter analyze`)
```
Analyzing dili_express...
No issues found! (ran in 17.4s)
```
*Zéro warning, zéro erreur d'analyse.*

### 4.4. Contrôle d'Intégrité Git (`git diff --check`)
```
Exit code: 0 (No whitespace errors, no syntax anomalies)
```

---

## 5. Analyses Techniques Approfondies

### 5.1. Géolocalisation & Anomalie du Plafond de 10 km (CTRL-GEO-04 / CTRL-GEO-08)

Le fichier `workers/notifications_dispatcher/src/radar_config.js` définit :
```javascript
export const RADAR_CONFIG = {
  INITIAL_RADIUS_KM: 2.0,
  MAX_RADIUS_KM: 15.0, // <-- DÉPASSEMENT DU PLAFOND CONTRACTUEL DE 10.0 KM
  RADIUS_INCREMENT_KM: 3.0,
  MAX_WAVES: 4,
  WAVE_TIMEOUT_SEC: 15,
  MAX_LOCATION_AGE_MS: 15 * 60 * 1000,
  MAX_CANDIDATES_PER_WAVE: 10,
};
```

Dans `workers/notifications_dispatcher/src/radar_service.js` (lignes 497-500) :
```javascript
const nextRadiusKm = Math.min(
  RADAR_CONFIG.INITIAL_RADIUS_KM + (nextWave - 1) * RADAR_CONFIG.RADIUS_INCREMENT_KM,
  RADAR_CONFIG.MAX_RADIUS_KM
);
```

**Calcul réel en exécution :**
- Vague 1 : $2.0\text{ km}$
- Vague 2 : $\min(2.0 + 1 \times 3.0, 15.0) = \mathbf{5.0\text{ km}}$
- Vague 3 : $\min(2.0 + 2 \times 3.0, 15.0) = \mathbf{8.0\text{ km}}$
- Vague 4 : $\min(2.0 + 3 \times 3.0, 15.0) = \min(11.0, 15.0) = \mathbf{11.0\text{ km}}$

**Conséquence :** Le radar sollicite des livreurs situés jusqu'à 11 km du magasin. Dans la réalité urbaine algérienne, 11 km à vol d'oiseau équivalent fréquemment à 15 à 20 km de distance routière réelle, ce qui est incompatible avec la promesse d'une livraison express en magasin. Ce point est **NON CONFORME**.

---

### 5.2. Ordonnancement des Vagues et Délai de 15 Secondes (CTRL-SCHED-01)

L'exigence stipule que chaque vague de recherche dure 15 secondes avant de s'élargir automatiquement à la vague suivante si aucun shoppeur n'a accepté la course.

1. **Contrainte Cloudflare Workers Free Tier :**
   Les déclencheurs Cron de Cloudflare (`crons = ["* * * * *"]`) ne peuvent pas être programmés avec une granularité inférieure à **1 minute** (60 secondes).
2. **État du code dans `src/index.js` (lignes 77-83) :**
   ```javascript
   async scheduled(event, env, ctx) {
     // Cron trigger pour balayer les vagues radar en attente
     return new Response(JSON.stringify({ status: 'scheduled_sweep_complete' }), {
       headers: { 'Content-Type': 'application/json' }
     });
   }
   ```
   La fonction planifiée est un stub vide qui n'interroge ni Firestore ni le radar.
3. **Mécanisme HTTP effectif :**
   Le Worker expose l'endpoint HTTP `POST /api/radar/next-wave` qui vérifie le champ `nextWaveDueAt` :
   ```javascript
   if (now < state.nextWaveDueAt) {
     return { advanced: false, reason: 'wave_timeout_not_reached', waitSeconds: Math.ceil((state.nextWaveDueAt - now) / 1000) };
   }
   ```
   Le délai de 15 secondes est donc parfaitement vérifié **si et seulement si** une entité externe (l'application Flutter du client demandeur ou l'écran radar) déclenche l'appel HTTP. Par conséquent, l'autonomie pure en arrière-plan via cron seul est **NON RESPECTÉE**.

---

### 5.3. Mécanisme d'Attribution Atomique et Concurrence (CTRL-ATOM-01 à 03)

L'attribution de la course lorsqu'un shoppeur clique sur "Accepter" doit être strictement exclusive (zéro double assignation).

#### Implémentation Worker REST (`src/radar_service.js`) :
Le Worker utilise l'API REST de Firestore avec la condition `currentDocument.updateTime` :
```javascript
const patchUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/errands/${errandId}?updateMask.fieldPaths=status&updateMask.fieldPaths=shopperId&currentDocument.updateTime=${readTime}`;
```

1. **Course concurrente :** Si deux shoppeurs $A$ et $B$ cliquent en même temps, le premier arrivé met à jour le document Firestore. Le document acquiert un nouveau `updateTime`.
2. **Rejet atomique du second :** La requête du shoppeur $B$ échoue avec une erreur `400/412 Precondition Failed` de Google Firestore. Le Worker intercepte ce rejet, vérifie l'état actuel du document et renvoie :
   `HTTP 409 Conflict` avec `{ "status": "already_assigned", "assignedTo": "<shopper_A_id>" }`.
3. **Idempotence :** Si le shoppeur $A$ renvoie sa requête suite à un micro-décrochage réseau, le Worker constate que `errand.shopperId === shopperA.id` et renvoie immédiatement un `HTTP 200 OK` avec `{ "status": "accepted", "idempotent": true }`.
4. **Cohérence avec les Règles Firestore :** Les règles Firestore (`firestore.rules`) interdisent à un utilisateur non assigné de modifier `errands/{errandId}`. L'appel d'assignation passe impérativement par le Worker authentifié via Service Account, ce qui empêche toute triche directe depuis le SDK mobile.

---

### 5.4. Notifications FCM et Protection de la Vie Privée (CTRL-FCM-01)

L'audit de `src/events.js` et `src/fcm.js` valide le respect strict de la vie privée :

1. **Ciblage Unicast :** Les notifications sont envoyées directement au `fcmToken` du shoppeur sélectionné. Aucun topic public ou partagé n'est utilisé pour diffuser les nouvelles courses.
2. **Assainissement du Payload (Sanitization) :**
   ```javascript
   data: {
     eventType: 'NEW_ERRAND_AVAILABLE',
     errandId: errand.id,
     storeName: errand.storeName,
     distanceKm: candidate.distanceKm.toFixed(1),
     estimatedEarning: `${errand.shopperFee || 300} DZD`,
     expiresAt: new Date(Date.now() + 15000).toISOString(),
   }
   ```
   - **Adresse personnelle du client :** Absente.
   - **Coordonnées GPS exactes du client :** Absentes (seules les coordonnées du magasin sont utilisées).
   - **Numéro de téléphone du client :** Absent.
   - **Code PIN de remise de course :** Strictement exclu du payload FCM (accessible uniquement après validation en magasin).
3. **Nettoyage des jetons invalides :** Si FCM renvoie `UNREGISTERED` ou `INVALID_ARGUMENT`, le Worker capture l'erreur et désactive le jeton côté RTDB pour ne plus le solliciter.

---

## 6. Modélisation Économique et Quotas Firebase / Cloudflare

L'architecture est évaluée sur les paliers **Firebase Spark (Gratuit)** et **Cloudflare Workers (Gratuit)**.

### 6.1. Scénarios Journaliers Modélisés
- **Scénario Faible (Lancement) :** 5 courses / jour, 3 shoppeurs notifiés en moyenne par course (1.5 vague).
- **Scénario Moyen (Croissance) :** 25 courses / jour, 6 shoppeurs notifiés par course (2 vagues).
- **Scénario Fort (Pic d'activité) :** 100 courses / jour, 12 shoppeurs notifiés par course (3 vagues).

| Ressource | Quota Gratuit Journalier | Scénario Faible (5/j) | Scénario Moyen (25/j) | Scénario Fort (100/j) | Taux d'Utilisation Max |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Requêtes Cloudflare Workers** | 100 000 req/jour | ~50 req/j | ~350 req/j | ~2 000 req/j | **2.0%** ✅ |
| **Lectures Firestore** | 50 000 / jour | ~40 / jour | ~300 / jour | ~1 800 / jour | **3.6%** ✅ |
| **Écritures Firestore** | 20 000 / jour | ~15 / jour | ~100 / jour | ~550 / jour | **2.7%** ✅ |
| **Bande Passante RTDB** | 10 Go / mois (~330 Mo/j) | ~2 Mo/j | ~15 Mo/j | ~80 Mo/j | **24.2%** ✅ |
| **Connexions RTDB Simultanées** | 100 simultanées | 5-10 shoppeurs | 20-35 shoppeurs | 60-80 shoppeurs | **80.0%** ⚠️ |
| **Messages FCM HTTP v1** | Illimité (gratuit) | ~15 / jour | ~150 / jour | ~1 200 / jour | **0% impact coût** ✅ |

**Conclusion Coût :** Le système opère à **0 $/mois** dans tous les scénarios. En cas de dépassement de 80-100 shoppeurs connectés simultanément en temps réel sur la RTDB, une bascule vers le plan Blaze (à paiement à l'usage, restant inférieur à quelques centimes) devra être anticipée.

---

## 7. Tableau des Points Bloquants et Risques Résiduels

| Niveau | Problème Identifié | Impact | Solution Requise |
| :---: | :--- | :--- | :--- |
| 🛑 **BLOQUANT** | `MAX_RADIUS_KM` fixé à 15.0 et Vague 4 calculant 11.0 km. | Violation des exigences métier ; shoppeurs trop lointains alertés ; inefficacité logistique. | Modifier `MAX_RADIUS_KM` à 10.0 dans `radar_config.js` et borner explicitement la Vague 4 à 10.0 km. |
| 🛑 **BLOQUANT** | Délai de vague 15s dépendant d'un appel externe (`scheduled()` inactif). | Si le smartphone du client se met en veille, les vagues 2, 3 et 4 ne sont jamais déclenchées. | Soit connecter l'UI du client à un timer actif de rappel HTTP, soit implémenter une boucle de relance via Cloudflare Queues / Durable Objects si disponible. |
| ⚠️ **RISQUE** | Concurrence sur RTDB $>100$ shoppeurs connectés. | Erreurs de connexion RTDB Spark si plus de 100 livreurs sont en ligne simultanément. | Activer la déconnexion automatique des shoppeurs inactifs et prévoir la surveillance du quota de connexions simultanées. |

---

## 8. Conditions Préalables à l'Autorisation de Déploiement

Pour lever le statut **BLOQUÉ** et autoriser l'exécution de `wrangler deploy`, les conditions suivantes doivent être formellement satisfaites lors d'une phase de correction dédiée :

1. **Correction du rayon :** Mettre à jour `radar_config.js` (`MAX_RADIUS_KM: 10.0`) et sécuriser les fonctions `dispatchRadarWave` et `advanceRadarWave` pour garantir la progression exacte : **2.0 km, 5.0 km, 8.0 km, 10.0 km**.
2. **Couverture de test du plafond :** Ajouter un test unitaire explicite vérifiant qu'un shoppeur situé à 10.1 km n'est JAMAIS inclus dans la Vague 4.
3. **Formalisation de l'orchestrateur de vagues :** Documenter et valider dans le code Flutter que l'écran de suivi client maintient un `Timer.periodic` de 15 secondes pour solliciter `advanceRadarWave` tant que la course est `pending`.
4. **Validation complète :** Exécuter à nouveau la chaîne d'assurance qualité (`npm test`, `flutter test`, `flutter analyze`).

---

## 9. Décision Finale d'Audit

| Verdict | Mot-clé Réglementaire | Action Autorisée |
| :---: | :---: | :--- |
| 🛑 | **BLOQUÉ** | **AUCUN DÉPLOIEMENT EN PRODUCTION N'EST AUTORISÉ.** Les fichiers sources doivent d'abord être corrigés dans une phase de maintenance dédiée, conformément aux recommandations du présent rapport et du rapport de conformité du rayon. |

*Rapport établi et certifié conforme le 16-17 Octobre 2026 par Antigravity Engine.*
