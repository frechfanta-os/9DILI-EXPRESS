# 9DILI EXPRESS — RAPPORT DES CORRECTIONS P0 / P1

**Application :** 9DILI EXPRESS  
**Date d'audit & d'implémentation :** 16 Octobre 2026  
**Identifiant Android / Package :** `com.ghdinteractivestudio.dili_express`  
**Projet Firebase Réel :** `dili-express` (Numéro : `273784230349`)  
**Dépôt GitHub :** `https://github.com/frechfanta-os/9DILI-EXPRESS.git`  
**Statut Global de Validation :** ✅ **PASS (100% Tests Validés - 42/42)**

---

## 1. Synthèse Exécutive des Corrections Appliquées

| Réf | Défaut Initial Audité | Gravité | Statut | Fichiers Modifiés / Créés | Preuve & Validation |
| :--- | :--- | :---: | :---: | :--- | :--- |
| **CORR-01** | `applicationId` Android divergent (`com.ghdinteractivestudio.diliexpress` vs `dili_express`) | **P0** | **RÉSOLU** | • `android/app/google-services.json`<br>• `lib/firebase_options.dart`<br>• `.firebaserc` | Enregistrement de l'app officielle `com.ghdinteractivestudio.dili_express` (App ID `1:273784230349:android:1317b52fa41defee973484`) sur `dili-express`. |
| **CORR-02** | Falsification de rôle privilégié (`role: 'admin'`) et solde (`availableCash`) côté client | **P0** | **RÉSOLU** | • `firestore.rules`<br>• `lib/services/user_service.dart`<br>• `lib/models/user_model.dart` | `firestore.rules` verrouille les modifications de `role`, `availableCash` et `rating`. Tests unitaires validés. |
| **CORR-03** | Fuite du PIN de livraison en clair dans le document principal de mission | **P0** | **RÉSOLU** | • `firestore.rules`<br>• `lib/models/errand_model.dart`<br>• `lib/services/errand_service.dart` | Découplage strict : le PIN est stocké exclusivement dans `/errands/{id}/secrets/pin` (accessible uniquement par le client). Vérification par transaction `/errands/{id}/verification/delivery_pin`. |
| **CORR-04** | Formule de tarification & Justificatif de caisse non obligatoires | **P0** | **RÉSOLU** | • `firestore.rules`<br>• `lib/models/errand_model.dart`<br>• `lib/services/errand_service.dart` | Règle `Total = Montant Ticket + Commission` strictement vérifiée. Transition vers `delivered` impossible sans `receiptUrl` et `actualReceiptAmount`. |
| **CORR-05** | Absence de protection Firebase App Check contre l'abus de quota | **P1** | **RÉSOLU** | • `pubspec.yaml`<br>• `lib/main.dart`<br>• `GUIDE_SHA_APP_CHECK_9DILI_EXPRESS.md` | Dépendance `firebase_app_check: ^0.5.0` intégrée avec `AndroidDebugProvider` en mode debug et `AndroidPlayIntegrityProvider` en production. |
| **CORR-06** | Dépendance risquée à Google Maps payant | **P1** | **RÉSOLU** | • `pubspec.yaml`<br>• `lib/services/map_tracking_service.dart`<br>• `lib/ui/screens/delivery_tracking_screen.dart` | Remplacement intégral par la stack 100% libre et gratuite `flutter_map: ^8.3.2` + OpenStreetMap (OSM) avec User-Agent conforme. |
| **CORR-07** | Manque de catalogue local algérien bilingue et modes de transport | **P1** | **RÉSOLU** | • `lib/models/catalog_category_model.dart`<br>• `lib/models/catalog_product_model.dart`<br>• `lib/services/catalog_service.dart`<br>• `lib/ui/screens/profile_screen.dart` | Intégration de 11 catégories officielles, 20+ produits du terroir (Cevital, Hamoud, Candia, Benamor...), 5 modes de transport Shopper et contrôles de capacité de charge. |
| **CORR-08** | Absence de dépôt Git local et d'hygiène du dépôt | **P1** | **RÉSOLU** | • `.git/`<br>• `.gitignore` renforcé | Initialisation Git propre, exclusion stricte des clés `.keystore`, `.jks`, `.env*` et secrets, liaison au remote `origin`. |

---

## 2. Détail Technique des Fichiers Modifiés & Créés

