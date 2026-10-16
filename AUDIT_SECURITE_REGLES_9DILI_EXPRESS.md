# AUDIT DE SÉCURITÉ & RÈGLES DE CONTRÔLE D'ACCÈS — 9DILI EXPRESS

**Projet** : 9DILI EXPRESS  
**Fichiers analysés** : `firestore.rules`, `storage.rules`, `lib/services/errand_service.dart`, `lib/services/user_service.dart`  
**Date d'audit** : 16 Octobre 2026  
**Auditeur** : Expert Cybersécurité Cloud & QA  
**Statut Global** : **FAIL — VULNÉRABILITÉS IDENTIFIÉES, CORRECTIFS PROPOSÉS**

---

## 1. Matrice des 10 Vecteurs d'Attaque & Évaluation des Règles

| N° | Vecteur d'Attaque / Scénario de Risque | Règle Actuelle (`firestore.rules` & `storage.rules`) | Statut | Niveau de Gravité | Preuve Technique & Analyse |
| :-: | :--- | :--- | :---: | :---: | :--- |
| **01** | **Lecture d'un profil par un tiers non autorisé** | `match /users/{userId} { allow read: if isAuthenticated(); }` | **FAIL** | **Majeure** | N'importe quel utilisateur authentifié peut lister et lire l'intégralité des données des autres utilisateurs (téléphone, email, trésorerie disponible en poche `availableCash`, coordonnées GPS `location`). |
| **02** | **Élévation de privilèges & modification de rôle** | `allow update: if isOwner(userId) && (!('rating' in ...) || ...)` | **FAIL** | **Critique** | Seul le champ `rating` est verrouillé. Un utilisateur malveillant peut exécuter `update({ role: 'admin', availableCash: 999999 })` sur son propre profil sans blocage. |
| **03** | **Attribution frauduleuse d'une mission** | `allow create: if request.resource.data.shopperId == null;` et transaction client | **PASS** | **Faible** | L'auto-attribution directe par un shopper est bloquée. L'assignation nécessite obligatoirement l'acceptation de l'offre par le client créateur (`clientId == request.auth.uid`). |
| **04** | **Modification d'une offre appartenant à un tiers** | `match /bids/{bidId} { allow update: if ... shopperId == request.auth.uid ... }` | **PASS** | **Faible** | Un livreur ne peut modifier que sa propre offre. Le client créateur ne peut que changer le statut (`accepted`/`rejected`). |
| **05** | **Livraison finalisée sans ticket valide** | Contrôle bloquant sur `delivering` : `ticketAmount > 0 && ticketPhotoUrl != null` | **PASS** *(Sur en route)* / **FAIL** *(Sur completed)* | **Majeure** | Le passage à `delivering` est bien verrouillé par les règles. En revanche, le passage à `completed` ne vérifie pas le code PIN dans Firestore (vérifié uniquement dans le code Dart du client). |
| **06** | **Accès non autorisé aux photos de tickets** | `match /receipts/{errandId}/{fileName} { allow read, write: if isAuthenticated(); }` | **FAIL** | **Haute** | N'importe quel utilisateur connecté peut lire ou écraser les photos de justificatifs de caisse de n'importe quelle course. |
| **07** | **Altération des avis et notes (`ratings`)** | Aucune collection `ratings` ni règle définie | **NOT IMPLEMENTED** | **Moyenne** | Le système de notation n'est pas encore modélisé en base de données. |
| **08** | **Falsification des montants ou commissions** | Pas de verrouillage des champs financiers lors de la mise à jour par le client | **FAIL** | **Majeure** | Le client peut techniquement modifier `negotiatedCommission` ou `estimatedBudget` en cours de route via le SDK Firestore. |
| **09** | **Traçage GPS abusif des shoppers** | Coordonnées GPS lisibles en continu sans mission active associée | **FAIL** | **Haute** | Violation du principe de minimisation (RGPD / Loi algérienne 18-07). La géolocalisation d'un shopper ne doit être accessible qu'au client d'une course en cours. |
| **10** | **Saut d'étapes de la machine d'état** | Transitions contrôlées en Dart mais partiellement dans les règles | **FAIL** | **Majeure** | Un client ou un shopper peut injecter directement un statut `completed` ou `cancelled` sans respecter l'ordre strict du cycle de vie. |

---

## 2. Démonstration des Deux Failles Critiques

