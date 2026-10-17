# RAPPORT D'ÉTAPE — PROTOTYPE CARTOGRAPHIQUE MAPLIBRE ISOLÉ (PHASE 1)
**Projet :** 9DILI EXPRESS  
**Application ID :** `com.ghdinteractivestudio.dili_express`  
**Environnement :** Flutter 3.47.7 • Dart 3.13.5 • Android SDK 34 / minSdk 23 • Java 17 OpenJDK  
**Commit de référence :** `36e5c3d`  
**Branche :** `main`  
**Date :** 16 Octobre 2026  

---

## 1. SYNTHÈSE DES OBJECTIFS ET CONTRAINTES

Dans le respect strict du mandat, un **prototype MapLibre minimal, indépendant et réversible** a été implémenté sans impacter le parcours de livraison existant :
- **Parcours de production inchangé** : L'écran de production [`DeliveryTrackingScreen`](file:///root/dili_express/lib/ui/screens/delivery_tracking_screen.dart) continue d'opérer avec son suivi GPS temps réel RTDB (throttlé à 8s) sans régression.
- **Prototype isolé** : Création d'un écran dédié [`MapLibrePrototypeScreen`](file:///root/dili_express/lib/ui/screens/maplibre_prototype_screen.dart) chargeant le style vectoriel OpenFreeMap Liberty.
- **Contrat de routage et de géocodage** : Mise en place d'une interface abstraite [`RoutingService`](file:///root/dili_express/lib/services/routing_geocoding_service.dart) et [`GeocodingService`](file:///root/dili_express/lib/services/routing_geocoding_service.dart) avec estimation locale résiliente sans appel réseau externe obligatoire.
- **Règle Git respectée** : Aucun commit ni push sur `main` n'a été effectué avant validation formelle.

---

## 2. FICHIERS CRÉÉS ET MODIFIÉS

