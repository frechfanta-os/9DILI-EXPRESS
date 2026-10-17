# PROMPT À TRANSMETTRE À ANTIGRAVITY
## Mission : réparer la chaîne de notification du projet 9DILI EXPRESS

---

## 0. RÔLE ET MODE D'EXÉCUTION

Tu es un ingénieur senior Flutter / Firebase / Cloudflare Workers travaillant sur le dépôt local `/root/dili_express`.

**Mode de travail imposé :**
1. **Phase 1 — Reconnaissance (lecture seule)** : relis les fichiers cités dans l'audit ci-dessous et confirme chaque constat avec des références `fichier:ligne`.
2. **Phase 2 — Plan** : produis un plan de correction numéroté, avec pour chaque point : fichier touché, nature du changement, risque de régression, test associé.
3. **Phase 3 — Implémentation** : applique les correctifs **P0**, puis **P1**, puis **P2** (dans cet ordre), une catégorie à la fois.
4. **Phase 4 — Vérification** : exécute les commandes de validation listées au §5 et colle les sorties réelles.
5. **Phase 5 — Rapport** : écris le rapport final dans `/root/dili_express/RAPPORT_CORRECTION_NOTIFICATIONS_9DILI_EXPRESS.md`.

**Règle absolue :** aucun constat de l'audit ne doit être « contourné » ou juste documenté. Chaque anomalie doit être **réellement corrigée dans le code** ou explicitement marquée `NON CORRIGÉE + justification technique`.

---

## 1. CONTEXTE DU PROJET

