# AUDIT DE LA CONFIGURATION FIREBASE — 9DILI EXPRESS

**Projet Firebase** : `dili-express`  
**Numéro de Projet Réel** : `273784230349`  
**Compte Administrateur Connecté** : `ghdinteractivestudio@gmail.com`  
**Date d'audit** : 16 Octobre 2026  
**Auditeur** : Équipe Senior Firebase & Architecture Cloud  
**Statut Global** : **AUDIT PHASE B TERMINÉ — BLOQUANTS DE DÉPLOIEMENT IDENTIFIÉS**

---

## 1. Identification du Projet Réel & Décalages Détectés (Phase B1)

Grâce à l'authentification CLI réussie sur le compte propriétaire `ghdinteractivestudio@gmail.com`, l'inspection directe des métadonnées du projet Firebase `dili-express` a permis d'extraire la configuration officielle en direct.

### 1.1 Tableau Comparatif des Configurations (Local vs Console Live)

| Paramètre | Fichier Local `google-services.json` | Fichier Local `firebase_options.dart` | Configuration Live Firebase Console (`apps:sdkconfig`) | Analyse de Cohérence |
| :--- | :--- | :--- | :--- | :--- |
| **Project ID** | `dili-express` | `dili-express` | `dili-express` | **CONFORME** |
| **Project Number** | `100000000000` *(Factice/Template)* | `100000000000` *(Factice)* | **`273784230349`** *(Officiel)* | **ÉCART CRITIQUE LOCAL** |
| **Android App ID** | `1:100000000000:android:com_...` | `1:100000000000:android:com_...` | **`1:273784230349:android:35bbc811e38deeb1973484`** | **ÉCART CRITIQUE LOCAL** |
| **Package Name Android** | `com.ghdinteractivestudio.dili_express` | (non spécifié) | **`com.ghdinteractivestudio.diliexpress`** *(Sans underscore)* | **DIVERGENCE BLOQUANTE** |
| **Application ID Gradle** | `com.ghdinteractivestudio.dili_express` | - | `com.ghdinteractivestudio.diliexpress` | **INCOMPATIBLE GOOGLE SIGN-IN** |
| **Client OAuth Android (Type 1)** | Présent (Hash `7df2a...`) | - | **ABSENT** *(Aucun client OAuth Android configuré en ligne)* | **GOOGLE SIGN-IN NON FONCTIONNEL** |
| **Client OAuth Web (Type 3)** | Absent | - | `273784230349-0lr2crsalpk51apeetf96fhthl4ap6k1...` | **DISPONIBLE POUR LE WEB** |
| **Clé API (API Key)** | `AIzaSyCUbk_KE1NJ2QMeGhUvg882EMgFrXB6Qi0` | `AIzaSyCUbk_KE1NJ2QMeGhUvg882EMgFrXB6Qi0` | `AIzaSyCUbk_KE1NJ2QMeGhUvg882EMgFrXB6Qi0` | **VALIDE & HARMONISÉE** |
| **Storage Bucket** | `dili-express.firebasestorage.app` | `dili-express.firebasestorage.app` | `dili-express.firebasestorage.app` | **CONFORME** |
| **Fichier `.firebaserc`** | **ABSENT** | - | - | **À CRÉER** |

> [!WARNING]
> ### ANOMALIE MAJEURE N°1 : Divergence du nom de package (`package_name`)
> - Dans le code local Flutter (`build.gradle.kts`, `AndroidManifest.xml`) : `com.ghdinteractivestudio.dili_express` (avec trait de soulignement `_`).
> - Dans la console Firebase enregistrée : `com.ghdinteractivestudio.diliexpress` (sans trait de soulignement).
> - **Conséquence directe** : Firebase Auth (Google Sign-In) et App Check rejettent catégoriquement toute requête venant d'un package dont l'identifiant ne correspond pas exactement au certificat OAuth enregistré.

