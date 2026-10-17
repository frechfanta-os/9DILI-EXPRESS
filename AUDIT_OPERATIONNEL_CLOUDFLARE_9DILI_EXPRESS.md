# 9DILI EXPRESS — AUDIT OPÉRATIONNEL CLOUDFLARE EN LECTURE SEULE

> **Document** : `AUDIT_OPERATIONNEL_CLOUDFLARE_9DILI_EXPRESS.md`  
> **Date** : 17 Octobre 2026  
> **Projet** : 9DILI EXPRESS (`com.ghdinteractivestudio.dili_express`)  
> **Dépôt** : `https://github.com/frechfanta-os/9DILI-EXPRESS.git`  
> **Branche de référence** : `main`  
> **Commit de référence audité** : `36e5c3d2da989fe911ba460db65978de0873d159`  
> **Environnement de test** : Android / Termux / Ubuntu PRoot / Node.js v22.22.1 / npm 9.2.0  
> **Mode** : Lecture seule stricte, aucune modification locale ou distante, aucune installation d'outils, aucun secret affiché

---

## A. Résumé Exécutif

Cet audit opérationnel a été conduit dans le respect rigoureux du mode lecture seule afin d'évaluer la disponibilité opérationnelle de l'infrastructure Cloudflare pour le dispatcher de notifications du projet 9DILI EXPRESS.

### Verdict : 🟡 **GO CONDITIONNEL (VALIDATION TECHNIQUE LOCALE) / ATTENTE D'ACCÈS CLOUDFLARE DISTANT**

- **Sur le plan logiciel et architectural local** : **CONFORME À 100% (PASS)**.  
  La configuration locale (`wrangler.toml`), le code source du Worker (`src/`), la gestion des files Cloudflare Queues et de la DLQ, le repli Cron Sweep, la validation cryptographique RS256, l'exclusion du créateur, le mode simulation sans secret et les 157 tests automatisés sont parfaitement cohérents et validés.
- **Sur le plan opérationnel distant Cloudflare** : **NON VÉRIFIÉ — AUTORISATION ET ACCÈS REQUIS**.  
  L'exécutable Wrangler n'étant pas préinstallé dans l'environnement local et tout téléchargement/installation via `npx` ou `npm` étant strictement proscrit par les règles de la mission, aucune ressource distante Cloudflare (existence des queues, présence effective du secret, état de publication) n'a pu être interrogée à ce stade.

---

## B. Tableau Détaillé des Contrôles

