# Rapport Technique — Corrections Fonctionnelles et Sécurité Applicative 9DILI EXPRESS

## 1. Contexte et Objectifs

Ce rapport documente les correctifs appliqués à l'application mobile Flutter/Dart **9DILI EXPRESS** (`com.ghdinteractivestudio.dili_express`) pour résoudre les anomalies fonctionnelles critiques, garantir la conformité des flux financiers et sécuriser les interactions entre Clients et Shoppeurs.

---

## 2. Synthèse des Problèmes et Corrections Appliquées

### A. Règle du Numéro de Téléphone Obligatoire & Échange Symétrique
- **Diagnostic** : Le modèle `UserModel` considérait le numéro de téléphone comme optionnel. Les utilisateurs pouvaient initier des commandes ou se déclarer en ligne sans numéro valide, rendant impossible l'appel obligatoire de coordination. De plus, lors de l'acceptation d'une offre dans `_openBidsSheet`, l'application transmettait `errand.shopperPhone` (qui valait `null` avant confirmation) au lieu de `bid.shopperPhone`.
- **Corrections Appliquées** :
  1. Ajout de `UserModel.isValidPhone` et `UserModel.hasValidPhone` (vérification regex `>= 9` chiffres, compatible indicatifs `+213` ou format national `05/06/07`).
  2. Blocage préventif avec dialogue guidant vers `ProfileScreen` :
     - Pour le Client : blocage de la création de liste si le téléphone est manquant.
     - Pour le Shoppeur : blocage du passage en ligne (`isOnline`) et de l'envoi d'offres (`_openPlaceBidDialog`).
  3. Ajout de `shopperPhone` dans `ErrandBidModel` et transmission systématique lors de `placeBid` et `acceptBid`.
  4. Mise à jour de `_makeMandatoryCall` :
     - Bouton « J'atteste l'appel » désactivé si le numéro de l'interlocuteur est absent ou invalide.
     - Bouton d'action direct « Composer : <numéro> » utilisant `url_launcher` avec le schéma `tel:`.

### B. Trésorerie du Shoppeur & Règles Firestore
- **Diagnostic** : Lors de la modification de `availableCash` dans `ProfileScreen`, aucune règle de mise à jour spécifique n'était définie dans `firestore.rules`, ce qui provoquait une erreur d'autorisation Firebase (`permission-denied`).
- **Corrections Appliquées** :
  1. Mise à jour de `firestore.rules` pour autoriser explicitement le propriétaire du document à modifier sa trésorerie :
     ```text
     allow update: if isOwner(userId) &&
                   request.resource.data.diff(resource.data).affectedKeys().hasOnly(['availableCash', 'updatedAt']) &&
                   request.resource.data.availableCash is number &&
                   request.resource.data.availableCash >= 0.0;
     ```
  2. Sécurisation de l'UI avec gestion d'erreurs `try/catch` et `SnackBar` de confirmation.

### C. Débordement Visuel du Mode de Transport (Overflow UI)
- **Diagnostic** : Sur les écrans de taille moyenne, le menu déroulant `DropdownButtonFormField<ShopperTransportType>` débordait horizontalement sur les libellés longs (ex: `En moto / scooter`).
- **Corrections Appliquées** :
  1. Ajout de `isExpanded: true` sur le champ déroulant dans `ProfileScreen`.
  2. Implémentation de `selectedItemBuilder` avec `TextOverflow.ellipsis` pour tronquer élégamment sans déborder.

### D. Géolocalisation GPS Obligatoire & Nom de Magasin Optionnel
- **Diagnostic** : La création d'une course exigeait un nom de magasin mais n'imposait pas de coordonnées GPS réelles, risquant la publication de fausses positions.
- **Corrections Appliquées** :
  1. Nom du magasin rendu optionnel : si laissé vide, application automatique du fallback neutre `Commerce de proximité / Supérette locale`.
  2. Coordonnées GPS de livraison rendues **strictement obligatoires** :
     - Bouton « Ma position GPS » via `Geolocator.getCurrentPosition()`.
     - Bouton « Pointer sur carte » via `FlutterMap` interactif (OpenStreetMap).
     - Blocage de la publication avec alerte rouge si `deliveryGeoPoint` est absent.

### E. Justificatif de Caisse & Ticket de Caisse
- **Diagnostic** : `ReceiptScreen` bloquait le passage en livraison si la référence textuelle de caisse n'était pas saisie avec un astérisque obligatoire, même lorsqu'une photo du ticket était prise.
- **Corrections Appliquées** :
  1. Référence textuelle rendue optionnelle si la photo est fournie (retrait de l'astérisque `*`).
  2. Validation conforme Spark sans Cloud Storage :
     `isReceiptValidated = ticketAmount > 0 && (ticketRef.isNotEmpty || ticketPhotoUrl.isNotEmpty)`.
  3. Intégration d'un sélecteur de photo caméra avec `image_picker` et affichage dynamique (`Image.file` ou `Image.network`).

---

## 3. Matrice des Fichiers Modifiés

| Fichier | Modification principale |
| :--- | :--- |
| `lib/models/user_model.dart` | `isValidPhone`, `hasValidPhone`, validation regex téléphones |
| `lib/models/errand_bid_model.dart` | Ajout et persistance de `shopperPhone` |
| `lib/services/errand_service.dart` | `acceptBid` avec paramètre `shopperPhone` |
| `lib/ui/screens/profile_screen.dart` | Validation téléphone, correction overflow transport, feedback trésorerie |
| `lib/ui/screens/home_screen.dart` | Appel obligatoire avec dialer, vérification téléphone Client & Shopper, carte Radar Shopper |
| `lib/ui/screens/create_errand_screen.dart` | GPS obligatoire (Geolocator + FlutterMap), magasin neutre par défaut |
| `lib/ui/screens/receipt_screen.dart` | Photo du ticket probante sans référence obligatoire, intégration `image_picker` |
| `firestore.rules` | Autorisation mise à jour `availableCash >= 0` et sous-collection `fcm_tokens` |
| `android/app/src/main/AndroidManifest.xml` | Intent filter dialer `<queries>` (`tel`), `POST_NOTIFICATIONS`, `CAMERA` |