> [!WARNING]
> ### ANOMALIE MAJEURE N°2 : Fichiers locaux obsolètes/factices
> Le fichier `google-services.json` et `firebase_options.dart` dans le projet local utilisaient des identifiants temporaires (`project_number: 100000000000`). Ils doivent être mis à jour avec la configuration officielle téléchargée depuis le serveur Firebase (`273784230349`).

---

## 2. Matrice d'Audit des Services Firebase (Phase B2)

Conformément aux exigences de rigueur, chaque service est classé selon les 5 états d'existence :

| Service Firebase | 1. Déclaré dans le code Dart | 2. Configuré localement | 3. Activé dans Firebase Console | 4. Ressource créée en production | 5. Test de communication réussi | Statut Global |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Firebase Auth (Email/Password)** | OUI (`AuthService`) | OUI (`firebase_options.dart`) | OUI (Projet actif) | OUI | **BLOCKED** *(En attente alignement package)* | **BLOCKED** |
| **Firebase Auth (Google Sign-In)** | OUI (`AuthService`) | OUI (`google_sign_in: ^6.2.2`) | **INCOMPLET** (Manque SHA-1 & bon package) | NON (Client OAuth Type 1 absent) | FAIL *(Erreur 10 garantie)* | **FAIL** |
| **Cloud Firestore** | OUI (`UserService`, `ErrandService`) | OUI (`firestore.rules`) | OUI (Projet actif) | OUI (Base provisionnée, 0 index composite) | PASS *(Mocks unitaires validés)* | **PASS** *(Local)* / **BLOCKED** *(Prod)* |
| **Firebase Storage** | OUI (`ErrandModel.ticketPhotoUrl`) | OUI (`storage.rules`) | OUI (`dili-express.firebasestorage.app`) | OUI (Bucket prêt) | NON (Pas de code d'upload `putFile` écrit) | **NOT IMPLEMENTED** *(Dart)* |
| **Firebase App Check** | NON (Absent de `pubspec.yaml`) | NON | NON | NON | NON | **NOT IMPLEMENTED** |
| **Cloud Messaging (FCM)** | NON | NON | NON | NON | NON | **NOT IMPLEMENTED** |
| **Cloud Functions** | NON (Pas de dossier `functions/`) | NON | NON | NON | NON | **NOT IMPLEMENTED** |
| **Realtime Database** | NON (Aucun import `firebase_database`) | OUI (URL résiduelle template) | NON activé | NON | NON | **NOT USED** |

---

## 3. Évaluation du Modèle de Données Cible vs Existant (Phase B3)

### 3.1 Analyse Comparative des Collections

| Collection Cible Proposée | État Actuel dans le Code | Rôle & Nécessité Métier | Champs Clés & Relations | Action Recommandée |
| :--- | :---: | :--- | :--- | :--- |
| **`users`** | **PASS** (Implémenté) | Profils clients et shoppers, solde en poche, statut en ligne, note. | `uid`, `fullName`, `email`, `phone` *(facultatif)*, `role`, `isOnline`, `availableCash`, `rating`, `location`. | Conserver. Durcir les règles pour empêcher la modification de son propre rôle ou note. |
| **`errands`** | **PASS** (Implémenté) | Commandes de courses, budget, commission, adresses, étapes. | `errandId`, `clientId`, `shopperId`, `status`, `storeName`, `estimatedBudget`, `ticketAmount`, `negotiatedCommission`. | Déplacer le `securePin` hors du document principal pour éviter la fuite vers les tiers. |
| **`offers`** | **PASS** *(Sous-collection `/bids`)* | Propositions et contre-propositions de commission pour une course. | `bidId`, `shopperId`, `shopperName`, `shopperRating`, `proposedCommission`, `status` (`pending`, `accepted`, `rejected`). | Architecture actuelle en sous-collection `/errands/{id}/bids` optimale. |
| **`errand_events`** | **NOT IMPLEMENTED** | Journal d'audit immuable des transitions d'état et actions financières. | `eventId`, `errandId`, `timestamp`, `fromStatus`, `toStatus`, `performedBy`, `metadata`. | **PROPOSED** : Fortement recommandé pour la traçabilité des litiges et l'historique d'audit. |
| **`receipts`** | **NOT IMPLEMENTED** *(Inclus dans errand)* | Métadonnées détaillées du ticket de caisse (photo, articles détectés, TVA, magasin). | `receiptId`, `errandId`, `shopperId`, `photoUrl`, `ticketAmount`, `uploadedAt`, `validatedByClient`. | **PROPOSED** : Conserver pour l'instant dans `errands` pour la V1, extraire en collection dédiée en V2 si OCR. |
| **`deliveries`** | **NOT IMPLEMENTED** *(Inclus dans errand)* | Suivi logistique spécifique, étapes de prise en charge et de dépose. | `deliveryId`, `errandId`, `shopperId`, `startLocation`, `dropoffLocation`, `eta`, `completedAt`. | Maintenir dans `errands` pour éviter les lectures multiples et réduire les coûts Firebase. |
| **`ratings`** | **NOT IMPLEMENTED** | Évaluations immuables et avis après livraison terminée. | `ratingId`, `errandId`, `fromUserId`, `toUserId`, `score` (1-5), `comment`, `createdAt`. | **PROPOSED** : À implémenter en Phase Post-Livraison. |
| **`catalog_categories`** | **NOT IMPLEMENTED** | Catégories officielles de commerces et de produits en Algérie. | `categoryId`, `nameFr`, `nameAr`, `icon`, `sortOrder`, `isActive`. | **PROPOSED** : Indispensable pour la Phase E (Catalogue algérien). |
| **`catalog_products`** | **NOT IMPLEMENTED** | Produits référencés avec noms en arabe/français, unités, marques locales. | `productId`, `categoryId`, `nameFr`, `nameAr`, `brand`, `unit`, `indicativePrice`, `barcode`, `aliases`. | **PROPOSED** : À implémenter en Phase E. |
| **`shopper_presence`** | **NOT IMPLEMENTED** *(Dans users)* | Position GPS temporaire du livreur en service actif avec expiration TTL. | `shopperId`, `geohash`, `coordinates`, `lastSeen`, `transportType`, `isAvailable`. | **PROPOSED** : Isoler hors de `/users` pour des raisons de confidentialité et de fréquence de rafraîchissement. |
| **`app_config`** | **NOT IMPLEMENTED** | Paramètres globaux de l'application (version minimale requise, maintenance). | `minVersion`, `forceUpdate`, `commissionFloor`, `searchRadiusKm`. | **PROPOSED** : Très utile pour la maintenance sans republier d'APK. |

---

## 4. Procédure de Test de Communication Réelle (Phase B5)

Pour tester de façon infalsifiable la communication entre l'application et Firebase :

1. **Étape Préalable Obligatoire** : Aligner le package Android (`com.ghdinteractivestudio.diliexpress` ou modifier dans la console pour `com.ghdinteractivestudio.dili_express`) et injecter l'empreinte SHA-1 debug (`7D:F2:A7:43:F4:3A:60:3A:C1:E1:DD:B8:26:81:FE:C5:09:59:FA:20`).
2. **Initialisation** : Lancer l'application avec le `google-services.json` synchronisé.
3. **Création d'un compte de test** : Inscription d'un utilisateur temporaire `audit_qa_test@dili.dz`.
4. **Vérification Firestore** : Écriture du document de test dans `/users/test_qa_uid`.
5. **Observation en temps réel** : Contrôle de la notification de stream Flutter.
6. **Contrôle de sécurité négatif** : Tentative de modification illégitime du champ `role: 'admin'` (doit renvoyer `permission-denied`).
7. **Nettoyage automatique** : Suppression immédiate du document de test.

> **Statut actuel de la communication réelle** : **BLOCKED**  
> *Raison du blocage* : Le décalage du `package_name` et l'absence de l'empreinte SHA-1 dans Firebase Console empêchent l'obtention des jetons d'authentification Google et Firestore sur les terminaux réels.