| Élément Contrôlé | Méthode & Commande Exacte Utilisée | Résultat Observé | Statut | Limites du Contrôle |
| :--- | :--- | :--- | :---: | :--- |
| **Disponibilité Node.js** | `node --version` | `v22.22.1` | **PASS** | Environnement d'exécution local uniquement. |
| **Disponibilité npm** | `npm --version` | `9.2.0` | **PASS** | Gestionnaire de paquets présent. |
| **Présence Wrangler dans le PATH** | `command -v wrangler` | `wrangler_not_in_PATH` (code 1) | **FAIL (Outil absent)** | Wrangler n'est pas installé dans le PATH global. |
| **Présence Wrangler local** | `ls workers/notifications_dispatcher/node_modules/.bin/wrangler` | `no_local_wrangler` (code 2) | **FAIL (Outil absent)** | Aucun binaire local Wrangler présent. |
| **Résolution sans téléchargement** | Résolution shell sans `npx` permissif | Tentative `npx` avortée car déclenchant l'invite `Need to install packages: wrangler` | **PASS (Règle respectée)** | Téléchargement non autorisé bloqué immédiatement. |
| **Nom du Worker local** | Inspection `wrangler.toml` (Ligne 1) | `name = "dili-express-notifications-dispatcher"` | **PASS** | Conforme au nom attendu dans le projet. |
| **Variables d'environnement** | Inspection `wrangler.toml` (Lignes 5-7) | `FIREBASE_PROJECT_ID = "dili-express"`, `ENVIRONMENT = "production"` | **PASS** | Cohérent avec le projet Firebase de production. |
| **Binding Queue Producteur** | Inspection `wrangler.toml` (Lignes 20-22) | `binding = "RADAR_QUEUE"`, `queue = "dili-express-radar-queue"` | **PASS** | Vérifié localement dans le fichier de config. |
| **Consommateur Queue & DLQ** | Inspection `wrangler.toml` (Lignes 24-29) | `max_batch_size = 5`, `max_batch_timeout = 5`, `max_retries = 3`, `dead_letter_queue = "dili-express-radar-dlq"` | **PASS** | Paramétrage résilient conforme aux exigences. |
| **Déclencheur Cron local** | Inspection `wrangler.toml` (Lignes 15-16) | `crons = ["* * * * *"]` | **PASS** | Déclenché toutes les minutes dans la config. |
| **Cohérence bindings / code** | `grep -rn "RADAR_QUEUE" workers/notifications_dispatcher/` | Lignes 441 & 447 de `radar_service.js` appellent `env.RADAR_QUEUE.send(...)` | **PASS** | Parfaite adéquation entre code source et binding. |
| **Consommateur `queue()`** | Inspection `workers/notifications_dispatcher/src/index.js` (L514-592) | Traite `advance_radar_wave`, idempotence, `msg.ack()`, `msg.retry()` | **PASS** | Logique de retry et idempotence validée par test unitaire. |
| **File de rebut (DLQ)** | Inspection `wrangler.toml` (L29) | `dead_letter_queue = "dili-express-radar-dlq"` | **PASS (Config locale)** | Déclaré pour recevoir les messages après 3 retries. |
| **Déclencheur `scheduled()`** | Inspection `workers/notifications_dispatcher/src/index.js` (L594-608) | Appelle `sweepPendingRadarWaves()` pour balayer les vagues échues | **PASS** | Validé localement par tests automatisés. |
| **Cadence temporelle du Cron** | Analyse d'architecture logicielle | Déclenchement à la minute (`* * * * *`) | **PARTIAL** | Un Cron à la minute ne traite pas toutes les 15s. Il sert de secours (fallback). |
| **Éligibilité Cloudflare Queue** | Analyse du paramètre `delaySeconds: 15` | `env.RADAR_QUEUE.send(..., { delaySeconds: 15 })` | **PARTIAL** | La tâche devient visible après 15s ; la livraison exacte dépend de la charge PoP. |
| **Comportement sans secret** | Inspection `src/index.js` (L195-204, L300-315) | Répond HTTP 200 en simulation explicite (`simulated: true, configured: false`) | **PASS** | Aucune défaillance silencieuse ni faux succès d'envoi. |
| **Healthcheck `/health`** | Inspection `src/index.js` (L79-87) | Répond HTTP 200 `{ status: 'ok', ... }` sans interroger Firebase | **PARTIAL** | Valide la santé du Worker, pas celle de Firebase/FCM. |
| **Exclusion du créateur** | Inspection `radar_service.js`, `events.js`, `errand_service.dart` | Élimination formelle de `clientId`, rejet 403 `cannot_assign_own_errand` | **PASS** | Verrouillé à tous les niveaux (code et tests). |
| **Attribution atomique REST** | Inspection `radar_service.js` (L565-720) | Précondition `currentDocument.updateTime`, rejet HTTP 409 `already_assigned` | **PASS** | Validé sous concurrence simulant Firestore REST. |
| **Protection `firestore.rules`** | Inspection `firestore.rules` (L58-90) | Mises à jour restreintes aux seuls créateurs ou shoppers déjà assignés | **PASS** | Les shoppers non assignés subissent `PERMISSION_DENIED`. |
| **Secrets codés en dur** | Scan regex `private_key`, `client_secret`, `BEGIN PRIVATE KEY` | 0 secret trouvé dans le code source ou la configuration | **PASS** | Aucun secret embarqué dans le dépôt. |
| **Existence des queues distantes** | Contrôle distant Cloudflare | Impossible sans exécutable Wrangler installé | **NON VÉRIFIÉ — AUTORISATION OU ACCÈS REQUIS** | Requiert `wrangler queues list` avec session active. |
| **Présence du secret distant** | Contrôle distant Cloudflare | Impossible sans exécutable Wrangler installé | **NON VÉRIFIÉ — AUTORISATION OU ACCÈS REQUIS** | Requiert `wrangler secret list` avec session active. |
| **Statut de déploiement Worker** | Contrôle distant Cloudflare | Impossible sans exécutable Wrangler installé | **NON VÉRIFIÉ — AUTORISATION OU ACCÈS REQUIS** | Requiert `wrangler deployments list` avec session active. |
| **Réception push réelle Android** | Test GSM / Google Play Services | Interdiction d'envoi de notification réelle | **NON VÉRIFIÉ — AUTORISATION REQUISE** | Dépend de terminaux physiques réels connectés. |

