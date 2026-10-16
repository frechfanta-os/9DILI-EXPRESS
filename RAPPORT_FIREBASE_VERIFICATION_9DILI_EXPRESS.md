# 9DILI EXPRESS — RAPPORT DE VÉRIFICATION FIREBASE

**Projet Firebase Réel :** `dili-express`  
**Numéro de Projet :** `273784230349`  
**Date d'Inspection :** 16 Octobre 2026  
**Compte Développeur Authentifié :** `ghdinteractivestudio@gmail.com`  
**Application ID Android :** `com.ghdinteractivestudio.dili_express` (ID Firebase : `1:273784230349:android:1317b52fa41defee973484`)

---

## 1. État Réel des Applications Android Enregistrées sur le Projet

L'inspection de la configuration Firebase distante via Firebase CLI a permis d'éclaircir la divergence constatée lors de l'audit initial :

| Nom de l'App / Package | Firebase App ID | Date de Détection | Statut & Rôle |
| :--- | :--- | :---: | :--- |
| `com.ghdinteractivestudio.diliexpress` | `1:273784230349:android:12046cb8ae717df3973484` | Initial | Ancienne application déclarée sans underscore. |
| `com.ghdinteractivestudio.dili_express` | `1:273784230349:android:1317b52fa41defee973484` | 16/10/2026 | **Application officielle active** créée et liée au code Flutter. |

Le fichier `google-services.json` embarqué dans `/android/app/` intègre désormais les deux clients avec la référence active vers `com.ghdinteractivestudio.dili_express`.

---

## 2. État des Services Firebase

| Service | Statut Code | Statut Configuration Locale | Statut Console Distante | Preuve & Observations |
| :--- | :---: | :---: | :---: | :--- |
| **Firebase Auth** | Actif | Prêt (`EmailAuthProvider`, `GoogleAuthProvider`) | Prêt | Supporte la connexion par email et mot de passe. L'authentification Google nécessite l'enregistrement du SHA-1 dans la console. |
| **Cloud Firestore** | Actif | Règles locales durcies (`firestore.rules`) | Prêt | Schéma de sécurité validé en tests locaux. Déploiement des règles prêt via `firebase deploy --only firestore:rules`. |
| **Firebase Storage** | Actif | Règles locales durcies (`storage.rules`) | Prêt | Règles validées avec restriction MIME (`image/(jpeg|png|webp)`) et taille max de 10 Mo. |
| **Firebase App Check** | Actif | Prêt (`firebase_app_check: ^0.5.0`) | Configuration Console Requise | Implémenté avec `AndroidDebugProvider` (debug) et `AndroidPlayIntegrityProvider` (release). Debug Token à inscrire dans la console. |
| **Cloud Messaging (FCM)**| Réservé | Non requis en P0 | Prévu Roadmap | Le suivi en direct s'effectue via les `Stream` Firestore temps réel sans surcoût. |

---

## 3. Modèle de Données & Collections Cibles

| Collection / Sous-collection | Rôle & Usage | Règles d'Accès Appliquées |
| :--- | :--- | :--- |
| `/users/{uid}` | Profils utilisateurs (Client et Shopper). | Écriture réservée au propriétaire. Verrouillage strict de `role`, `availableCash` et `rating`. |
| `/errands/{errandId}` | Missions de courses principales. | Lecture authentifiée. Modification réservée au client ou au shopper assigné. |
| `/errands/{errandId}/items/{itemId}` | Liste des articles demandés avec état (pending, found, replaced, unavailable). | Création/modification par le client lors du brouillon, marquage des statuts par le shopper en magasin. |
| `/errands/{errandId}/offers/{offerId}` | Offres et contre-offres financières négociées. | Création par les shoppers intéressés. Statuts : `proposed`, `accepted`, `rejected`. |
| `/errands/{errandId}/secrets/pin` | **Sous-collection ultra-sécurisée** contenant le `deliveryPin`. | **Accès en lecture et écriture STRICTEMENT limité au client créateur.** Indétectable par les shoppers. |
| `/errands/{errandId}/verification/delivery_pin` | Handshake de validation du code de livraison. | Écriture d'une tentative par le shopper, vérifiée par transaction sécurisée. |
| `/catalog_categories` | Les 11 catégories de produits officielles. | Lecture publique / authentifiée. Écriture réservée aux administrateurs. |
| `/catalog_products` | Produits algériens recommandés. | Lecture publique / authentifiée avec fallback local embarqué ultra-rapide. |

---

## 4. Statut des Index Firestore

Pour optimiser les requêtes de recherche de missions par localisation, statut et date, le fichier `firestore.indexes.json` doit déclarer :
1. **Index Errand par statut et date :**
   - Collection : `errands`
   - Champs : `status` (ASC), `createdAt` (DESC)
2. **Index Errand par client et date :**
   - Collection : `errands`
   - Champs : `clientId` (ASC), `createdAt` (DESC)
3. **Index Errand par shopper assigné et date :**
   - Collection : `errands`
   - Champs : `shopperId` (ASC), `createdAt` (DESC)

---

## 5. Statut App Check & Écarts Résiduels

- **Debug Provider :**
  Lors de l'exécution sur émulateur ou appareil de test, le logcat Android produit un jeton :
  `Firebase App Check debug token: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
  Ce jeton doit être copié une seule fois dans la console Firebase sous *App Check > Apps > dili_express > Manage debug tokens*.
- **Play Integrity Provider :**
  En production, Play Integrity valide l'empreinte SHA-256 de la clé de signature Play Store (`53:F5:90:67:01:CA:B5:A3:91:E5:2C:4E:D1:61:29:0B:EF:18:32:CE:AA:E7:11:FC:BC:B8:0D:25:E1:E2:5B:9B`).