### 2.1. Sécurité Firestore (`firestore.rules`)
- **Isolation du PIN :**
  ```javascript
  match /errands/{errandId}/secrets/pin {
    allow read, write: if isSignedIn() && request.auth.uid == get(/databases/$(database)/documents/errands/$(errandId)).data.clientId;
  }
  ```
- **Interdiction de falsification de rôle :**
  ```javascript
  allow update: if isOwner(userId)
    && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['role', 'availableCash', 'rating']);
  ```
- **Validation stricte de la transition de livraison :**
  Exige obligatoirement `receiptUrl` non vide et `actualReceiptAmount > 0` pour passer au statut `delivered`.

### 2.2. Configuration Firebase & Android
- **`android/app/google-services.json` :** Récupéré directement du projet Firebase `dili-express` pour le package `com.ghdinteractivestudio.dili_express`.
- **`lib/firebase_options.dart` :** Aligné sur le numéro de projet officiel `273784230349` et l'application ID `1:273784230349:android:1317b52fa41defee973484`.
- **`lib/main.dart` :** Initialisation d'App Check robuste avec tolérance gracieuse hors-ligne.

### 2.3. Cartographie & Suivi GPS Libre (`lib/services/map_tracking_service.dart`)
- Intégration OpenStreetMap sans clé d'API, 100% gratuit à vie.
- User-Agent HTTP officiel : `com.ghdinteractivestudio.dili_express`.
- Calcul des distances orthodromiques corrigées (facteur sinuosité urbaine 1.3) et ETA dynamique selon le moyen de transport du Shopper.
- Marqueurs stylisés aux couleurs officielles Stitch V2 (Orange `#FF6D00` et Vert `#10B981`).

### 2.4. Catalogue Algérien Local & Hybride (`lib/services/catalog_service.dart`)
- **11 Catégories officielles :** Fruits & Légumes, Épicerie, Lait & Frais, Pain & Boulangerie, Viandes & Poissons, Boissons & Eaux, Hygiène, Entretien, Bébé, Papeterie, Terroir & Saisonnier.
- **Référentiel embarqué :** Huile Fleurial Cevital, Semoule Benamor, Couscous Sim, Pâtes Safina, Lait National, Lait Candia, Yaourt Soummam, Fromage Tartino, Boissons Hamoud Boualem (Selecto, Slim), Eau Ifri, Savon Le Taous, etc.
- Méthode de conversion automatique d'un produit sélectionné en `ErrandItemModel`.

### 2.5. Modes de Transport Shopper (`lib/models/user_model.dart` & `profile_screen.dart`)
- Support de 5 modes : À pied (5kg / 1.5km), Vélo (10kg / 3.5km), Trottinette (8kg / 3km), Moto (20kg / 10km), Voiture (80kg / 25km).
- Validation `canCarry(weight)` empêchant un Shopper à pied d'accepter des packs lourds non transportables.

---

## 3. Résultats des Tests de Non-Régression

Toutes les suites de tests automatisées s'exécutent avec succès :

```bash
$ flutter analyze
Analyzing dili_express...
No issues found! (ran in 12.1s)

$ flutter test
00:10 +42: All tests passed!
```

### Décomposition des 42 tests validés :
1. **`test/widget_test.dart` (5 tests) :**
   - Règle téléphone facultatif sur `UserModel`.
   - Formule financière obligatoire : Total = Ticket + Commission.
   - Validation de l'isolation du PIN.
2. **`test/integration_workflow_test.dart` (2 tests) :**
   - Séparation stricte des rôles Client vs Shopper.
   - Contrôle bloquant du justificatif de caisse et de la formule financière.
3. **`test/ui_components_test.dart` (24 tests) :**
   - Vérification de la palette officielle Stitch V2 (Orange, Vert, Violet, Blanc cassé).
   - Rendu visuel responsive (Format compact 360x640 et moderne 412x915).
   - États d'interface (chargement, erreur, succès, liste vide).
4. **`test/generate_visual_captures_test.dart` (1 test avec 18 captures vérifiées) :**
   - 9 écrans majeurs en double résolution conformes à l'archive ZIP livrée.
5. **`test/maps_catalog_transport_test.dart` (10 tests) :**
   - Validation des 11 catégories et du catalogue de produits algériens.
   - Recherche locale bilingue (arabe / français).
   - Modes de transport Shopper et capacité d'emport.
   - Calculs de distance orthodromique et ETA OpenStreetMap.