---

## C. État de l'Infrastructure Cloudflare

### 1. Configuration Locale Établie (Fichiers Sources)
- Fichier de configuration : `workers/notifications_dispatcher/wrangler.toml`.
- Nom du Worker : `dili-express-notifications-dispatcher`.
- Compatibilité : `2024-04-01`.
- Variables déclarées : `FIREBASE_PROJECT_ID = "dili-express"`, `ENVIRONMENT = "production"`.
- Producteur de file : `binding = "RADAR_QUEUE"` pointant vers `queue = "dili-express-radar-queue"`.
- Consommateur de file : `queue = "dili-express-radar-queue"` avec `max_retries = 3`, `max_batch_size = 5`, `max_batch_timeout = 5`, `dead_letter_queue = "dili-express-radar-dlq"`.
- Déclencheur Cron : `crons = ["* * * * *"]`.
- URL publique attendue : `https://dili-express-notifications-dispatcher.<subdomain>.workers.dev`.

### 2. Ressources Distantes Réellement Interrogées
- **Aucune**.  
  Wrangler n'étant pas disponible en local sans déclencher une installation externe non autorisée, aucun appel réseau n'a été émis vers les API Cloudflare.

### 3. Ressources Distantes Dont l'Existence Reste Inconnue
- L'existence effective de la file `dili-express-radar-queue` sur le compte Cloudflare.
- L'existence effective de la file de rebut `dili-express-radar-dlq`.
- La publication effective du Worker `dili-express-notifications-dispatcher`.
- L'activation effective du déclencheur Cron sur l'infrastructure Cloudflare.
- L'association du sous-domaine `*.workers.dev` au compte Cloudflare du projet.

---

## D. État de l'Intégration Firebase / FCM

### 1. Configuration Locale
- Projet cible : `dili-express` (déclaré dans `wrangler.toml` et `firebase_options.dart`).
- Authentification client : Validation cryptographique des jetons Firebase Auth par clés publiques Google JWKS (RS256).
- Attribution autoritative : API Firestore REST avec précondition de concurrence `currentDocument.updateTime`.
- Règles Firestore : Intactes, sanctuarisant les écritures sous la garde `resource.data.clientId == request.auth.uid || resource.data.shopperId == request.auth.uid`.

### 2. Secret Distant `FIREBASE_SERVICE_ACCOUNT`
- **Statut** : **NON VÉRIFIÉ — PRÉSENCE DU SECRET FIREBASE NON CONFIRMÉE**.
- La configuration locale attend une chaîne JSON représentant le compte de service Google (avec `client_email` et `private_key`).
- Le code gère l'absence du secret de façon sécurisée (simulation explicite `simulated: true, configured: false`).
- Sa présence réelle sur l'infrastructure Cloudflare n'a pas pu être interrogée et doit être confirmée via `wrangler secret list` lors de la phase autorisée.

### 3. Fonctionnement Réel Non Testé
- Aucun push FCM réel n'a été émis vers les serveurs de production Google.
- Aucune écriture réelle n'a été soumise à la base Firestore de production `dili-express`.
- La réussite des 157 tests automatisés locaux garantit la conformité de l'algorithme sous simulation, mais ne remplace pas un smoke test opérationnel post-déploiement.

---

## E. Risques Bloquants et Analyse Opérationnelle

