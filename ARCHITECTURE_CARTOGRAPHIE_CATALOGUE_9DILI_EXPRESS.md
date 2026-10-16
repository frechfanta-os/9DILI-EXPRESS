# ARCHITECTURE TECHNIQUE : CARTOGRAPHIE LIBRE & CATALOGUE ALGÉRIEN — 9DILI EXPRESS

**Projet** : 9DILI EXPRESS  
**Date d'audit & conception** : 16 Octobre 2026  
**Auditeur** : Lead Architecte Mobile & Data  
**Statut Global** : **PROPOSED — EN ATTENTE DE VALIDATION AVANT IMPLÉMENTATION**

---

## PARTIE 1 : CARTOGRAPHIE LIBRE (PHASE D)

### 1.1 Composants Techniques Retenus
- **Affichage des cartes** : [`flutter_map: ^7.0.2`](https://pub.dev/packages/flutter_map) (Moteur open-source léger basé sur Leaflet).
- **Gestion des coordonnées** : `latlong2: ^0.9.1`.
- **Acquisition GPS** : [`geolocator: ^14.1.1`](file:///root/dili_express/pubspec.yaml) (déjà présent dans `pubspec.yaml`).
- **Tuiles de carte** : Fond OpenStreetMap standard (avec mise en cache locale via `flutter_map_cbl` ou `cached_network_image`).

### 1.2 Respect des Conditions d'Utilisation (Tile Usage Policy d'OSM)
Les serveurs de tuiles publics de la fondation OpenStreetMap (`tile.openstreetmap.org`) imposent des règles strictes qu'il est obligatoire de respecter pour éviter tout bannissement d'IP :
1. **User-Agent obligatoire et explicite** : Interdiction d'utiliser le User-Agent par défaut. Format imposé : `9DiliExpress-Flutter/1.0 (contact@ghdinteractivestudio.com)`.
2. **Attribution légale obligatoire** : Affichage permanent et lisible du bandeau légal `© OpenStreetMap contributors` en bas à droite de la carte.
3. **Mise en cache locale agressive** : Interdiction formelle de retélécharger les mêmes tuiles à chaque ouverture. Stockage en cache local des tuiles visitées (durée de validité 7 jours).
4. **Stratégie pour la Production** : Pour le passage à l'échelle commerciale, les serveurs de la fondation OSM ne disposent d'aucun SLA garanti. La recommandation technique est d'utiliser une clé de fournisseur de tuiles avec SLA (ex: Stadia Maps, MapTiler, ou serveur de tuiles auto-hébergé sur Cloudflare R2 / VPS).

### 1.3 Moteur de Routage & Calcul d'Itinéraire (OSRM / GraphHopper)
- **Environnement de Test / Préproduction** : Utilisation de l'API de démonstration OSRM (`router.project-osrm.org`) pour le calcul des distances et tracés polyline.
- **Limites d'utilisation** : L'instance publique d'OSRM interdit les requêtes à haute fréquence. L'application appliquera un bridage (throttling) : recalcul du trajet uniquement si le shopper s'écarte de plus de 50 mètres de son tracé initial.
- **Alternative de Production** : Déploiement d'une instance Docker légère OSRM contenant l'extrait cartographique de l'Algérie (`algeria-latest.osm.pbf`, ~120 Mo extrait de Geofabrik).

### 1.4 Respect de la Vie Privée & Contrôle GPS
1. **Minimisation des données** : Les coordonnées GPS précises ne sont partagées qu'entre les deux parties d'une course active (`shopping` et `delivering`).
2. **Arrêt immédiat du tracking** :
   - Dès la validation du code PIN de livraison (`status: completed`), le flux GPS est coupé instantanément.
   - Dès que le shopper bascule son bouton de disponibilité sur « Hors ligne », tout enregistrement de position est interrompu.
3. **Précision adaptative** : Précision élevée (`LocationAccuracy.high`) uniquement pendant le trajet de livraison ; précision moyenne (`LocationAccuracy.medium`) pendant les achats pour préserver la batterie du smartphone.

### 1.5 Interfaces logicielles prévues (Contrats d'API Dart)

```dart
abstract class ILocationTrackingService {
  Future<bool> requestPermissions();
  Stream<Position> get locationStream;
  Future<void> updateShopperLocation({required String errandId, required double lat, required double lng});
  Future<void> stopTracking();
}

abstract class IRoutingService {
  Future<RouteData> calculateRoute({
    required LatLng start,
    required LatLng destination,
    required String transportMode, // 'walking', 'cycling', 'driving'
  });
}
```

---

## PARTIE 2 : CATALOGUE DE PRODUITS ALGÉRIENS (PHASE E)

### 2.1 Schéma de Données du Catalogue

Le catalogue est conçu pour refléter les habitudes réelles d'achat en Algérie (multilinguisme français/arabe, marques nationales, unités locales).

```
Firestore
├── catalog_categories/{categoryId}
│   ├── categoryId: String (ex: "dairy_eggs")
│   ├── nameFr: String ("Lait & Produits Frais")
│   ├── nameAr: String ("حليب ومشتقاته")
│   ├── icon: String ("local_drink")
│   ├── sortOrder: int
│   └── isActive: bool
│
└── catalog_products/{productId}
    ├── productId: String (ex: "candia_silhouette_1l")
    ├── categoryId: String ("dairy_eggs")
    ├── nameFr: String ("Lait Candia Silhouette Demi-Écrémé")
    ├── nameAr: String ("حليب كانديا نصف دسم")
    ├── brand: String ("Candia / Tchin-Lait")
    ├── unit: String ("L", "kg", "pièce", "paquet", "bouteille")
    ├── defaultQuantity: int (1)
    ├── indicativePrice: double (115.0) // Clarté : INDICATIF UNIQUEMENT
    ├── priceUpdatedAt: Timestamp
    ├── barcode: String? ("6130000000000") // EAN-13 national
    ├── aliases: List<String> ["candia", "lait", "hlib", "كانديا", "حليب"]
    ├── imageUrl: String?
    └── isActive: bool
```

### 2.2 Les 11 Catégories Initiales & Marques Algériennes de Référence

| N° | Catégorie (Français) | Catégorie (Arabe) | Exemples de Produits & Marques Phares en Algérie |
| :-: | :--- | :--- | :--- |
| **01** | Fruits & Légumes | خضر وفواكه | Tomates, Pommes de terre (بطاطا), Oignons, Oranges de Boufarik, Dattes Deglet Nour (دقلة نور de Biskra). |
| **02** | Épicerie & Céréales | بقوليات وعجائن | Couscous Sim / Mama, Semoule Benamor / Safina, Pâtes Extrême, Huile Fleurial / Elio / Afia (Cevital), Sucre Ennour. |
| **03** | Lait & Produits Frais | حليب ومشتقاته | Lait en sachet pasteurisé (حليب الشكارة), Lait Candia, Yaourts Soummam / Danone / Trèfle, Fromage Tartino / Berbère. |
| **04** | Pain & Boulangerie | خبز ومخبوزات | Baguette ordinaire / améliorée, Khobz Eddar, Kesra (كسرة), Matlouh (مطلوع), Brioche. |
| **05** | Viandes, Volailles & Poissons | لحوم، دواجن وأسماك | Poulet entier vidé, Escalope de dinde, Viande hachée, Sardines fraîches du port. |
| **06** | Boissons & Eaux | مشروبات ومياه | Eau minérale Lalla Khedidja / Guedila / Ifri / Saïda, Soda Hamoud Boualem (Selecto, Slim), Jus Rouiba / Ifruit. |
| **07** | Hygiène Personnelle | عناية ونظافة شخصية | Savon Taous, Shampoing Doussy / Fructis, Dentifrice Signal, Couches Bébé Dalaa / Canbebe. |
| **08** | Entretien & Nettoyage | مواد التنظيف | Eau de Javel Bref / Maxis, Lessive en poudre Isis / Omo / Ariel, Liquide vaisselle Pril / Test. |
| **09** | Bébé & Puériculture | لوازم الأطفال الرضع | Lait infantile Guigoz / Célia, Céréales Blédine, Petits pots, Lingettes Dalaa. |
| **10** | Papeterie & Dépannage | أدوات مكتبية ومستلزمات | Cahiers scolaires, Stylos Bic, Sacs poubelle, Allumettes, Piles. |
| **11** | Terroir & Saisonnier | منتجات تقليدية وموسmية | Huile d'olive de Kabylie, Miel pur, Pâte de dattes Ghers (غرس), Frik pour chorba. |

### 2.3 Intégration d'Open Food Facts (Données Ouvertes)
- **Licence** : Open Database License (ODbL) — Utilisation commerciale permise avec attribution.
- **Couverture Algérie** : Plus de 8 500 produits emballés identifiés sous le préfixe EAN-13 `613...`.
- **Règle de résilience locale** : L'application n'appellera jamais l'API Open Food Facts en direct pendant les courses pour éviter les ralentissements ou pannes de réseau. Un sous-ensemble pré-filtré sera packagé dans un fichier JSON/SQLite local embarqué dans l'application pour une recherche instantanée hors-ligne.

### 2.4 Ajout d'Articles Hors-Catalogue & Flexibilité Magasin
- Si un article recherché par le client ne figure pas dans le catalogue suggéré, un bouton « **Ajouter un article personnalisé** » permet de saisir librement le libellé, la quantité et une note vocale ou écrite (ex: *« Pain de campagne bien cuit »*).
- **Règle métier impérative** : Le prix affiché dans le catalogue est rigoureusement étiqueté **« Prix Indicatif Moyen »**. Le prix final facturé est **exclusivement celui du ticket de caisse réel** certifié par le Shopper lors de la clôture des achats.
