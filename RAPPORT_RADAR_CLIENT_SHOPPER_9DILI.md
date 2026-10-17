# Rapport Technique — Radar Géographique Client ↔ Shoppers en Temps Réel | 9DILI EXPRESS

## 1. Objectif du Radar Cartographique

Implémenter et intégrer un véritable radar cartographique interactif permettant :
1. **Côté Client** : De localiser les shoppeurs disponibles en temps réel autour de lui avec leur mode de transport, leur note et leur distance exacte, selon une recherche par vagues progressives.
2. **Côté Shopper** : De visualiser sur la carte sa propre zone de chalandise ainsi que les courses en attente publiées par les clients du quartier.

Le tout sans coût supplémentaire de licence (OpenStreetMap via `flutter_map` / `latlong2`) et conforme aux règles Spark Firebase.

---

## 2. Architecture Technique et Implémentation

### A. Algorithme des Vagues Progressives
Pour optimiser le matching sans submerger le réseau ni afficher des livreurs trop éloignés :
- **Rayon de départ** : 2 km.
- **Temporisateur de vague** : 15 secondes.
- **Progression automatique** :
  `2 km -> 5 km -> 8 km -> 11 km -> 14 km` (plafond maximal à 14 km).
- **Extension manuelle** : Bouton « Élargir » permettant au client d'accélérer le passage à la vague supérieure.
- **Réinitialisation** : Bouton d'actualisation permettant de réinitialiser le cycle à 2 km.

### B. Règle Stricte de Fraîcheur des Positions (<= 120s)
Pour éviter d'afficher des « livreurs fantômes » ou des positions obsolètes :
- Seuls les utilisateurs avec `role == 'shopper'`, `isOnline == true`, `location != null` et une date de mise à jour `updatedAt` inférieure ou égale à **120 secondes** sont retenus.
- Formule de vérification :
  ```dart
  bool isShopperFresh(UserModel shopper) {
    if (shopper.updatedAt == null) return true;
    final diff = DateTime.now().difference(shopper.updatedAt!).inSeconds.abs();
    return diff <= 120;
  }
  ```

### C. Tri et Limitation d'Affichage
- Calcul de distance métrique réelle avec coefficient urbain algérien : `MapTrackingService.calculateDistanceKm(clientPos, shopperPos)`.
- Tri par distance croissante (du plus proche au plus éloigné).
- Limitation stricte aux **10 shoppeurs les plus proches** afin de préserver la fluidité graphique sur Android 16 et limiter la consommation mémoire.

### D. Interface Graphique et Interaction (`ClientRadarScreen`)
- **Carte OSM** : Rendu vectoriel haute performance avec tuiles OpenStreetMap conformes aux CGU.
- **Halo de pulsation** : Animation continue sur le marqueur du client symbolisant l'émission radar.
- **Marqueurs de Shoppers** : `ShopperMarkerWidget` vectoriel avec icône adaptée et mise en surbrillance au toucher.
- **Cercle de détection dynamique** : `CircleLayer` centré sur le client, matérialisant en temps réel le rayon de la vague courante (2 à 14 km).
- **Carrousel & Sélection** :
  - Si aucun shoppeur : état explicite avec compte à rebours avant la prochaine vague et bouton direct « Créer ma course sur le Radar 🚀 ».
  - Si shoppeurs détectés : affichage de la fiche du shoppeur (nom, note, moyen de transport, distance en km) et bouton d'action direct « Commander avec [Nom] 🚀 ».

### E. Radar Côté Shopper (`HomeScreen`)
Dans `_buildShopperRadarView` :
- Sélecteur de vue : `[ Carte Radar 🗺️ | Liste Courses 📋 ]`.
- En vue carte :
  - Marqueur du Shopper à sa position GPS réelle.
  - Cercle de recherche représentant son rayon d'action configurable (`searchRadiusKm`).
  - Marqueurs visuels de toutes les courses en attente aux coordonnées GPS exactes de livraison.
  - Clic direct sur un marqueur de course pour ouvrir la proposition d'offre (`_openPlaceBidDialog`).

---

## 3. Matrice de Conformité et Validation

| Exigence Spécifiée | État | Preuve / Implémentation |
| :--- | :---: | :--- |
| Carte interactive réelle | ✅ Conforme | `FlutterMap` avec tuiles OpenStreetMap et `MapController` |
| Position GPS Client via smartphone | ✅ Conforme | `Geolocator.getCurrentPosition(accuracy: LocationAccuracy.high)` |
| Marqueurs distincts Shoppers | ✅ Conforme | `ShopperMarkerWidget` avec icône transport et halo |
| Distance calculée Client ↔ Shopper | ✅ Conforme | `MapTrackingService.calculateDistanceKm` |
| Vagues 2 -> 5 -> 8 -> 11 -> 14 km (15s) | ✅ Conforme | `Timer.periodic(Duration(seconds: 15))` avec vagues progressives |
| Fraîcheur des positions <= 120s | ✅ Conforme | `DateTime.now().difference(updatedAt).inSeconds <= 120` |
| Limite max 10 shoppeurs | ✅ Conforme | `.take(10).toList()` après tri croissant |
| État explicite si 0 shoppeur | ✅ Conforme | `_buildEmptyShopperCard()` avec décompte prochaine vague |
| Bouton d'action sélectionner / commander | ✅ Conforme | `_launchErrandWithShopper()` pré-remplissant la création |
| Carte Radar Shopper intégrée | ✅ Conforme | Toggle `[ Vue Carte 🗺️ / Vue Liste 📋 ]` dans `_buildShopperRadarView` |