### Fichiers Modifiés
1. [`pubspec.yaml`](file:///root/dili_express/pubspec.yaml) :
   - Ajout de la dépendance vectorielle : `maplibre_gl: ^0.27.1`.
2. [`pubspec.lock`](file:///root/dili_express/pubspec.lock) :
   - Résolution des paquets : `maplibre_gl (0.27.1)`, `maplibre_gl_platform_interface (0.27.1)`, `maplibre_gl_web (0.27.1)`, `image (4.12.0)`.

### Fichiers Créés
1. [`lib/services/routing_geocoding_service.dart`](file:///root/dili_express/lib/services/routing_geocoding_service.dart) :
   - Contrat d'interface abstrait pour le routage et le géocodage.
   - Modèles `GeoCoordinate`, `RouteResult`, `GeocodingResult`.
   - Implémentation `FallbackLocalRoutingService` calculant une distance géodésique directe (Haversine) sans aucun appel réseau.
2. [`lib/ui/screens/maplibre_prototype_screen.dart`](file:///root/dili_express/lib/ui/screens/maplibre_prototype_screen.dart) :
   - Écran prototype indépendant avec bannière d'environnement de test isolé.
   - Chargement du style OpenFreeMap Liberty (`https://tiles.openfreemap.org/styles/liberty`).
   - Centrage sur Alger Centre (`36.7725° N, 3.0588° E`) sans accès intrusif au GPS physique.
   - Gestion d'état robuste : `loading` (spinner explicite), `error` (message explicite et bouton de réessai `retryLoading()`), et `ready`.
   - Superposition des marqueurs Shopper et Client créés dans `map_markers.dart`.
   - Enregistrement des bitmaps générés par Canvas pour le SymbolLayer (`MapMarkerBitmapGenerator`).
   - Bandeau légal d'attribution obligatoire : `© OpenStreetMap contributors • OpenFreeMap • MapLibre GL`.
3. [`test/maplibre_prototype_screen_test.dart`](file:///root/dili_express/test/maplibre_prototype_screen_test.dart) :
   - 5 tests automatisés couvrant le rendu initial, le masquage des marqueurs, la gestion de l'erreur réseau avec réessai et le calcul d'estimation locale.

---

## 3. RÉSULTATS RÉELS DES COMMANDES

### 3.1. Résolution des Dépendances (`flutter pub get`)
```
Resolving dependencies...
+ image 4.12.0
+ maplibre_gl 0.27.1
+ maplibre_gl_platform_interface 0.27.1
+ maplibre_gl_web 0.27.1
Changed 4 dependencies!
```
- Compatibilité validée : Aucune incompatibilité avec `cloud_firestore: ^7.0.0`, `firebase_database: ^13.0.0`, `geolocator: ^14.1.1` ou `flutter_map: ^8.3.2`.

### 3.2. Analyse Statique (`flutter analyze`)
```
Analyzing dili_express...
No issues found! (ran in 28.8s)
```
- Codebase 100% saine : 0 erreur, 0 avertissement, 0 lint d'inattention.

### 3.3. Tests Automatisés (`flutter test`)
```
00:10 +60: All tests passed!
```
- **60/60 tests passés avec succès (100% de réussite)** :
  - Tests unitaires et widget tests de production : 55/55 PASS
  - Nouveaux tests du prototype MapLibre : 5/5 PASS

---

## 4. LIMITES IDENTIFIÉES & RISQUES TECHNIQUES

1. **Fournisseur de tuiles OpenFreeMap** :
   - OpenFreeMap est un service libre et gratuit basé sur Cloudflare / infrastructure communautaire. Bien qu'autorisant l'usage commercial sans clé API ni limitation de requêtes, il n'offre pas de contrat SLA d'entreprise à 99.99%.
2. **APIs Publiques de Routage (OSRM / Photon)** :
   - Les serveurs publics `router.project-osrm.org` et `photon.komoot.io` sont destinés au prototypage et à des usages de faible intensité. L'interface abstraite [`RoutingService`](file:///root/dili_express/lib/services/routing_geocoding_service.dart) a été conçue pour isoler cette dépendance et permettre un basculement transparent.
3. **Exécution des tests en environnement Headless** :
   - Le moteur C++/NDK de MapLibre exige un contexte OpenGL/Vulkan disponible sur smartphone Android réel. Pour préserver la rapidité de la CI et des tests unitaires locaux sans crash de platform-view, [`MapLibrePrototypeScreen`](file:///root/dili_express/lib/ui/screens/maplibre_prototype_screen.dart) dispose d'un paramètre d'injection `mapBuilder` permettant de simuler le cycle de vie de la carte.

---

## 5. CONDITIONS DE REMPLACEMENT DU FOURNISSEUR

En cas de saturation, indisponibilité ou politique restrictive future d'OpenFreeMap, la transition vers une solution souveraine privée s'effectue en une seule ligne de code :
1. **Option Cloudflare R2 + PMTiles (Recommandée & Coût Zéro Egress)** :
   - Hébergement de l'extrait Algérie (`algeria.pmtiles`, ~300 Mo) sur le bucket Cloudflare R2 configuré dans l'environnement (`https://7b2260ba6e6ea12f6271c9e8e78bc391.r2.cloudflarestorage.com`).
   - Remplacement de l'URL du style par l'endpoint R2 privé.
2. **Option Fournisseur Commercial Clé en Main** :
   - MapTiler Cloud ou Stadia Maps : ajout de la clé API dans les paramètres du style JSON sans modifier l'architecture du code Flutter.

---

## 6. CHECKLIST DES TESTS SUR TÉLÉPHONE PHYSIQUE ANDROID

Avant toute migration du parcours principal, les tests suivants doivent être réalisés sur un terminal Android réel :

- [ ] **Chargement initial des tuiles en Algérie** : Vérifier l'affichage complet du réseau routier algérois et des wilayas voisines lors du premier lancement avec connexion 4G.
- [ ] **Interactions tactiles** : Fluidité du pan (déplacement), du pinch-to-zoom (zoom continu) et de la rotation à deux doigts (bearing).
- [ ] **Rendu typographique Arabe & Français** : Contrôle du shaping HarfBuzz pour les noms de rues arabes (ex: شارع ديدوش مراد) et absence de caractères inversés ou isolés.
- [ ] **Coupure et reprise réseau** : Basculer le smartphone en mode Avion puis rétablir la connexion pour valider le bandeau d'erreur et le bouton « Réessayer ».
- [ ] **Consommation mémoire et batterie** : Mesurer l'empreinte mémoire RAM (cible < 120 Mo supplémentaires) et la dissipation thermique lors d'un affichage prolongé de 10 minutes.
- [ ] **Comportement en arrière-plan** : Mettre l'application en arrière-plan puis la réafficher sans perte de contexte GL ni crash OpenGL ES.

---

## 7. STRATÉGIE ET COMMANDES EXACTES DE RETOUR ARRIÈRE

Si le prototype doit être annulé ou retiré sans laisser de trace :

```bash
# 1. Annuler les modifications de pubspec
git restore pubspec.yaml pubspec.lock

# 2. Supprimer les fichiers créés pour le prototype
rm -f lib/services/routing_geocoding_service.dart
rm -f lib/ui/screens/maplibre_prototype_screen.dart
rm -f test/maplibre_prototype_screen_test.dart
rm -f RAPPORT_PROTOTYPE_MAPLIBRE_9DILI_EXPRESS.md

# 3. Réinstaller les dépendances propres
flutter pub get
```

*Le dépôt reviendra instantanément et de façon déterministe à l'état exact du commit `36e5c3d`.*