### 1. Risques Bloquants Identifiés
1. **Absence de l'outil Wrangler dans l'environnement d'exécution** :
   - Pour exécuter des opérations de déploiement ou de vérification distante, l'administrateur devra autoriser l'installation locale de Wrangler (`npm install --save-dev wrangler` dans `workers/notifications_dispatcher/` ou utilisation de `npx` avec téléchargement approuvé).
2. **Incertitude sur le provisionnement des Queues Cloudflare** :
   - Si le Worker est déployé avant que les files `dili-express-radar-queue` et `dili-express-radar-dlq` ne soient créées sur le compte Cloudflare, le déploiement échouera avec une erreur de binding manquant.
3. **Incertitude sur la présence du secret `FIREBASE_SERVICE_ACCOUNT`** :
   - Si le secret n'est pas déposé sur Cloudflare avant le premier appel de notification, le Worker fonctionnera en mode simulation sans délivrer de push réels sur les téléphones des commissionnaires.

### 2. Précisions Techniques Impératives
- **Délai des vagues et Cloudflare Queues** :
  L'envoi différé via `delaySeconds: 15` rend le message consommable au bout de 15 secondes. Il ne garantit pas une exécution à la milliseconde près, celle-ci étant soumise à l'ordonnancement interne des files Cloudflare (généralement 15 à 20 secondes).
- **Rôle du Cron Trigger à la minute** :
  Le déclencheur `* * * * *` ne tourne qu'une fois par minute. Il sert exclusivement de mécanisme de rattrapage durable (filet de sécurité) pour les vagues échues non traitées, et non de métronome à 15 secondes.
- **Indicateur HTTP 200 `/health`** :
  Un retour positif sur `/health` confirme uniquement que le Worker est en ligne et que l'environnement Node.js s'exécute ; il ne prouve en aucun cas la validité du secret Firebase ni l'accessibilité des API Google.

---

## F. Étapes Suivantes Ordonnées (Sous Réserve d'Autorisation Explicite)

Lorsque l'autorisation de procéder sera accordée par l'utilisateur, exécuter dans l'ordre strict :

### 1. Préparation de l'environnement d'outillage
Autoriser l'utilisation de Wrangler pour la session :
```bash
cd /root/dili_express/workers/notifications_dispatcher
# Option A : Installation locale propre
npm install --save-dev wrangler
# Option B : Autorisation ponctuelle npx
npx wrangler whoami
```

### 2. Vérification de l'identité Cloudflare (Lecture Seule)
```bash
npx wrangler whoami
```
*Critère* : Confirmer que le compte connecté correspond au propriétaire du projet 9DILI EXPRESS.

### 3. Provisionnement des Queues Cloudflare
```bash
npx wrangler queues create dili-express-radar-queue
npx wrangler queues create dili-express-radar-dlq
```

### 4. Dépôt du Secret de Production
```bash
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT
# Coller la clé JSON du compte de service Firebase dili-express (avec client_email et private_key)
```

### 5. Déploiement du Worker
```bash
npx wrangler deploy
```

### 6. Smoke Tests Post-Déploiement
- Interroger `/health` : `curl -s https://dili-express-notifications-dispatcher.<subdomain>.workers.dev/health`
- Vérifier le statut d'une course fictive : `curl -s https://dili-express-notifications-dispatcher.<subdomain>.workers.dev/api/radar/status?errandId=test`

---

## G. Conclusion & Respect des Règles d'Audit

Conformément aux règles de déontologie de cet audit :
- **Il n'est pas affirmé que le Worker est déployé** (statut distant non interrogé).
- **Il n'est pas affirmé que les queues existent sur Cloudflare** (seule la configuration locale a été validée).
- **Il n'est pas affirmé que le secret existe** (la référence locale ne constitue pas une preuve de présence distante).
- **La réception FCM n'est pas déclarée opérationnelle** (aucun test sur appareil physique n'a été réalisé).
- **Le code `/health` HTTP 200 n'est pas assimilé à une disponibilité complète**.
- **Aucune commande modificatrice distante n'a été lancée**.

L'ensemble du code local est prêt et validé. Le passage à la phase distante attend votre autorisation explicite.
