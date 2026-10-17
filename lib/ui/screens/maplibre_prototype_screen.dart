import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../../services/routing_geocoding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/map_markers.dart';

/// Statut de cycle de vie du prototype cartographique.
enum MapLoadState {
  loading,
  ready,
  error,
}

/// Écran prototype isolé MapLibre Native pour 9DILI EXPRESS.
/// Totalement indépendant du flux de livraison de production.
///
/// Spécifications :
/// - Style vectoriel : OpenFreeMap Liberty ("https://tiles.openfreemap.org/styles/liberty").
/// - Position de test configurable par défaut : Alger Centre (36.7538° N, 3.0588° E).
/// - Aucun recours à la géolocalisation précise sans consentement explicite.
/// - Attribution cartographique légale ODbL/OpenFreeMap systématiquement visible.
/// - Architecture réversible et découplée avec injection optionnelle de [RoutingService].
class MapLibrePrototypeScreen extends StatefulWidget {
  /// URL publique du style vectoriel OpenFreeMap.
  static const String openFreeMapLibertyStyle =
      'https://tiles.openfreemap.org/styles/liberty';

  /// Coordonnées de test par défaut (Grande Poste, Alger).
  static const GeoCoordinate defaultTestLocation = GeoCoordinate(
    latitude: 36.7725,
    longitude: 3.0588,
  );

  /// Position de destination de test (Didouche Mourad, Alger).
  static const GeoCoordinate defaultTestDestination = GeoCoordinate(
    latitude: 36.7645,
    longitude: 3.0535,
  );

  final String styleString;
  final GeoCoordinate initialLocation;
  final RoutingService? routingService;

  /// Builder alternatif pour les tests unitaires/widget tests headless sans NDK.
  final Widget Function(BuildContext context, MapLibrePrototypeState state)?
      mapBuilder;

  const MapLibrePrototypeScreen({
    super.key,
    this.styleString = openFreeMapLibertyStyle,
    this.initialLocation = defaultTestLocation,
    this.routingService,
    this.mapBuilder,
  });

  @override
  State<MapLibrePrototypeScreen> createState() => MapLibrePrototypeState();
}

class MapLibrePrototypeState extends State<MapLibrePrototypeScreen> {
  maplibre.MapLibreMapController? _mapController;

  MapLoadState _loadState = MapLoadState.loading;
  String? _errorMessage;

  bool _showCustomMarkers = true;
  double _currentZoom = 13.5;
  late GeoCoordinate _currentCenter;
  late final RoutingService _routingService;

  RouteResult? _estimatedRoute;
  bool _isEstimatingRoute = false;

  MapLoadState get loadState => _loadState;
  String? get errorMessage => _errorMessage;
  bool get showCustomMarkers => _showCustomMarkers;
  double get currentZoom => _currentZoom;
  GeoCoordinate get currentCenter => _currentCenter;
  RouteResult? get estimatedRoute => _estimatedRoute;

  @override
  void initState() {
    super.initState();
    _currentCenter = widget.initialLocation;
    _routingService = widget.routingService ?? FallbackLocalRoutingService();

    // En environnement de test avec custom builder, l'état peut être basculé par le test
    if (widget.mapBuilder != null) {
      _loadState = MapLoadState.ready;
    }
  }

  /// Déclenche une nouvelle tentative de chargement.
  void retryLoading() {
    setState(() {
      _loadState = MapLoadState.loading;
      _errorMessage = null;
    });
  }

  /// Force un état d'erreur pour les tests et la résilience.
  void simulateError(String message) {
    setState(() {
      _loadState = MapLoadState.error;
      _errorMessage = message;
    });
  }

  /// Bascule la visibilité des marqueurs de test.
  void toggleMarkers() {
    setState(() {
      _showCustomMarkers = !_showCustomMarkers;
    });
  }

  /// Zoom avant sur la carte.
  void zoomIn() {
    setState(() {
      _currentZoom = (_currentZoom + 1.0).clamp(1.0, 20.0);
    });
    _mapController?.animateCamera(
      maplibre.CameraUpdate.zoomTo(_currentZoom),
    );
  }

  /// Zoom arrière sur la carte.
  void zoomOut() {
    setState(() {
      _currentZoom = (_currentZoom - 1.0).clamp(1.0, 20.0);
    });
    _mapController?.animateCamera(
      maplibre.CameraUpdate.zoomTo(_currentZoom),
    );
  }

