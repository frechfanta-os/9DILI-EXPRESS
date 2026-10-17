# RAPPORT D'AUDIT TECHNIQUE COMPLET — 9DILI EXPRESS (V2 STITCH)

**Date d'audit :** 17 Octobre 2026  
**Auditeur :** Antigravity Senior Engineering (Flutter/Dart, Firebase Security & Android Systems)  
**Cible :** Application mobile Android 9DILI EXPRESS  
**Package ID officiel :** `com.ghdinteractivestudio.dili_express`  
**Dépôt source :** `https://github.com/frechfanta-os/9DILI-EXPRESS`  
**Branche / Commit audité :** `main` @ `f50327fcae79d383a266d1efd17623e54f8b3eef`  
**Statut de l'arbre Git :** Propre (Working tree clean sur les fichiers suivis)  
**Mode d'intervention :** STRICTEMENT LECTURE SEULE (Aucune modification de code ni de base de production)

---

## 1. RÉSUMÉ EXÉCUTIF

Cet audit technique exhaustif a été conduit sur l'ensemble de la chaîne applicative de 9DILI EXPRESS (code source Dart/Flutter, configuration Android native, règles de sécurité Cloud Firestore, règles Realtime Database et pipeline CI/CD GitHub Actions).

L'investigation démontre formellement les causes racines de l'ensemble des anomalies rencontrées en production sur appareil physique Android :

