# 9DILI EXPRESS — RAPPORT D'INTÉGRATION CARTOGRAPHIE & CATALOGUE ALGÉRIEN

**Application :** 9DILI EXPRESS  
**Date d'implémentation :** 16 Octobre 2026  
**Périmètre :** OpenStreetMap (OSM), Catalogue Hybride Algérien, Modes de Transport Shopper  
**Statut :** ✅ **100% Implémenté & Validé en Production**

---

## 1. Architecture Cartographique 100% Libre et Gratuite (OpenStreetMap)

### 1.1. Éviction Totale des Dépendances Payantes Google Maps
Pour garantir la pérennité économique du projet et éliminer tout risque de facturation surprise sur la carte bancaire, la dépendance à Google Maps SDK a été intégralement rejetée au profit d'une stack Flutter native et ouverte :
- **Bibliothèque de rendu cartographique :** `flutter_map: ^8.3.2`
- **Calculs géodésiques et coordonnées :** `latlong2: ^0.10.1`
- **Serveur de tuiles mondiales :** OpenStreetMap Standard (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`)
- **Coût d'exploitation :** **0,00 DZD / 0,00 $ à vie**.

### 1.2. Respect Strict de la Politique d'Utilisation OpenStreetMap (OSM Tile Usage Policy)
L'implémentation dans `MapTrackingService` honore scrupuleusement les exigences de la fondation OpenStreetMap :
- **User-Agent HTTP personnalisé obligatoire :** `com.ghdinteractivestudio.dili_express`
- Mise en cache intelligente des tuiles pour minimiser les requêtes réseau.
- Attribution légale OpenStreetMap intégrée.

### 1.3. Algorithmes de Calcul & Estimation des Trajets
- **Distance orthodromique réelle avec coefficient urbain algérien :**
  Les distances à vol d'oiseau sont pondérées d'un coefficient de sinuosité urbaine de 1.3 adapté aux ruelles et boulevards des villes algériennes (Alger, Oran, Constantine, etc.).
- **Calcul dynamique de l'ETA (Estimation du Temps d'Arrivée) :**
  Adapté en temps réel à la vitesse moyenne du mode de transport du Shopper.
- **Grille tarifaire transparente suggérée :**
  Base forfaitaire de 250 DZD + 50 DZD par km au-delà de 2 km, arrondie à 10 DZD près.

---

## 2. Référentiel du Catalogue Algérien Bilingue (FR / AR)

### 2.1. Les 11 Catégories Officielles

| ID Catégorie | Nom Français | Nom Arabe | Icône UI | Ordre |
| :--- | :--- | :--- | :--- | :---: |
| `fruits_legumes` | Fruits & Légumes | خضر وفواكه | `Icons.eco` | 1 |
| `epicerie` | Épicerie & Féculents | بقالة ومواد غذائية | `Icons.shopping_bag` | 2 |
| `lait_frais` | Lait, Produits Frais & Fromages | حليب ومشتقاته | `Icons.egg` | 3 |
| `pain_boulangerie` | Pain & Boulangerie | خبز ومخبوزات | `Icons.bakery_dining` | 4 |
| `viandes_poissons` | Viandes, Volailles & Poissons | لحوم، دواجن وأسماك | `Icons.restaurant` | 5 |
| `boissons` | Boissons & Eaux | مشروبات ومياه | `Icons.local_cafe` | 6 |
| `hygiene` | Hygiène Personnelle | عناية ونظافة شخصية | `Icons.clean_hands` | 7 |
| `entretien` | Entretien & Nettoyage | مواد التنظيف | `Icons.cleaning_services` | 8 |
| `bebe` | Bébé & Puériculture | لوازم الأطفال الرضع | `Icons.child_care` | 9 |
| `papeterie` | Papeterie & Dépannage | أدوات مكتبية ومستلزمات | `Icons.menu_book` | 10 |
| `terroir_saisonnier`| Produits du Terroir | منتجات تقليدية وموسمية | `Icons.spa` | 11 |

### 2.2. Référentiel des Marques du Terroir Embarqué
Le catalogue intègre dès le démarrage (fonctionnement 100% hors-ligne garanti) les produits emblématiques de la consommation quotidienne en Algérie :
- **Huiles & Matières Grasses :** Huile Fleurial Cevital 5L (650 DZD).
- **Semoules & Pâtes :** Semoule Moyenne Amor Benamor 5kg (280 DZD), Couscous Sim 1kg (120 DZD), Spaghettis Extrême Safina 500g (65 DZD).
- **Lait & Frais :** Lait pasteurisé en sachet national (25 DZD), Lait Candia Silhouette 1L (125 DZD), Pack Yaourt Soummam Panaché x8 (240 DZD), Fromage fondu Tartino 16P (210 DZD).
- **Boissons :** Hamoud Boualem Selecto 1L (95 DZD), Eau minérale Ifri pack 6x1.5L (210 DZD).
- **Entretien & Hygiène :** Savon Le Taous 125g (80 DZD), Liquide vaisselle Maxis 1L (160 DZD), Couches Bébé Dalaa Taille 4 (1350 DZD).

---

## 3. Modes de Transport Shopper & Contrôles de Capacité

Le modèle `UserModel` intègre désormais le type de déplacement et le rayon d'action du Shopper :

| Mode de Transport | Vitesse Urbaine Moyenne | Rayon Conseillé | Poids Max Conseillé | Exemples de Paniers Compatibles |
| :--- | :---: | :---: | :---: | :--- |
| **À pied** | 4.5 km/h | Jusqu'à 1.5 km | 5 kg max | Pain, dépannage épicerie, médicaments. |
| **À vélo** | 14.0 km/h | Jusqu'à 3.5 km | 10 kg max | Sac de courses classique avec légumes et lait. |
| **En trottinette** | 16.0 km/h | Jusqu'à 3.0 km | 8 kg max | Courses d'appoint rapides en centre-ville. |
| **En moto / scooter** | 30.0 km/h | Jusqu'à 10.0 km | 20 kg max | Deux sacs pleins, pack d'eau d'appoint, livraison express. |
| **En voiture** | 25.0 km/h | Jusqu'à 25.0 km | 80 kg max | Grosses courses familiales, multiples packs d'eau Ifri, sacs de semoule 25kg. |

**Sécurité intégrée :** La méthode `canCarry(double estimatedWeightKg)` prévient les acceptations de missions incompatibles avec le moyen de transport du livreur.