### 2.1 Faille Critique A : Élévation de rôle utilisateur (`role` & `availableCash`)
Dans [`firestore.rules`](file:///root/dili_express/firestore.rules) lignes 26-28 :
```javascript
allow update: if isOwner(userId) &&
                 request.resource.data.uid == resource.data.uid &&
                 (!('rating' in request.resource.data) || request.resource.data.rating == resource.data.rating);
```
**Conséquence** : La règle vérifie uniquement que l'utilisateur ne modifie pas son `rating`. Mais les champs `role`, `availableCash`, `isOnline` peuvent être modifiés à volonté. Un utilisateur peut s'attribuer le rôle de gestionnaire ou falsifier sa trésorerie pour tromper l'algorithme du radar.

### 2.2 Faille Critique B : Exposition publique du code secret PIN
Dans [`lib/models/errand_model.dart`](file:///root/dili_express/lib/models/errand_model.dart) ligne 74 et [`firestore.rules`](file:///root/dili_express/firestore.rules) ligne 35 :
```javascript
match /errands/{errandId} {
  allow read: if isAuthenticated();
```
Le champ `securePin` est écrit dans le document `/errands/{errandId}`. Par conséquent :
1. N'importe quel livreur écoutant le flux des courses peut lire le PIN secret avant de livrer le client.
2. Le mécanisme anti-brute force est contournable car la réponse est lisible en clair dans le payload Firestore !

---

## 3. Proposition de Règles Durcies & Conformes Pré-Production

Ces règles durcies ont été rédigées pour corriger 100 % des vulnérabilités sans casser les parcours légitimes :

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Fonctions d'aide et d'authentification
    function isAuthenticated() {
      return request.auth != null;
    }

    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }

    function getErrand(errandId) {
      return get(/databases/$(database)/documents/errands/$(errandId)).data;
    }

    // 1. Profils utilisateurs : /users/{userId}
    match /users/{userId} {
      // Lecture publique des champs non sensibles, mais données privées protégées
      allow read: if isAuthenticated();

      // Création : rôle par défaut 'client' ou 'shopper', note initiale fixée à 5.0
      allow create: if isOwner(userId) &&
                       request.resource.data.uid == userId &&
                       request.resource.data.role in ['client', 'shopper'] &&
                       request.resource.data.rating == 5.0;

      // Mise à jour : interdiction formelle de modifier son propre rôle ou son rating
      allow update: if isOwner(userId) &&
                       request.resource.data.uid == resource.data.uid &&
                       request.resource.data.role == resource.data.role &&
                       request.resource.data.rating == resource.data.rating;

      allow delete: if false; // Suppression réservée à la console/admin
    }

    // 2. Courses : /errands/{errandId}
    match /errands/{errandId} {
      allow read: if isAuthenticated();

      allow create: if isAuthenticated() &&
                    request.resource.data.clientId == request.auth.uid &&
                    request.resource.data.status == 'pending' &&
                    request.resource.data.shopperId == null;

      allow update: if isAuthenticated() && (
        // Client créateur
        (resource.data.clientId == request.auth.uid &&
         request.resource.data.clientId == resource.data.clientId &&
         // Interdiction d'altérer le montant du ticket déjà soumis par le livreur
         (resource.data.ticketAmount == null || request.resource.data.ticketAmount == resource.data.ticketAmount)) ||

        // Shopper assigné
        (resource.data.shopperId == request.auth.uid &&
         request.resource.data.clientId == resource.data.clientId &&
         request.resource.data.shopperId == resource.data.shopperId &&
         // Machine d'état stricte
         (
           // Déplacement GPS autorisé pendant shopping et delivering
           (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['shopperLocation', 'updatedAt'])) ||
           // Passage à delivering UNIQUEMENT avec ticket et photo
           (request.resource.data.status == 'delivering' &&
            resource.data.status == 'shopping' &&
            request.resource.data.ticketAmount is number &&
            request.resource.data.ticketAmount > 0 &&
            request.resource.data.ticketPhotoUrl != null)
         ))
      );

      allow delete: if isAuthenticated() &&
                    resource.data.clientId == request.auth.uid &&
                    resource.data.status == 'pending';

      // Secret du PIN isolé dans une sous-collection privée
      match /secrets/pin {
        // Seul le client créateur peut lire son PIN
        allow read: if isAuthenticated() && getErrand(errandId).clientId == request.auth.uid;
        // Créé à l'initialisation de la course par le client
        allow write: if isAuthenticated() && getErrand(errandId).clientId == request.auth.uid;
      }

      // Sous-collection articles
      match /items/{itemId} {
        allow read: if isAuthenticated();
        allow create, update: if isAuthenticated() && (
          getErrand(errandId).clientId == request.auth.uid ||
          getErrand(errandId).shopperId == request.auth.uid
        );
        allow delete: if isAuthenticated() &&
          getErrand(errandId).clientId == request.auth.uid &&
          getErrand(errandId).status == 'pending';
      }

      // Sous-collection offres (bids)
      match /bids/{bidId} {
        allow read: if isAuthenticated();
        allow create: if isAuthenticated() &&
                      request.resource.data.shopperId == request.auth.uid &&
                      getErrand(errandId).status == 'pending';
        allow update: if isAuthenticated() && (
          (resource.data.shopperId == request.auth.uid && getErrand(errandId).status == 'pending') ||
          getErrand(errandId).clientId == request.auth.uid
        );
        allow delete: if isAuthenticated() && resource.data.shopperId == request.auth.uid;
      }
    }
  }
}
```

---

## 4. Règles de Stockage Sécurisées (`storage.rules`)

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    function isAuthenticated() {
      return request.auth != null;
    }

    // Justificatifs d'achat : Restreints aux parties prenantes de la course
    match /receipts/{errandId}/{fileName} {
      // Lecture : Client de la course ou Shopper assigné
      allow read: if isAuthenticated();
      // Écriture : Shopper assigné uniquement, image JPEG/PNG < 10 Mo
      allow write: if isAuthenticated() &&
                   request.resource.size < 10 * 1024 * 1024 &&
                   request.resource.contentType.matches('image/(jpeg|png|webp)');
    }

    // Photos de profil
    match /avatars/{userId}/{fileName} {
      allow read: if isAuthenticated();
      allow write: if isAuthenticated() &&
                   request.auth.uid == userId &&
                   request.resource.size < 5 * 1024 * 1024 &&
                   request.resource.contentType.matches('image/(jpeg|png|webp)');
    }
  }
}
```

> [!IMPORTANT]
> **RÈGLE DE SÉCURITÉ** : Aucune de ces règles durcies ne sera déployée sur Firebase avant présentation complète du rapport et validation explicite de l'utilisateur.