1. **Justificatif de Caisse (`PERMISSION_DENIED`) :** Rupture de la machine d'état. L'action « Mode En Magasin » dans l'interface n'appelle jamais la méthode `startShopping()`. La course reste au statut `accepted` dans Firestore. Lorsque le shoppeur soumet le ticket, `firestore.rules` exige strictement `status == 'shopping'`, provoquant un rejet immédiat par le serveur. De plus, l'écran affiche un faux message de conformité local avant tout appel réseau.
2. **Google Sign-In (`PlatformException 10`) :** Discordance des empreintes OAuth. L'APK de release produit par GitHub Actions est signé avec le keystore `dili_express.keystore` dont l'empreinte SHA-1 (`61:1E:DB:C9...`) est totalement absente du fichier `google-services.json` et de la console Firebase/Google Cloud (seule l'empreinte de debug y figure).
3. **Trésorerie Shoppeur (5 000 DA vs Radar 0 DA & Fonds Insuffisants) :** La règle Firestore `firestore.rules` ligne 37 interdit formellement au client d'écrire dans le champ `availableCash`. La tentative de mise à jour depuis le profil échoue silencieusement en arrière-plan avec une exception non capturée, maintenant la base à 0 DA pendant que le champ texte local conserve artificiellement 5 000 DA.
4. **Échange Téléphonique (Numéro non renseigné) :** Rupture de liaison de données. Le constructeur de course n'injecte ni `clientPhone` ni `shopperPhone` dans `ErrandModel`. La boîte de dialogue tente de lire ces champs nuls sans jamais interroger le document profil `/users/{uid}`.
5. **Faille Critique Code PIN / Handshake :** Le code PIN de remise est stocké en clair dans le document principal de la course accessible en lecture à n'importe quel utilisateur authentifié, et la clôture de la course par le shoppeur n'est pas vérifiée côté serveur par les règles Firestore.

---

## 2. TABLEAU DE SYNTHÈSE DES ANOMALIES

| Identifiant | Domaine | Sévérité | Statut | Cause Racine Résumée |
| :--- | :--- | :--- | :--- | :--- |
| **ANOM-01** | Firestore / Caisse | **P0 - Bloquant** | `CONFIRMÉ` | `startShopping()` non appelé ; status reste `accepted` au lieu de `shopping` ; rejet par `firestore.rules:76-78`. Fausse confirmation UI locale. |
| **ANOM-02** | Authentification Google | **P0 - Bloquant** | `CONFIRMÉ` | SHA-1 du keystore de Release absent de `google-services.json` et de la console Cloud (CommonStatusCodes.DEVELOPER_ERROR 10). |
| **ANOM-03** | Trésorerie Shopper | **P0 - Bloquant** | `CONFIRMÉ` | `firestore.rules:37` bloque l'écriture de `availableCash`. Profil affiche la valeur locale du TextEditingController, Firestore reste à 0 DA. |
| **ANOM-04** | Échange Téléphonique | **P1 - Majeur** | `CONFIRMÉ` | `clientPhone` et `shopperPhone` non persistés dans `ErrandModel` ni `ErrandBidModel` ; dialogue n'interroge pas `UserService`. |
| **ANOM-05** | Sécurité Code PIN | **P1 - Sécurité** | `CONFIRMÉ` | `securePin` exposé en clair dans `/errands/{id}` (lecture publique authentifiée) ; clôture Firestore non conditionnée au PIN serveur. |
| **ANOM-06** | Mode En Magasin | **P2 - Mineur** | `CONFIRMÉ` | Bouton « Passer au Ticket » cliquable même si des articles ne sont pas traités ; absence de `PopScope` pour sécuriser le bouton retour. |
| **ANOM-07** | Pipeline CI / Build APK | **P2 - Qualité** | `CONFIRMÉ` | Workflow GitHub Actions fonctionnel mais dépendant du secret `ANDROID_KEYSTORE_BASE64` avec keystore release unique. |

---

## 3. PHASE 0 — IDENTIFICATION ET CONTRÔLE DE L'ENVIRONNEMENT

### 3.1 Dépôt et Arborescence
- **Répertoire de travail :** `/root/dili_express`
- **Dépôt distant :** `https://github.com/frechfanta-os/9DILI-EXPRESS.git`
- **Branche :** `main` (commit `f50327fcae79d383a266d1efd17623e54f8b3eef`)
- **Package Android :** `com.ghdinteractivestudio.dili_express` (conforme aux directives d'organisation)
- **Fichiers de configuration Firebase détectés :**
  - `firestore.rules` (172 lignes)
  - `database.rules.json` (47 lignes)
  - `android/app/google-services.json` (78 lignes)
  - `lib/firebase_options.dart` (75 lignes)

### 3.2 Contrôle Matériel et CI/CD
- **Périphérique physique de test :** Smartphone Android `PLE110` connecté via ADB sur `192.168.1.11:34401`.
- **Dernier build CI GitHub Actions validé :** Run `#39019932378` ayant compilé `app-release.apk` (Empreinte SHA-256 : `b82d2e2e0d01217619dc7d1ef55b2392948c8fd572d97ae19bfdca0aa3441636`).
- **Tests unitaires et analyse statique :**
  - `flutter analyze` : 0 avertissement, 0 erreur.
  - `flutter test` : 78/78 tests passés avec succès.

---

## 4. PHASE 1 — AUDIT DU JUSTIFICATIF DE CAISSE (PERMISSION_DENIED)

### 4.1 Symptôme Observé
Sur l'écran « Justificatif de Caisse », un message vert « Justificatif conforme » s'affiche, puis la validation échoue avec l'erreur :
`[cloud_firestore/permission-denied] PERMISSION_DENIED: Missing or insufficient permissions.`

### 4.2 Reconstitution de l'Ordre des Opérations
1. **Écran `ReceiptScreen` (`lib/ui/screens/receipt_screen.dart`) :**
   - Lignes 72-76 : La variable `_isValidated` est calculée par une fonction synchrone purement locale :
     ```dart
     bool get _isValidated => _ticketAmount > 0 && _ticketRefController.text.trim().length >= 3;
     ```
   - Lignes 174-175 : Dès que le montant est > 0 et que la référence fait au moins 3 caractères, le conteneur vert *"Justificatif conforme. Vous pouvez partir en livraison."* est rendu dans l'arbre des widgets **AVANT** que le shoppeur ne clique sur « Confirmer le Justificatif » et avant toute requête réseau vers Firebase.
2. **Navigation depuis `HomeScreen` (`lib/ui/screens/home_screen.dart`) :**
   - Lignes 1080-1089 :
     ```dart
     onPressed: () {
       Navigator.of(context).push(
         MaterialPageRoute(
           builder: (_) => ShoppingModeScreen(
             errand: activeErrand,
             errandService: widget.errandService,
           ),
         ),
       );
     }
     ```
   - Le bouton « Mode En Magasin » navigue directement vers `ShoppingModeScreen` sans exécuter `widget.errandService.startShopping(activeErrand.errandId)`.
3. **Statut Firestore de la course :**
   - Dans `errand_service.dart:295-297`, la fonction `startShopping(errandId)` existe mais n'est **appelée nulle part dans l'ensemble de l'interface utilisateur**.
   - Par conséquent, la course demeure dans Firestore avec le statut `status: 'accepted'`.
4. **Soumission du Ticket (`lib/services/errand_service.dart`) :**
   - Dans `submitTicket()` (lignes 231-263), l'application met à jour le document :
     ```dart
     await _errandsRef.doc(errandId).update({
       'ticketAmount': amount,
       'ticketRef': ticketRef,
       'updatedAt': FieldValue.serverTimestamp(),
     });
     ```
5. **Règles de Sécurité Firestore (`firestore.rules`) :**
   - Lignes 75-78 :
     ```firestore
     // Enregistrement du justificatif de caisse en magasin (Spark sans Storage)
     (request.resource.data.status == 'shopping' &&
      resource.data.status == 'shopping' &&
      request.resource.data.diff(resource.data).affectedKeys().hasOnly(['ticketAmount', 'ticketRef', 'ticketPhotoUrl', 'updatedAt']))
     ```
   - Le moteur de sécurité exige formellement `resource.data.status == 'shopping'`. Or la donnée distante vaut `resource.data.status == 'accepted'`.
   - **Verdict serveur :** Rejet immédiat avec `PERMISSION_DENIED`.

### 4.3 Classification
- **Statut :** `CONFIRMÉ`
- **Fichiers impliqués :**
  - [receipt_screen.dart](file:///root/dili_express/lib/ui/screens/receipt_screen.dart#L72-L76) (illusion de succès local)
  - [home_screen.dart](file:///root/dili_express/lib/ui/screens/home_screen.dart#L1080-L1089) (omission de l'appel de transition)
  - [errand_service.dart](file:///root/dili_express/lib/services/errand_service.dart#L295-L297) (`startShopping` orphelin)
  - [firestore.rules](file:///root/dili_express/firestore.rules#L75-L78) (règle stricte et légitime)

---

## 5. PHASE 2 — AUDIT DE GOOGLE SIGN-IN (CODE 10 DEVELOPER_ERROR)

### 5.1 Symptôme Observé
Lors de la tentative de connexion via Google sur l'APK Release, l'exception suivante est levée :
`PlatformException(sign_in_failed, z3: 10: , null, null)`

### 5.2 Analyse Forensique des Empreintes Cryptographiques
L'erreur 10 dans le SDK Google Play Services correspond à la constante `CommonStatusCodes.DEVELOPER_ERROR`, indiquant qu'aucun client OAuth 2.0 Android correspondant à l'application émettrice n'est enregistré dans Google Cloud Console.

1. **Inspection du Keystore Release (`android/app/dili_express.keystore`) :**
   - Alias : `dili_express`
   - Empreinte SHA-1 : `61:1E:DB:C9:D9:9A:B9:98:D3:10:30:C5:87:AF:4F:07:91:2C:66:F2`
   - Empreinte SHA-256 : `2A:FF:4A:59:36:34:0C:90:26:CF:89:BA:F9:4E:19:0D:1C:A1:E6:9D:23:DF:96:F3:B6:7C:CE:FC:65:B6:C0:88`
2. **Inspection de `android/app/google-services.json` (lignes 17-29) :**
   ```json
   "oauth_client": [
     {
       "client_id": "273784230349-npk0ahc1ql1tsgvlioa3c2gdk3r2hlfj.apps.googleusercontent.com",
       "client_type": 1,
       "android_info": {
         "package_name": "com.ghdinteractivestudio.dili_express",
         "certificate_hash": "7df2a743f43a603ac1e1ddb82681fec50959fa20"
       }
     }
   ]
   ```
3. **Preuve du Conflit :**
   - Le certificat `7df2a743...` présent dans `google-services.json` correspond exclusivement au `debug.keystore` local (`/root/.android/debug.keystore`).
   - L'empreinte du certificat officiel de production `61:1E:DB:C9...` **n'est pas enregistrée dans la console Firebase / Google Cloud**.
   - Par conséquent, l'APK de release compilé par GitHub Actions est systématiquement refoulé par les serveurs d'authentification Google avec le code `10`.

### 5.3 Classification
- **Statut :** `CONFIRMÉ`
- **Action requise :** Ajouter le SHA-1 `61:1E:DB:C9:D9:9A:B9:98:D3:10:30:C5:87:AF:4F:07:91:2C:66:F2` et le SHA-256 dans les paramètres du projet Firebase Console (Paramètres du projet > Vos applications > Empreintes de certificat SHA), puis retélécharger le `google-services.json` mis à jour.

---

## 6. PHASE 3 — AUDIT DE LA TRÉSORERIE DU SHOPPEUR

### 6.1 Symptômes Observés
- Le profil affiche une trésorerie en poche de 5 000 DA.
- Le bandeau radar principal affiche `En poche : 0 DA`.
- Une course nécessitant 2 500 DA d'avance affiche le badge `Fonds insuffisants ⚠️`.

### 6.2 Preuve dans le Code et les Règles de Sécurité
1. **Règles Firestore sur la collection `/users/{userId}` (`firestore.rules` lignes 33-38) :**
   ```firestore
   allow update: if isOwner(userId) &&
     request.resource.data.role == resource.data.role &&
     request.resource.data.availableCash == resource.data.availableCash;
   ```
   La condition `request.resource.data.availableCash == resource.data.availableCash` stipule expressément que **le client mobile n'a pas le droit de modifier sa propre trésorerie**.
2. **Écran Profil (`lib/ui/screens/profile_screen.dart` lignes 73-77) :**
   ```dart
   if (cashParsed != currentUserModel.availableCash) {
     await widget.userService.setAvailableCash(currentUserModel.uid, cashParsed);
   }
   ```
   Lors de la sauvegarde du profil avec 5 000 DA, `UserService.setAvailableCash()` envoie l'écriture à Firestore.
3. **Comportement Réseau et UI :**
   - L'écriture est rejetée par Firestore avec `[cloud_firestore/permission-denied]`.
   - L'exception n'est pas remontée à l'utilisateur de manière explicite.
   - Le `TextEditingController` de l'écran Profil conserve la valeur locale saisie (`5000`), donnant l'illusion que le profil est à jour.
   - En base de données, `availableCash` reste figé à `0.0`.
4. **Écran d'Accueil (`HomeScreen`) :**
   - Le bandeau radar écoute le flux Firestore distant en temps réel : il reçoit `0.0 DA` et affiche `En poche : 0 DA`.
   - L'évaluation de la condition d'éligibilité (ligne 1204) :
     ```dart
     final hasEnoughCash = shopper.availableCash >= errand.treasuryRequired; // 0.0 >= 2500.0 => FALSE
     ```
   - La condition échoue et l'interface affiche légitimement `Fonds insuffisants ⚠️`.

### 6.3 Tableau des Champs de Trésorerie

| Entité | Champ / Variable | Emplacement Code | Source de Vérité | Rôle Métier |
| :--- | :--- | :--- | :--- | :--- |
| `UserModel` | `availableCash` | `lib/models/user_model.dart:21` | Firestore `/users/{uid}` | Montant réel en dinars dont dispose le shoppeur pour faire l'avance en caisse |
| `ProfileScreen` | `_cashController.text` | `lib/ui/screens/profile_screen.dart:33` | État local éphémère | Saisie utilisateur dans le formulaire du profil |
| `HomeScreen` | `shopper.availableCash` | `lib/ui/screens/home_screen.dart:991` | Stream Firestore réactif | Affichage du solde en poche sur le radar |
| `ErrandModel` | `treasuryRequired` | `lib/models/errand_model.dart:88` | Calcul (`estimatedBudget`) | Montant minimum exigé du shoppeur pour accepter la course |

### 6.4 Classification
- **Statut :** `CONFIRMÉ`
- **Fichiers impliqués :**
  - [firestore.rules](file:///root/dili_express/firestore.rules#L37) (verrouillage strict côté serveur)
  - [profile_screen.dart](file:///root/dili_express/lib/ui/screens/profile_screen.dart#L73-L77) (tentative d'écriture non autorisée)
  - [user_service.dart](file:///root/dili_express/lib/services/user_service.dart#L46-L51) (`setAvailableCash` bloqué par les règles)

---

## 7. PHASE 4 — AUDIT DU NUMÉRO DE TÉLÉPHONE DANS L'ÉCHANGE TÉLÉPHONIQUE

### 7.1 Symptôme Observé
Bien qu'un numéro de téléphone soit renseigné dans le profil, l'ouverture de la boîte de dialogue « Échange Téléphonique » indique :
*"Numéro de téléphone non renseigné sur le profil."*

### 7.2 Analyse du Flux de Données
1. **Création de la Course (`HomeScreen._openCreateListDialog`, lignes 166-176) :**
   ```dart
   final newErrand = ErrandModel(
     errandId: '',
     clientId: clientId,
     storeName: storeCtrl.text.trim(),
     deliveryAddress: addressCtrl.text.trim(),
     estimatedBudget: budget,
     securePin: generatedPin,
     storeDistanceKm: 1.8,
     etaMinutes: 20,
     status: ErrandStatus.pending,
   );
   ```
   Les paramètres `clientPhone` et `shopperPhone` ne sont **pas renseignés** lors de l'instanciation de la course. Ils prennent donc la valeur par défaut `null`.
2. **Soumission et Acceptation des Offres :**
   - Le modèle `ErrandBidModel` (`lib/models/errand_bid_model.dart`) ne contient aucun champ pour le numéro de téléphone du shoppeur.
   - Lors de l'acceptation de l'offre dans `ErrandService.acceptBid` (lignes 464-470), les numéros de téléphone ne sont jamais copiés dans le document `errand`.
3. **Déclenchement du Dialogue `_makeMandatoryCall` :**
   - Ligne 494 (Client appelant le Shoppeur depuis la feuille des offres) :
     `_makeMandatoryCall(errand, bid.shopperName, errand.shopperPhone)` -> `errand.shopperPhone` vaut `null`.
   - Ligne 891 (Client appelant le Shoppeur assigné) :
     `_makeMandatoryCall(errand, 'Shoppeur', errand.shopperPhone)` -> `errand.shopperPhone` vaut `null`.
   - Ligne 1308 (Shoppeur appelant le Client depuis le radar) :
     `_makeMandatoryCall(errand, 'Client', errand.clientPhone)` -> `errand.clientPhone` vaut `null`.
4. **Rendu dans le Dialogue (`HomeScreen`, lignes 337-347) :**
   Le code teste `phone != null && phone.isNotEmpty`. Comme `phone` est toujours `null`, la branche d'affichage retombe sur l'erreur rouge :
   ```dart
   phone != null && phone.isNotEmpty
       ? 'Numéro : $phone'
       : 'Numéro de téléphone non renseigné sur le profil.'
   ```
5. **Faille Métier Supplémentaire :**
   Bien que le numéro soit manquant, le bouton « J'atteste l'appel » (ligne 363) reste actif et permet de valider un appel qui n'a jamais pu être passé.

### 7.3 Classification
- **Statut :** `CONFIRMÉ`
- **Fichiers impliqués :**
  - [home_screen.dart](file:///root/dili_express/lib/ui/screens/home_screen.dart#L166-L176) (omission du téléphone à la création)
  - [errand_bid_model.dart](file:///root/dili_express/lib/models/errand_bid_model.dart#L13-L32) (absence de champ de téléphone)
  - [home_screen.dart](file:///root/dili_express/lib/ui/screens/home_screen.dart#L337-L347) (consommation directe de valeurs nulles sans requête `UserService`)

---

## 8. PHASE 5 — AUDIT DU MODE EN MAGASIN (SHOPPING MODE)

### 8.1 Parcours et Persistance des Articles
- **Gestion des statuts :** `ShoppingModeScreen` permet de marquer chaque article parmi 3 statuts : `Trouvé` (vert), `Remplacé` (orange avec note textuelle) ou `Rupture` (rouge).
- **Persistance Firestore :** Chaque pression déclenche `widget.errandService.updateItem(widget.errand.errandId, updatedItem)`. La mise à jour est immédiatement écrite dans la sous-collection `/errands/{errandId}/items/{itemId}`.
- **Règles Firestore sur les articles (`firestore.rules` lignes 126-135) :**
  ```firestore
  match /items/{itemId} {
    allow read: if isAuthenticated();
    allow create, update: if isAuthenticated() && (
      getErrand(errandId).clientId == request.auth.uid ||
      getErrand(errandId).shopperId == request.auth.uid
    );
  }
  ```
  La mise à jour des articles par le shoppeur assigné est parfaitement autorisée dès lors que `shopperId` correspond à son UID.
- **Reprise après déconnexion ou fermeture de l'application :** Le stream `streamItems()` recharge correctement les articles depuis Firestore avec leurs statuts exacts.

### 8.2 Vulnérabilités et Anomalies Détectées
1. **Passage forcé en caisse sans traitement intégral :**
   - Ligne 122-124 : La variable `allProcessed` est calculée correctement :
     `final allProcessed = items.isNotEmpty && (foundCount + replacedCount + unavailableCount) == items.length;`
   - Ligne 365 : Malgré cela, `onPressed: _goToReceiptScreen` est **toujours lié et cliquable**. Seule la couleur du bouton change. Un shoppeur distrait peut donc basculer vers le ticket de caisse en ignorant une partie des articles.
2. **Absence de protection `PopScope` :**
   - L'écran ne dispose d'aucun `PopScope` / `WillPopScope`. Si le shoppeur presse le bouton retour physique Android, il quitte le magasin sans confirmation.
3. **Cas de rupture totale non géré :**
   - Si 100% des articles sont déclarés « Rupture », l'écran autorise tout de même le passage au ticket de caisse alors qu'aucun achat n'a été réalisé.

### 8.3 Classification
- **Statut :** `CONFIRMÉ`
- **Fichiers impliqués :**
  - [shopping_mode_screen.dart](file:///root/dili_express/lib/ui/screens/shopping_mode_screen.dart#L358-L375) (bouton de caisse non bloquant)

---

## 9. PHASE 6 — AUDIT DE LA LIVRAISON ET DU CODE PIN (HANDSHAKE)

### 9.1 Mécanisme du Code PIN
- À la création de la course, un code PIN aléatoire à 4 chiffres est généré (`ErrandService.generateCryptographicPin` ou `HomeScreen._generateSecurePin`).
- Ce PIN est sauvegardé directement dans le document principal de la course :
  `/errands/{errandId}` -> champ `securePin: "4821"`.
- Côté Client (`DeliveryTrackingScreen` lignes 223-228), le PIN est affiché en grand et encodé dans un QR code sous la forme `9DILI_DELIVERY:{errandId}:{securePin}`.
- Côté Shoppeur (`DeliveryTrackingScreen` lignes 334-338), la méthode `ErrandService.completeErrandWithPin(errandId, inputPin)` compare la saisie avec le PIN mémorisé.

### 9.2 Faille de Sécurité Critique Découverte
1. **Fuite du Secret en Lecture Publique :**
   - Dans `firestore.rules` (lignes 46-47) :
     ```firestore
     match /errands/{errandId} {
       allow read: if isAuthenticated();
     ```
   - N'importe quel utilisateur connecté (y compris le shoppeur) peut lire l'intégralité du document `/errands/{errandId}`, qui contient `securePin` en clair !
   - Le shoppeur a donc accès au PIN secret avant même de rencontrer le client.
2. **Absence de Vérification Côté Serveur :**
   - Dans `firestore.rules` (lignes 87-88) :
     ```firestore
     // Clôture après validation de livraison
     (request.resource.data.status == 'completed' &&
      resource.data.status == 'delivering')
     ```
   - La règle Firestore autorise la transition vers `completed` **sans aucune vérification du code PIN**.
   - Le contrôle anti-brute force et la validation du PIN sont exécutés exclusivement côté client dans le code Dart du shoppeur (`errand.securePin.trim() == cleanInput`).
   - Un client malveillant ou une requête HTTP directe peut clôturer la course sans connaître le PIN.
3. **Règles Orphelines Non Utilisées :**
   - Dans `firestore.rules` (lignes 98-121), des règles très sécurisées avaient été prévues sur `/secrets/pin` et `/verification/delivery_pin`.
   - Cependant, le code Flutter n'écrit ni ne lit **jamais** dans ces sous-collections.

### 9.3 Classification
- **Statut :** `CONFIRMÉ`
- **Fichiers impliqués :**
  - [errand_model.dart](file:///root/dili_express/lib/models/errand_model.dart#L184,L235) (`securePin` exposé dans le corps principal)
  - [errand_service.dart](file:///root/dili_express/lib/services/errand_service.dart#L128-L137,L343-L359) (contrôle purement client-side)
  - [firestore.rules](file:///root/dili_express/firestore.rules#L87-L88,L98-L121) (clôture permissive et sous-collections orphelines)

---

## 10. PHASE 7 — AUDIT DU RADAR ET DU SUIVI TEMPS RÉEL (REALTIME DATABASE)

### 10.1 Architecture et Cohérence
- **Service :** `RealtimeTrackingService` (`lib/services/realtime_tracking_service.dart`).
- **Endpoint configuré :** `https://dili-express-default-rtdb.europe-west1.firebasedatabase.app` (confirmé dans `google-services.json` et `firebase_options.dart`).
- **Gestion de présence :** Utilisation correcte de `.onDisconnect()` sur `/presence/{uid}` pour basculer automatiquement les shoppeurs hors ligne en cas de perte de connectivité réseau.
- **Règles RTDB (`database.rules.json`) :**
  - Les nœuds `presence`, `locations`, `shopper_locations` et `active_errands` disposent de contrôles stricts validant la structure des données (présence obligatoire de `latitude`, `longitude`, bornes géographiques -90 à +90 et -180 à +180).
  - Les tentatives d'injection de champs non autorisés (`role`, `availableCash`, `rating`, `admin`, `balance`) sont explicitement bloquées par les clauses `.validate`.

### 10.2 Respect des Quotas Firebase Spark
- **Throttling GPS :** Intervalle minimum de 8 secondes (`minWriteInterval = Duration(seconds: 8)`) codé en dur dans `updateShopperLocation` et `pushActiveErrandLocation`.
- **Nettoyage automatique :** Méthode `cleanUpActiveErrand(errandId)` appelée à la fin de la livraison pour supprimer les données de localisation éphémères du nœud `active_errands`.
- **Points de vigilance Spark :** La limite de 100 connexions simultanées en WebSocket sur Realtime Database imposera une bascule sur le plan Blaze lors de la montée en charge commerciale.

### 10.3 Classification
- **Statut :** `CONFIRMÉ` (Comportement conforme aux contraintes d'architecture Spark)
- **Fichiers impliqués :**
  - [realtime_tracking_service.dart](file:///root/dili_express/lib/services/realtime_tracking_service.dart)
  - [database.rules.json](file:///root/dili_express/database.rules.json)

---

## 11. PHASE 8 — MATRICE DE SÉCURITÉ ET CONTRAINTES D'ARCHITECTURE

```
+---------------------------------------------------------------------------------------------------+
|                        MATRICE DE SÉCURITÉ & COHÉRENCE MULTI-COUCHES                              |
+------------------------------+---------------------------+-----------------------+----------------+
| Ressource / Opération        | Implémentation Client     | Règle Serveur Active  | Statut Cohérence|
+------------------------------+---------------------------+-----------------------+----------------+
| Profil : Modifier Trésorerie | UserService.setAvailableCash| Bloqué (rules:37)     | INCOHÉRENT (P0)|
| Course : Prise en Magasin    | Non appelé dans l'UI      | Requis (rules:73)     | INCOHÉRENT (P0)|
| Course : Justificatif Caisse | submitTicket()            | Requis status shopping| BLOQUÉ (P0)    |
| Course : Validation PIN      | errand.securePin client   | Clôture sans PIN (87) | VULNÉRABLE (P1)|
| Auth : Google Sign-In        | GoogleAuthProvider        | SHA-1 Release Manquant| REJETÉ (P0)    |
| Auth : Numéro Téléphone      | Dialog Échange Appel      | Champs nuls en base   | INCOMPLET (P1) |
| RTDB : Position GPS          | pushActiveErrandLocation  | Validé (règles strict)| CONFORME       |
| RTDB : Présence Shoppeur     | setUserPresence           | Validé (onDisconnect) | CONFORME       |
+------------------------------+---------------------------+-----------------------+----------------+
```

---

## 12. PHASE 9 — PLAN D'ACTIONS HIÉRARCHISÉ ET REMÉDIATION TECHNIQUE

### Priorité P0 — Corrections Immédiates (Bloquants de Production)

#### Action P0.1 : Résolution de l'erreur Google Sign-In 10
- **Type :** Configuration Cloud & Déploiement
- **Actions :**
  1. Accéder à la console Firebase du projet `dili-express`.
  2. Ajouter le certificat SHA-1 de Release : `61:1E:DB:C9:D9:9A:B9:98:D3:10:30:C5:87:AF:4F:07:91:2C:66:F2`.
  3. Ajouter l'empreinte SHA-256 de Release : `2A:FF:4A:59:36:34:0C:90:26:CF:89:BA:F9:4E:19:0D:1C:A1:E6:9D:23:DF:96:F3:B6:7C:CE:FC:65:B6:C0:88`.
  4. Télécharger le nouveau `google-services.json` et le placer dans `android/app/google-services.json`.

#### Action P0.2 : Correction de la machine d'état « Mode En Magasin » et Justificatif
- **Type :** Code Flutter & Gestion d'état
- **Actions :**
  1. Dans `HomeScreen` (`lib/ui/screens/home_screen.dart`), lors du clic sur « Mode En Magasin », appeler explicitement :
     ```dart
     await widget.errandService.startShopping(activeErrand.errandId);
     ```
  2. Dans `ReceiptScreen` (`lib/ui/screens/receipt_screen.dart`), supprimer l'illusion de conformité locale immédiate et n'afficher le message de succès qu'après la confirmation de l'écriture Firestore.

#### Action P0.3 : Rétablissement de la gestion de trésorerie shoppeur
- **Type :** Règles Firestore & Service Utilisateur
- **Actions :**
  1. Mettre à jour `firestore.rules` sur `/users/{userId}` pour autoriser l'auto-déclaration de la trésorerie disponible en poche par le shoppeur propriétaire :
     ```firestore
     allow update: if isOwner(userId) &&
       request.resource.data.role == resource.data.role &&
       request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isOnline', 'availableCash', 'location', 'transportType', 'searchRadiusKm', 'updatedAt']);
     ```
  2. Gérer explicitement les exceptions dans `ProfileScreen` avec un `SnackBar` d'erreur si l'écriture échoue.

---

### Priorité P1 — Sécurité & Intégrité Métier

#### Action P1.1 : Sécurisation du Code PIN de Remise
- **Type :** Architecture Sécurité & Code Flutter
- **Actions :**
  1. Ne plus enregistrer `securePin` dans le document principal `/errands/{errandId}`.
  2. Activer la sous-collection `/errands/{errandId}/secrets/pin` réservée exclusivement au client créateur.
  3. Pour la validation shoppeur, utiliser la sous-collection `/errands/{errandId}/verification/delivery_pin` qui valide l'égalité du code PIN directement dans le moteur de règles Firestore sans divulguer le secret.

#### Action P1.2 : Injection des numéros de téléphone dans l'échange préalable
- **Type :** Modèles de Données & UI
- **Actions :**
  1. Lors de la création de la course dans `HomeScreen`, injecter le numéro de téléphone de l'utilisateur connecté dans `clientPhone`.
  2. Dans `ErrandBidModel`, ajouter le champ `shopperPhone` alimenté depuis le profil du shoppeur soumettant l'offre.
  3. Lors de l'acceptation de l'offre dans `ErrandService.acceptBid`, enregistrer de manière atomique `shopperPhone` sur le document de la course.
  4. Dans la boîte de dialogue d'échange téléphonique, désactiver le bouton « J'atteste l'appel » si aucun numéro valide n'est disponible.

---

### Priorité P2 — Durcissement UX & Contrôles Magasin

#### Action P2.1 : Verrouillage du passage en caisse
- **Type :** UI / Logique Magasin
- **Actions :**
  1. Désactiver (`onPressed: null`) le bouton « Passer au Ticket de Caisse » dans `ShoppingModeScreen` tant que `allProcessed` est faux.
  2. Ajouter un dialogue de confirmation si 100% des articles sont marqués « Rupture » pour proposer l'annulation sans frais de la course.
  3. Envelopper `ShoppingModeScreen` dans un `PopScope` pour demander confirmation avant de quitter la session de courses en cours.

---

## 13. PROCÉDURES DE TEST DE NON-RÉGRESSION RECOMMANDÉES

1. **Test d'Authentification Google Release :**
   - Installer l'APK Release signé (`app-release.apk`) sur le smartphone physique `PLE110`.
   - Tester le flux complet de connexion Google d'un compte utilisateur réel sans erreur `10`.
2. **Test Cycle de Vie Complet d'une Course :**
   - Créer une course en tant que Client -> Vérifier la présence de `clientPhone` et la génération du code PIN secret.
   - Soumettre une offre en tant que Shoppeur -> Ouvrir l'échange téléphonique et vérifier l'affichage immédiat du numéro de téléphone réel.
   - Attester l'appel et accepter l'offre -> Vérifier le passage au statut `accepted`.
   - Cliquer sur « Mode En Magasin » -> Vérifier dans Firebase Console que le statut passe immédiatement à `shopping`.
   - Cocher les articles (Trouvé / Remplacé / Rupture) -> Vérifier la mise à jour en temps réel des documents `/items`.
   - Passer au ticket de caisse -> Saisir le montant réel et la référence -> Valider -> Confirmer l'absence d'erreur `PERMISSION_DENIED`.
   - Démarrer la livraison -> Activer le suivi GPS en direct -> Vérifier la remontée des coordonnées dans `/active_errands`.
   - Saisir le code PIN client côté Shoppeur -> Valider la remise -> Vérifier la clôture au statut `completed`.

---

## 14. ENGAGEMENT DE CONFORMITÉ DIRECTIVES ANTIGRAVITY

- [x] **Aucun secret exposé :** Les clés privées et secrets CI sont préservés.
- [x] **Identifiant de package respecté :** `com.ghdinteractivestudio.dili_express` appliqué sur l'ensemble de la chaîne.
- [x] **Code source préservé :** Aucun fichier source modifié pendant l'audit.
- [x] **Base de données de production préservée :** Aucune écriture de test n'a été injectée en production.
- [x] **Arrêt et attente d'autorisation :** Aucune correction ne sera appliquée sans validation formelle préalable de l'utilisateur.
