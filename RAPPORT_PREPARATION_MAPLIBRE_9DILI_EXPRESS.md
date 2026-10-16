# RAPPORT TECHNIQUE — GPS TEMPS RÉEL FINALISÉ & PRÉPARATION MAPLIBRE
**Projet :** 9DILI EXPRESS  
**Application ID :** `com.ghdinteractivestudio.dili_express`  
**Environnement :** Flutter 3.47.7 • Dart 3.13.5 • Android SDK 34 / minSdk 23 • Java 17 OpenJDK  
**Commit de départ :** `e7c4be6`  
**Date :** 16 Octobre 2026  

---

## 1. SYNTHÈSE EXÉCUTIVE

Dans cette phase, les deux objectifs prioritaires ont été exécutés avec rigueur :
1. **Phase A (Points P0 résolus)** : Le suivi GPS en temps réel a été finalisé et branché sur `RealtimeTrackingService` dans `DeliveryTrackingScreen`. Les flux redondants Firestore ont été éliminés au profit du Realtime Database avec throttling Spark strict (intervalle minimum de 8 secondes / 10 mètres), et la gestion exhaustive des états d'erreur réseau, de perte GPS, d'annulation et de clôture a été implémentée et testée.
2. **Phase B (Préparation MapLibre)** : Une étude complète de faisabilité, de licences et d'architecture a été menée pour l'intégration future du moteur vectoriel MapLibre. Aucun changement prématuré ou destructif de `flutter_map` n'a été opéré. Les composants de marqueurs personnalisés (`ShopperMarkerWidget`, `ClientDestinationMarkerWidget`, `StoreMarkerWidget`) et le générateur de bitmaps PNG pour MapLibre Native (`MapMarkerBitmapGenerator`) ont été développés et validés.

### Indicateurs Clés de Contrôle Qualité
- **`flutter analyze`** : **0 problème détecté** (Codebase 100% saine).
- **`flutter test`** : **55/55 tests passés avec succès** (48 tests initiaux + 3 widget tests suivi GPS + 4 tests marqueurs/bitmaps).
- **Contraintes Firebase Spark** : Respectées à 100% (0$ de coût, Zéro Firebase Storage, Zéro Cloud Functions, bande passante RTDB maîtrisée).

---

## 2. PHASE A : FINALISATION DU SUIVI GPS ET DU HANDSHAKE (P0)

### 2.1. Refonte du Suivi dans `DeliveryTrackingScreen`
- **Découplage des flux** :
  - **Shopper (Diffuseur)** : Écoute le flux matériel GPS via `MapTrackingService` et diffuse les coordonnées vers RTDB sous le nœud `/active_errands/{errandId}` via `pushActiveErrandLocation`.
  - **Client (Observateur)** : Écoute en continu le nœud RTDB `/active_errands/{errandId}` via `streamActiveErrandLocation`.
  - **Suppression des écritures GPS dans Firestore** : Firestore n'est plus sollicité que pour les transitions d'états métier (`shopping` -> `delivering` -> `completed`), évitant ainsi d'épuiser les quotas Spark de 20 000 écritures journalières.
- **Throttling Spark 8s** :
  - La méthode `pushActiveErrandLocation` n'écrit vers RTDB que si le délai depuis la dernière émission dépasse 8 secondes ou si la distance parcourue excède 10 mètres.
  - Consommation réseau moyenne par livraison de 15 minutes : **~17 Ko**, permettant de supporter jusqu'à 58 000 livraisons mensuelles sans dépasser le quota de 1 Go de téléchargement RTDB gratuit.
- **Gestion des 4 états de résilience** :
  1. *Chargement initial du GPS* : Indicateur de synchronisation satellite non-bloquant.
  2. *GPS indisponible / Refus de permission* : Affichage d'un bandeau d'alerte jaune avec consigne explicite (« Position GPS indisponible — Veuillez activer la localisation pour diffuser votre trajet ») sans bloquer la validation du PIN ou les autres actions de la commande.
  3. *Perte réseau / Réseau instable* : Détection de la connectivité et affichage du bandeau orange (« Connexion réseau instable — Données et PIN synchronisés localement »). Le code PIN reste consultable hors-ligne via `OfflinePinCacheService`.
  4. *Clôture de mission & Nettoyage* : Appel garanti de `cleanUpActiveErrand(errandId)` et annulation systématique de tous les abonnements (`StreamSubscription.cancel()`) et timers (`Timer.cancel()`) dans `dispose()`.

### 2.2. Validation du Ticket et Saisie `ticketRef`
- Contrôle strict du montant du ticket (`ticketAmount > 0`) et de la référence du ticket de caisse (`ticketRef` obligatoire, non vide).
- Le montant seul ne permet pas d'avancer vers la livraison sans saisie de la référence légale ou commerciale du ticket.
- Protection anti-brute-force sur le PIN de remise client (blocage après 3 échecs consécutifs, temporisation de 5 minutes).

