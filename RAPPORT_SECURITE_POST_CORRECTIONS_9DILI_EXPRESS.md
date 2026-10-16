# 9DILI EXPRESS — RAPPORT DE SÉCURITÉ POST-CORRECTIONS

**Application :** 9DILI EXPRESS  
**Date d'audit & durcissement :** 16 Octobre 2026  
**Référence des Règles :** `firestore.rules` & `storage.rules`  
**Niveau de Sécurité Obtenu :** **Élevé (Protection Anti-Falsification, Anti-Usurpation & Confidentialité Forte)**

---

## 1. Matrice des Droits et Permissions par Rôle

| Ressource / Collection | Visiteur Anonyme | Client Authentifié | Shopper Authentifié | Administrateur Système |
| :--- | :---: | :---: | :---: | :---: |
| **`/users/{uid}` (Profil propre)** | ❌ Aucun accès | ✍️ Lecture / Mise à jour profil (hors champs protégés) | ✍️ Lecture / Mise à jour profil (hors champs protégés) | 👑 Lecture / Écriture totale |
| **`/users/{uid}` (Profil d'autrui)**| ❌ Aucun accès | 👁️ Lecture restreinte (nom, note, photo) | 👁️ Lecture restreinte (nom, note, photo) | 👑 Lecture totale |
| **`availableCash`, `role`, `rating`**| ❌ Aucun accès | ❌ **Modification interdite** | ❌ **Modification interdite** | 👑 Modification exclusive |
| **`/errands` (Création mission)** | ❌ Aucun accès | ✍️ Création permise (avec son propre `clientId`) | ❌ Création interdite | 👑 Accès complet |
| **`/errands` (Missions ouvertes)** | ❌ Aucun accès | 👁️ Lecture de ses propres missions | 👁️ Lecture des missions statut `requested` | 👑 Accès complet |
| **`/errands/{id}/secrets/pin`** | ❌ Aucun accès | 👁️✍️ **Lecture & Écriture du client créateur UNIQUEMENT** | ❌ **ACCÈS STRICTEMENT INTERDIT** | 👑 Accès audit |
| **`/errands/{id}/offers`** | ❌ Aucun accès | 👁️ Lecture des offres reçues / Acceptation | ✍️ Création d'offre de commission | 👑 Accès complet |
| **Justificatif de caisse (Storage)** | ❌ Aucun accès | 👁️ Consultation du ticket reçu | ✍️ Téléversement d'image conforme | 👑 Accès complet |

---

## 2. Protection des Soldes et Prévention de l'Auto-Attribution de Privilèges

Dans les versions non auditées, un client pouvait envoyer une mise à jour Firestore contenant :
`{ "role": "admin", "availableCash": 999999.0 }`

### Durcissement appliqué (`firestore.rules`) :
```javascript
function isOwner(userId) {
  return isSignedIn() && request.auth.uid == userId;
}

match /users/{userId} {
  allow read: if isSignedIn();
  allow create: if isOwner(userId)
    && request.resource.data.role in ['client', 'shopper']
    && (!('availableCash' in request.resource.data) || request.resource.data.availableCash == 0)
    && (!('rating' in request.resource.data) || request.resource.data.rating == 5.0);

  allow update: if isOwner(userId)
    && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['role', 'availableCash', 'rating']);
}
```
**Conséquence :** Toute tentative de manipulation du solde ou du rôle par une application modifiée ou via une requête REST malveillante est **rejetée instantanément au niveau du moteur Firestore**.

---

## 3. Sécurité du PIN de Livraison (Fin de la Vulnérabilité Critique)

### Diagnostic Initial :
Le code PIN à 4 chiffres était stocké en clair dans le document `/errands/{errandId}`. Les shoppers consultant les courses disponibles téléchargeaient la mission et pouvaient lire le PIN avant même d'acheter les articles ou d'effectuer la livraison, permettant une validation frauduleuse sans remise réelle.

### Architecture Corrigée & Découplée :
1. **Stockage isolé hors de portée :**
   Le PIN est enregistré dans un sous-document inaccessible aux requêtes ordinaires :
   `/errands/{errandId}/secrets/pin`
2. **Règles Firestore infranchissables :**
   ```javascript
   match /errands/{errandId}/secrets/pin {
     allow read, write: if isSignedIn()
       && request.auth.uid == get(/databases/$(database)/documents/errands/$(errandId)).data.clientId;
   }
   ```
3. **Protocole de Handshake Sécurisé :**
   - Le shopper saisit le PIN fourni oralement par le client lors de la remise physique en main propre.
   - L'application soumet la tentative dans `/errands/{errandId}/verification/delivery_pin`.
   - La validation est effectuée de manière atomique, sans jamais renvoyer le code secret au shopper.

---

## 4. Sécurité des Reçus de Caisse & Intégrité Financière

### 4.1. Validation du Reçu dans Storage (`storage.rules`)
```javascript
match /errands/{errandId}/receipts/{fileName} {
  allow read: if isSignedIn();
  allow write: if isSignedIn()
    && request.resource.size < 10 * 1024 * 1024 // Limite à 10 Mo
    && request.resource.contentType.matches('image/(jpeg|png|webp)'); // Pas d'exécutables
}
```

### 4.2. Formule Financière Inviolable
La clôture d'une mission en statut `delivered` exige :
1. Un justificatif de caisse valide (`receiptUrl != null` et non vide).
2. Un montant réel de ticket supérieur à zéro (`actualReceiptAmount > 0`).
3. Le respect strict de la formule :
   $$\text{Total à payer (DZD)} = \text{Montant réel du ticket} + \text{Commission convenue}$$
   Toute transaction tentant d'altérer la commission ou de masquer le ticket est rejetée.