  /// Calcule une estimation locale résiliente sans appel réseau externe.
  Future<void> calculateEstimatedDistance() async {
    setState(() => _isEstimatingRoute = true);
    try {
      final result = await _routingService.calculateRoute(
        origin: _currentCenter,
        destination: MapLibrePrototypeScreen.defaultTestDestination,
      );
      if (mounted) {
        setState(() {
          _estimatedRoute = result;
          _isEstimatingRoute = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isEstimatingRoute = false);
      }
    }
  }

  /// Callback déclenché lors de la création du contrôleur natif MapLibre.
  void onMapCreated(maplibre.MapLibreMapController controller) {
    _mapController = controller;
  }

  /// Callback déclenché dès que le style JSON et les tuiles vectorielles sont prêts.
  Future<void> onStyleLoaded() async {
    if (!mounted) return;

    try {
      // Enregistrement des icônes 3D importées depuis assets avec fallback Canvas
      final shopperBytes =
          await MapMarkerBitmapGenerator.loadAssetMarkerBytes(
        MapMarkerAssets.shopperOrange3D01,
        isShopper: true,
      );
      final destBytes =
          await MapMarkerBitmapGenerator.loadAssetMarkerBytes(
        MapMarkerAssets.destinationGreen3D06,
        isShopper: false,
      );

      if (_mapController != null) {
        await _mapController!.addImage('shopper_icon', shopperBytes);
        await _mapController!.addImage('destination_icon', destBytes);
      }

      setState(() {
        _loadState = MapLoadState.ready;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _loadState = MapLoadState.ready; // Carte prête même si l'icône échoue
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prototype MapLibre (Isolé)'),
        actions: [
          IconButton(
            tooltip: 'Basculer Marqueurs',
            icon: Icon(
              _showCustomMarkers ? Icons.layers : Icons.layers_clear,
              color: AppTheme.primaryOrange,
            ),
            onPressed: toggleMarkers,
          ),
          IconButton(
            tooltip: 'Réinitialiser Vue',
            icon: const Icon(Icons.refresh),
            onPressed: retryLoading,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Moteur cartographique (MapLibre Native ou builder de test)
          if (widget.mapBuilder != null)
            widget.mapBuilder!(context, this)
          else
            maplibre.MapLibreMap(
              styleString: widget.styleString,
              initialCameraPosition: maplibre.CameraPosition(
                target: maplibre.LatLng(
                  _currentCenter.latitude,
                  _currentCenter.longitude,
                ),
                zoom: _currentZoom,
              ),
              onMapCreated: onMapCreated,
              onStyleLoadedCallback: onStyleLoaded,
              myLocationEnabled: false, // Pas d'accès GPS intrusif
              attributionButtonMargins: const Point(-100, -100), // Géré dans l'UI Stitch
            ),

          // 2. Marqueurs personnalisés en superposition interactive
          if (_loadState == MapLoadState.ready && _showCustomMarkers)
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Shopper3DMarkerWidget(
                    heading: 35.0,
                    size: 56.0,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceWhite,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Text(
                      'Shopper Test (Alger Centre)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 3. État de chargement explicite
          if (_loadState == MapLoadState.loading)
            Container(
              color: AppTheme.backgroundLight.withValues(alpha: 0.85),
              child: Center(
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: AppTheme.primaryOrange,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Chargement d\'OpenFreeMap Liberty...',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tuiles vectorielles Algérie via openfreemap.org',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 4. État d'erreur explicite et bouton de réessai
          if (_loadState == MapLoadState.error)
            Container(
              color: AppTheme.backgroundLight.withValues(alpha: 0.95),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            size: 48,
                            color: AppTheme.errorRed,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Échec du chargement de la carte',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _errorMessage ??
                                'Impossible de récupérer les tuiles OpenFreeMap. Vérifiez votre connexion Internet.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryOrange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: retryLoading,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 5. Bannière informative : Environnement Prototype Isolé
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.secondaryNavy.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.science_rounded,
                    color: AppTheme.primaryOrange,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PROTOTYPE MAPLIBRE ISOLÉ — Parcours de prod non impacté',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 6. Panneau d'estimation locale et contrôles
          Positioned(
            bottom: 40,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceWhite,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_estimatedRoute != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Distance : ${_estimatedRoute!.formattedDistance}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Durée : ${_estimatedRoute!.formattedDuration}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _estimatedRoute!.attributionNotice,
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.violetAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isEstimatingRoute
                        ? null
                        : calculateEstimatedDistance,
                    icon: _isEstimatingRoute
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.straighten_rounded, size: 16),
                    label: const Text(
                      'Calculer estimation locale (Offline Fallback)',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 7. Bandeau légal d'attribution obligatoire
          Positioned(
            bottom: 6,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '© OpenStreetMap contributors • OpenFreeMap • MapLibre GL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