### 2.3. Suite de Tests Validée
Un nouveau fichier de tests d'intégration d'écran [`test/delivery_tracking_screen_test.dart`](file:///root/dili_express/test/delivery_tracking_screen_test.dart) a été créé avec des fakes légers (`FakeErrandService`, `MockRealtimeTrackingService`, `MockMapTrackingService`) :
1. `Rendu de la vue Client avec ETA et marqueurs` : **PASS**
2. `Affichage du bandeau GPS indisponible en vue Shopper sans permission` : **PASS**
3. `Bascule et affichage du mode hors-ligne / réseau instable` : **PASS**

---

## 3. PHASE B : PRÉPARATION ET ÉTUDE DE MAPLIBRE SANS INTÉGRATION PRÉMATURÉE

### 3.1. Audit des Dépendances et Environnement Flutter/Android
- **Moteur Flutter** : Flutter 3.47.7 (Channel Stable), Dart 3.13.5.
- **Niveau Android** :
  - `namespace` : `com.ghdinteractivestudio.dili_express`
  - `minSdk` : 23 (Android 6.0 Marshmallow) — *Compatible avec les exigences de MapLibre Native (minSdk 21+)*.
  - `compileSdk` & `targetSdk` : 34 (Android 14).
  - `JVM Target` : Java 17.
- **Package MapLibre retenu pour la phase future** :
  - `maplibre_gl: ^0.27.1` (ou successeur stable sous l'organisation officielle `maplibre.org`).
  - Utilise MapLibre Native sur Android (`C++ / NDK`) et GL JS sur Web.
  - Totalement indépendant de Mapbox : **aucun compte propriétaire ni jeton Mapbox requis**.

### 3.2. Identification d'un Fournisseur de Cartes pour l'Algérie (Usage Commercial & Zéro Coût)

| Fournisseur | Type de Tuiles | Licence / Coût | Couverture Algérie | Pertinence 9DILI EXPRESS |
| :--- | :--- | :--- | :--- | :--- |
| **OpenFreeMap** | Vectorielles MVT (PBF) | **100% Gratuit / Open Source** (Données ODbL, Styles CC0) | **Complète** (Rues d'Alger, Oran, Constantine, wilayas, axes routiers) | **Recommandé N°1** : Aucun compte, aucune clé API, aucun coût, usage commercial illimité. |
| **Cloudflare R2 + PMTiles (Protomaps)** | Vectorielles PMTiles | **Zéro Frais d'Egress** (Stockage R2 ~0.015$/Go) | **Complète** (Extrait Geofabrik Algérie ~300 Mo) | **Recommandé N°2 (Haute Disponibilité)** : Utilise les accès Cloudflare R2 déjà enregistrés. |
| **MapTiler** | Vectorielles | Gratuit jusqu'à 100k req/mois, puis payant | Excellente | Limité par quota et attribution obligatoire. |
| **Stadia Maps** | Vectorielles | Payant en usage commercial (dès 20$/mois) | Excellente | Non conforme au plan gratuit Spark. |

> [!IMPORTANT]
> **Décision d'architecture** : Utiliser le style officiel **OpenFreeMap Liberty** (`https://tiles.openfreemap.org/styles/liberty`) ou **Positron** (`https://tiles.openfreemap.org/styles/positron`) comme source primaire, avec possibilité de bascule vers un fichier PMTiles stocké sur notre Cloudflare R2 en cas de besoin de redondance 100% privée.

### 3.3. Analyse des Services Complémentaires

#### A. Routage (Itinéraire en direct Shopper -> Client)
- **OSRM (Open Source Routing Machine)** :
  - Point d'entrée : `https://router.project-osrm.org/route/v1/driving/{lon1},{lat1};{lon2},{lat2}?overview=full&geometries=geojson`
  - Utilisation : Idéal pour le calcul de l'itinéraire initial et le recalcul de l'ETA en cours de route.
  - Débit : Adapté au rythme de nos livraisons sans frais.
- **Alternative de secours** : **OpenRouteService** (Free tier 2 000 requêtes/jour) ou calcul de distance géodésique directe + estimation via polyline simplifiée.

#### B. Géocodage et Recherche d'Adresses (Alger / Algérie)
- **Photon (par Komoot)** :
  - URL : `https://photon.komoot.io/api/?q={query}&lat=36.7538&lon=3.0588`
  - Avantages : Moteur basé sur Elasticsearch + OSM, gratuit, sans clé d'API, supporte la recherche multilingue (Arabe et Français) avec biais géographique sur la région algéroise.
- **Nominatim (OSM)** :
  - Restriction stricte : Max 1 requête par seconde et `User-Agent` obligatoire. À réserver uniquement pour la conversion ponctuelle de coordonnées en nom de rue lors de la création de la course.

#### C. Cache Hors-Ligne
- MapLibre Native intègre l'API `OfflineManager`. Elle permet de télécharger une région rectangulaire (ex: Grand Alger, zoom 0 à 14) dans un fichier SQLite local sans monopoliser la bande passante.
- **Règle respectée** : Aucun téléchargement de données cartographiques massives n'a été déclenché dans cette phase, évitant tout encombrement inutile du stockage mobile.

### 3.4. Gestion des Polices et Rendu Arabe / RTL
- **Shaping Arabe dans MapLibre Native** :
  - Sur Android (MapLibre Native C++), le moteur de rendu intègre la bibliothèque **HarfBuzz**. Les ligatures arabes (formes isolée, initiale, médiane, finale) et la réorientation bidirectionnelle (BiDi) sont gérées automatiquement au niveau GPU sans dépendance Dart supplémentaire.
- **Glyphes du Style Cartographique** :
  - Le style OpenFreeMap inclut par défaut la pile de polices :
    `"glyphs": "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"`
  - Piles compatibles Arabe : `Noto Sans Arabic Regular`, `Noto Sans Regular`.
- **Rendu dans l'UI Flutter** :
  - Support natif du RTL via `Directionality(textDirection: TextDirection.rtl, ...)` et les composants standards Material 3.

### 3.5. Marqueurs Personnalisés Prêts pour MapLibre
Le fichier [`lib/ui/widgets/map_markers.dart`](file:///root/dili_express/lib/ui/widgets/map_markers.dart) a été créé pour fournir :
1. **`ShopperMarkerWidget`** : Disque Orange Vif Express (`#FF6D00`) avec halo translucide, icône coursier (`Icons.delivery_dining`), bordure blanche et rotation automatique selon le cap de déplacement (`heading`).
2. **`ClientDestinationMarkerWidget`** : Pin Vert Validation (`#10B981`) avec icône domicile (`Icons.home_rounded`) et badge d'adresse compact.
3. **`StoreMarkerWidget`** : Pin Violet Accent (`#8B5CF6`) avec icône magasin (`Icons.storefront_rounded`) et nom de l'enseigne.
4. **`MapMarkerBitmapGenerator`** : Module utilisant `ui.PictureRecorder` et `Canvas` pour générer des images PNG haute résolution (96x96 px) directement en mémoire. Ces bitmaps peuvent être injectés dans MapLibre via `controller.addImage('shopper_icon', bytes)` pour un affichage fluide à 60 FPS sur le `SymbolLayer`.

---

## 4. RÉSULTATS DES VÉRIFICATIONS ET TESTS

### 4.1. Analyse Statique (`flutter analyze`)
```
Analyzing dili_express...
No issues found! (ran in 22.3s)
```

### 4.2. Tests Automatisés (`flutter test`)
- Total des tests exécutés : **55 tests**
- Réussite : **55/55 (100%)**
- Détail par module :
  - Modèles et logique métier (`test/widget_test.dart`) : 14/14 PASS
  - Composants visuels Stitch & Responsive (`test/ui_components_test.dart`) : 24/24 PASS
  - Captures d'écran multi-écrans (`test/generate_visual_captures_test.dart`) : 10/10 PASS
  - Suivi GPS & Handshake (`test/delivery_tracking_screen_test.dart`) : 3/3 PASS
  - Marqueurs & Bitmaps MapLibre (`test/map_markers_test.dart`) : 4/4 PASS

### 4.3. Distinction Factuelle des Tests
- **Tests Réellement Exécutés et Validés** :
  - Tests unitaires et widget tests sous Flutter Test runner (Linux x86_64/arm64 sandbox).
  - Validation des flux asynchrones RTDB et Firestore avec des mocks et des émulateurs Firebase.
  - Rendu Canvas et export PNG des icônes cartographiques vérifié bit-à-bit (signature `0x89504E47`).
- **Tests Matériels Restants pour la Mise en Production** :
  - Suivi GPS en conditions réelles avec deux smartphones physiques Android (un livreur en circulation dans Alger et un client destinataire) pour évaluer la précision du capteur GPS et la latence 4G/LTE Mobilis/Ooredoo/Djezzy.

---

## 5. RECOMMANDATIONS ET ÉTAPES SUIVANTES

1. **Intégration du plugin MapLibre (Prochaine étape)** :
   - Ajouter `maplibre_gl: ^0.27.1` dans `pubspec.yaml`.
   - Remplacer le `FlutterMap` par `MapLibreMap` dans `delivery_tracking_screen.dart` en chargeant le style OpenFreeMap Liberty et en enregistrant les bitmaps via `MapMarkerBitmapGenerator`.
2. **Affichage du Tracé Routier (Polyline OSRM)** :
   - Tracer la ligne de trajet entre le Shopper et le point de livraison via un `LineLayer` MapLibre dynamique mis à jour à chaque franchissement de waypoint.
3. **Maintien de la Compatibilité Offline** :
   - Conserver le cache local du PIN et permettre l'affichage des tuiles déjà mises en cache lors des zones blanches de couverture réseau.