- **Application** : 9DILI EXPRESS (livraison / courses à la demande, Algérie).
- **Identifiant Android** : `com.ghdinteractivestudio.dili_express` (conforme aux directives d'organisation `com.ghdinteractivestudio`).
- **Stack** : Flutter (Dart), Firebase (Firestore + Auth + App Check), backend 100 % **Cloudflare Worker** (zéro Cloud Function, plan Firebase Spark).
- **Rôles métier** : `client` (crée la course, valide l'offre) et `shopper` (accepte la course, achète, livre, clôture par PIN).
- **Cycle de vie d'une course** (`lib/models/errand_model.dart`) :
  `pending → accepted → shopping → delivering → completed` (+ `cancelled`).
- **Worker** : `workers/notifications_dispatcher/` (endpoints `/api/notify`, `/api/radar/dispatch`, `/api/radar/next-wave`, `/api/radar/accept`, `/api/radar/decline`, `/api/radar/status`, `/health`, + consumer Queues + handler `scheduled`).
- **État du Worker** : 79 tests Node.js passent (`npm test`), code prêt mais **jamais déployé** (secret `FIREBASE_SERVICE_ACCOUNT` non injecté).

---

## 2. RAPPORT D'AUDIT COMPLET (verdict : 🛑 CHAÎNE NON FONCTIONNELLE)

### 2.1 Verdict global

Le **backend** (Worker Cloudflare) et la **configuration Android** sont solides et testés, **mais le maillon applicatif est entièrement absent** : le service de notification Flutter existe sous forme de **code mort** et l'application **ne communique jamais** avec le Worker. Conséquence : **aucune notification métier ne peut être déclenchée ni reçue en production.**

```
App Flutter ──(AUCUN LIEN)──✗── Worker Cloudflare ──> FCM HTTP v1 ──> Appareil
     │                                    │
     └─ notification_service.dart ────> Firestore /users/{uid}/fcm_tokens
        (jamais instancié)
```

### 2.2 Composants vérifiés

| Couche | Fichier | État |
|---|---|---|
| Service FCM côté app | `lib/services/notification_service.dart` | ⚠️ Écrit mais **jamais utilisé** |
| Intégration au démarrage | `lib/main.dart` | ❌ Aucun `FirebaseMessaging` |
| Worker de dispatch | `workers/notifications_dispatcher/src/index.js` | ✅ Code complet + 79 tests PASS |
| Envoi FCM HTTP v1 | `workers/notifications_dispatcher/src/fcm.js` | ✅ Conforme (`UNREGISTERED`) |
| Logique métier / anti-fuite | `workers/notifications_dispatcher/src/events.js` | ✅ Assainie (zéro PIN/GPS) |
| Règles Firestore tokens | `firestore.rules:37-40` | ✅ `isOwner` strict |
| Manifeste Android | `android/app/src/main/AndroidManifest.xml` | ✅ Permissions OK |
| Config iOS | `ios/Runner/*` | ❌ Non configuré |

### 2.3 Anomalies BLOQUANTES (P0)

**❌ P0-1 — `NotificationService` est du code mort.**
`lib/services/notification_service.dart:43` définit la classe, mais **aucun fichier ne l'importe, ne l'instancie ni n'appelle `initializeForUser()`**. Un `grep` sur `lib/`, `test/` et `workers/` ne retourne que les auto-références du fichier (`:43`, `:52`, `:72`).
→ Le token FCM **n'est jamais écrit** dans `/users/{uid}/fcm_tokens` ni dans `users/{uid}.fcmToken`.
→ Le Worker lit `fcmToken` racine (`src/firestore.js:80-96`) et retourne donc toujours `recipient_has_no_fcm_token` (`src/index.js:234-241`). **Toutes les notifications unicast échouent.**

**❌ P0-2 — L'application ne déclenche jamais le Worker.**
`grep` de `/api/notify`, `/api/radar/*`, `workers.dev`, `dispatcher` dans `lib/` → **0 résultat**. De plus, `pubspec.yaml` ne contient **aucun client HTTP** (`http` / `dio`).
→ L'application est **techniquement incapable** de joindre le Worker.
→ Aucun événement `bid_accepted`, `errand_accepted`, `shopper_delivering`, `shopper_arrived`, `errand_completed`, `errand_cancelled` n'est jamais émis, alors que la logique `src/events.js` est conforme et prête.

**❌ P0-3 — Aucun handler de message en arrière-plan.**
Pas de `FirebaseMessaging.onBackgroundMessage(...)` (fonction top-level) dans `lib/main.dart`. Les messages *data-only* en arrière-plan ou application tuée ne sont pas traités.

**❌ P0-4 — Aucun traitement du tap sur notification.**
Ni `onMessageOpenedApp`, ni `getInitialMessage`. Cliquer une notification ouvre l'application mais **ne navigue vers aucune course**.

### 2.4 Anomalies IMPORTANTES (P1)

**⚠️ P1-1 — Le canal `errand_updates_channel` n'existe pas à l'exécution.**
Le Worker cible `channel_id: 'errand_updates_channel'` (`src/fcm.js:147`) et le manifeste le déclare par défaut (`AndroidManifest.xml:49-51`). Mais **le canal n'est jamais créé** : aucun code natif `NotificationChannel`, et `flutter_local_notifications` est absent de `pubspec.yaml`.
→ FCM bascule sur le canal de secours (« Miscellaneous ») : **perte du son personnalisé et de la priorité haute** configurés côté Worker.

**⚠️ P1-2 — Incohérence du contrat de données du payload.**
`lib/services/notification_service.dart:34` attend `data['status']` pour `newStatus`, alors que le Worker n'envoie que `errandId`, `eventType`, `distanceKm`, `storeName` (`src/index.js:217-220`, `src/index.js:251-254`, `src/radar_service.js:409-412`).
→ `newStatus` sera **toujours `null`**.

**⚠️ P1-3 — iOS non configuré.**
`ios/Runner/Info.plist` n'a pas `UIBackgroundModes: remote-notification`, et `ios/Runner/AppDelegate.swift` n'enregistre pas APNs, alors que `lib/main.dart:45` active `AppleDeviceCheckProvider`. Le projet est Android-first, mais la voie iOS est absente.

### 2.5 Anomalies MINEURES (P2)

| # | Détail | Emplacement |
|---|---|---|
| P2-1 | Double demande de permission : au démarrage (`main.dart:86`) **et** dans `initializeForUser()` (`notification_service.dart:116`) | incohérence UX |
| P2-2 | `getDiagnosticReport()` appelle `requestPermission()` → un diagnostic peut rouvrir le dialogue système (effet de bord non neutre) | `notification_service.dart:212` |
| P2-3 | `_saveTokenToFirestore` et `unregisterUser` avalent **toutes** les erreurs (`catch (_) {}`) → aucun log exploitable | `notification_service.dart:174`, `:201` |
| P2-4 | `dispose()` ne `await` pas l'annulation des souscriptions | `notification_service.dart:223-227` |
| P2-5 | L'app est purement Firestore-local alors que le Radar dépend d'un appel actif à `/api/radar/next-wave` (déjà signalé dans `REVUE_TECHNIQUE_RADAR_9DILI_EXPRESS.md`) | app ↔ worker |

### 2.6 Ce qui est CONFORME (à ne pas casser)

- Worker : JWT obligatoire (`security.js`), état autoritatif Firestore, idempotence + verrou distribué, **unicast strict**, payload assaini sans PIN ni GPS (`src/events.js:281-289`), gestion des jetons obsolètes `UNREGISTERED` / `INVALID_ARGUMENT` (`src/fcm.js:179`).
- Tests Worker : **79 / 79 PASS**.
- `flutter analyze lib/main.dart lib/services/notification_service.dart` → *No issues found*.
- Android : `POST_NOTIFICATIONS` déclarée (`AndroidManifest.xml:11`) ; `queries` DIAL + INSTALL_PACKAGE conformes.
- Firestore : sous-collection `fcm_tokens` réservée au propriétaire (`firestore.rules:37-40`).

### 2.7 Écart documentation / réalité

`RAPPORT_AUDIT_AUTORISATIONS_NOTIFICATIONS_9DILI.md` conclut que « l'intégration Flutter et Cloudflare est parfaitement alignée ». **C'est inexact** : le service a été créé mais jamais branché et aucun appel au Worker n'existe. Corrige cette affirmation dans la documentation.

---

## 3. TRAVAIL DEMANDÉ

### 3.1 Correctifs P0 (obligatoires)

1. **Câbler `NotificationService`**
   - Instancier le service dans `lib/main.dart` (injection dans l'arbre des services, cohérent avec `AuthService` / `ErrandService` / `UserService`).
   - Sur `authStateChanges` : appeler `initializeForUser(uid)` quand un utilisateur est authentifié, `unregisterUser()` à la déconnexion.
   - Le service doit exposer son état pour que l'UI puisse réagir (`onForegroundNotification`).

2. **Créer la couche d'appel au Worker**
   - Ajouter le client HTTP nécessaire au `pubspec.yaml`.
   - Créer `lib/services/notification_dispatch_service.dart` (nom indicatif) qui :
     - récupère le jeton Firebase ID (`user.getIdToken()`) et le passe en `Authorization: Bearer <token>` ;
     - appelle `POST {BASE_URL}/api/notify` avec `{ errandId, eventType, idempotencyKey? }` ;
     - appelle les endpoints radar nécessaires (`/api/radar/dispatch`, `/api/radar/accept`, `/api/radar/decline`, `/api/radar/next-wave`) selon le mode client/shopper ;
     - gère proprement : `409` (doublon → ignorer), `404`, `504` (ne pas réémettre), absence de réseau (dégradation gracieuse, jamais de crash).
   - L'URL de base doit être **configurable** (constante + `--dart-define` si possible), **jamais** un secret.

3. **Brancher les déclencheurs métier**
   - Dans `lib/services/errand_service.dart`, émettre l'événement correspondant **après** chaque transition de statut réussie :
     | Méthode | Événement |
     |---|---|
     | `createErrand` (`:109`) | `new_errand_available` (via radar) |
     | `acceptBid` (`:425`) | `bid_accepted` |
     | `confirmErrandAssignment` (`:279`) / `assignShopperAtomic` (`:528`) | `errand_accepted` |
     | `startShopping` (`:295`) | — (pas d'événement dédié) |
     | `startDelivering` (`:301`) | `shopper_delivering` |
     | arrivée sur place | `shopper_arrived` |
     | `completeErrandWithPin` (`:314`) | `errand_completed` |
     | `cancelErrand` (`:606`) | `errand_cancelled` |
   - **Interdit** de faire échouer la transition Firestore si l'appel Worker échoue : la notification est un effet secondaire non bloquant.
   - **Interdit** d'appeler le Worker depuis l'UI ; passer par les services.

4. **Handler d'arrière-plan + tap**
   - Déclarer une fonction **top-level** `@pragma('vm:entry-point') Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message)` et l'enregistrer dans `main()`.
   - Implémenter `FirebaseMessaging.onMessageOpenedApp` et `FirebaseMessaging.instance.getInitialMessage()` pour naviguer vers la course concernée (`errandId`).

### 3.2 Correctifs P1 (obligatoires)

5. **Créer réellement le canal `errand_updates_channel`** (importance `high`, son actif, description alignée sur `notification_service.dart:44-47`), par le moyen le plus propre disponible, et garantir qu'il existe **avant** le premier push. Le nom du canal doit rester **strictement identique** à celui du Worker et du manifeste.

6. **Aligner le contrat de payload** : soit le Worker ajoute `status` dans `data`, soit le mapping côté Flutter dérive le statut depuis `eventType`. Choisir une seule source de vérité et la documenter. Ne pas casser les 79 tests Worker.

7. **iOS** : ajouter `UIBackgroundModes: remote-notification` à `ios/Runner/Info.plist` et l'enregistrement APNs dans `AppDelegate.swift` — **ou** documenter explicitement que la plateforme est hors périmètre de cette itération (choix assumé, pas oubli).

### 3.3 Correctifs P2 (recommandés)

8. Une seule demande de permission de notification, au moment opportun et avec justification UX (pas au démarrage à froid en même temps que caméra/géoloc).
9. Rendre `getDiagnosticReport()` **neutre** : ne pas déclencher de dialogue système ; lire l'état courant.
10. Remplacer les `catch (_) {}` silencieux par des logs (`debugPrint`) exploitables.
11. `dispose()` : attendre/annuler proprement les souscriptions.
12. Documenter ou implémenter l'orchestration du Radar côté app (le délai de 15 s ne peut pas venir du cron Cloudflare, limité à 60 s).

---

## 4. CONTRAINTES STRICTES (directives d'organisation)

1. **Identifiant applicatif** : ne jamais modifier `applicationId` / `namespace` / bundle → doit rester `com.ghdinteractivestudio.dili_express`. Aucun `com.example`.
2. **Aucun secret dans le code ou dans Git.** Le compte de service Google reste exclusivement dans les secrets Cloudflare (`wrangler secret put FIREBASE_SERVICE_ACCOUNT`).
3. **Aucun déploiement Cloudflare** dans cette mission (`wrangler deploy` est une action manuelle, hors périmètre).
4. **Ne pas toucher** aux éléments OTA du `AndroidManifest.xml` requis par les directives du projet : `<queries>` avec `VIEW` + `INSTALL_PACKAGE` (`application/vnd.android.package-archive`) et les packages `com.google.android.packageinstaller` / `com.android.packageinstaller`. Ne jamais définir `android:taskAffinity=""`.
5. **Ne pas affaiblir `firestore.rules`** : la sous-collection `fcm_tokens` doit rester réservée au propriétaire.
6. **Ne pas casser les tests existants** (Flutter : `test/`, Worker : `workers/notifications_dispatcher/test/`).
7. Respecter le style, le nommage et les patterns déjà présents dans le dépôt.
8. Traiter tout fichier inconnu ou modifié comme du travail utilisateur : ne rien supprimer sans enquête.

---

## 5. VALIDATION OBLIGATOIRE (preuves exigées)

Exécute et **colle les sorties réelles** :

```bash
cd /root/dili_express
flutter analyze
flutter test
```

```bash
cd /root/dili_express/workers/notifications_dispatcher
npm test
```

Ajoute en plus :
- un test Flutter qui vérifie que `initializeForUser` écrit le token dans Firestore (ou un test vérifiant l'instanciation/câblage du service) ;
- un test Flutter qui vérifie que chaque transition de statut déclenche le bon `eventType` auprès du dispatcher (mock du client HTTP) ;
- un test qui vérifie que l'échec de l'appel Worker **ne fait pas** échouer la transition Firestore.

---

## 6. LIVRABLES ATTENDUS

1. Le code corrigé (P0 puis P1 puis P2).
2. Les nouveaux fichiers de test.
3. Un rapport `/root/dili_express/RAPPORT_CORRECTION_NOTIFICATIONS_9DILI_EXPRESS.md` contenant :
   - le tableau des anomalies avec le statut final (`CORRIGÉE` / `NON CORRIGÉE + justification`) et la référence `fichier:ligne` de la correction ;
   - la liste exacte des fichiers modifiés/créés ;
   - les sorties brutes des commandes de validation ;
   - la procédure manuelle restante (injection du secret, déploiement, test sur appareil physique réel) ;
   - la correction de l'affirmation erronée de `RAPPORT_AUDIT_AUTORISATIONS_NOTIFICATIONS_9DILI.md`.
4. Un `git diff --stat` final.

---

## 7. CRITÈRES D'ACCEPTATION

| # | Critère | Preuve |
|---|---|---|
| 1 | `NotificationService` est instancié et appelé sur `authStateChanges` | `grep` non vide hors de son propre fichier |
| 2 | Un token FCM réel est écrit dans `/users/{uid}/fcm_tokens` et `users/{uid}.fcmToken` sur appareil physique | capture / log Firestore |
| 3 | Chaque transition de statut émise par l'app déclenche un appel `/api/notify` avec le bon `eventType` | test + logs |
| 4 | Un échec Worker n'empêche jamais la transition Firestore | test dédié |
| 5 | Le canal `errand_updates_channel` existe à l'exécution et reçoit les push en priorité haute | `adb shell dumpsys notification --noredact` ou capture |
| 6 | Un tap sur notification navigue vers la bonne course (y compris app tuée → `getInitialMessage`) | test / démonstration |
| 7 | `flutter analyze` = 0 issue ; `flutter test` = 100 % PASS ; `npm test` = 100 % PASS | sorties collées |
| 8 | Aucune régression sur le cycle de vie des courses ni sur les règles Firestore | tests d'intégration |

---

## 8. FORMAT DE RÉPONSE ATTENDU

Commence par :
1. **Reconnaissance** : confirmation ou infirmation de **chaque** constat P0/P1/P2, avec `fichier:ligne`.
2. **Plan** de correction numéroté.
3. **Implémentation** (par catégorie).
4. **Preuves de validation**.
5. **Rapport final** + `git diff --stat`.

Si un constat de l'audit s'avère **inexact** après vérification, dis-le explicitement et justifie-le par le code — ne corrige pas un problème qui n'existe pas.
