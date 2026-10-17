import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/errand_service.dart';
import '../../services/map_tracking_service.dart';
import '../../services/product_catalog_service.dart';
import '../../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/map_markers.dart';
import 'create_errand_screen.dart';

/// Radar Géographique Client ↔ Shoppers en temps réel.
/// Affiche la position GPS du client, les shoppers disponibles (fraîcheur <= 120s),
/// et implémente la recherche par vagues progressives (2 km -> 5 km -> 8 km -> 11 km -> 14 km).
class ClientRadarScreen extends StatefulWidget {
  final UserModel currentUser;
  final UserService userService;
  final ErrandService errandService;
  final AuthService authService;
  final ProductCatalogService? catalogService;
  final LatLng? initialClientLocation;

  const ClientRadarScreen({
    super.key,
    required this.currentUser,
    required this.userService,
    required this.errandService,
    required this.authService,
    this.catalogService,
    this.initialClientLocation,
  });

  @override
  State<ClientRadarScreen> createState() => _ClientRadarScreenState();
}

class _ClientRadarScreenState extends State<ClientRadarScreen>
    with SingleTickerProviderStateMixin {
  static const List<double> progressiveWaves = [2.0, 5.0, 8.0, 11.0, 14.0];
  static const int waveIntervalSeconds = 15;
  static const int maxShoppersDisplayed = 10;

  final MapController _mapController = MapController();

  LatLng? _clientPosition;
  bool _isLoadingGps = true;
  String? _gpsError;

  int _currentWaveIndex = 0;
  int _secondsUntilNextWave = waveIntervalSeconds;
  Timer? _waveTimer;
  Timer? _countdownTimer;

  UserModel? _selectedShopper;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _initClientLocation();
    _startWaveProgression();
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  double get currentRadiusKm => progressiveWaves[_currentWaveIndex];

  Future<void> _initClientLocation() async {
    if (widget.initialClientLocation != null) {
      setState(() {
        _clientPosition = widget.initialClientLocation;
        _isLoadingGps = false;
      });
      return;
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsError = 'Service de localisation désactivé sur le téléphone.';
          _isLoadingGps = false;
          _clientPosition = const LatLng(
            36.7538,
            3.0588,
          ); // Alger centre fallback
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _gpsError = 'Permission de localisation refusée.';
            _isLoadingGps = false;
            _clientPosition = const LatLng(36.7538, 3.0588);
          });
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );

      if (mounted) {
        setState(() {
          _clientPosition = LatLng(pos.latitude, pos.longitude);
          _isLoadingGps = false;
        });
        _mapController.move(_clientPosition!, 14.0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gpsError = 'Signal GPS introuvable. Position par défaut Alger.';
          _isLoadingGps = false;
          _clientPosition = const LatLng(36.7538, 3.0588);
        });
      }
    }
  }

  void _startWaveProgression() {
    _waveTimer?.cancel();
    _countdownTimer?.cancel();
    _secondsUntilNextWave = waveIntervalSeconds;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsUntilNextWave > 1) {
        setState(() => _secondsUntilNextWave--);
      } else {
        _secondsUntilNextWave = waveIntervalSeconds;
      }
    });

    _waveTimer = Timer.periodic(const Duration(seconds: waveIntervalSeconds), (
      timer,
    ) {
      if (!mounted) return;
      if (_currentWaveIndex < progressiveWaves.length - 1) {
        setState(() {
          _currentWaveIndex++;
        });
      }
    });
  }

  void _resetRadarWaves() {
    setState(() {
      _currentWaveIndex = 0;
      _secondsUntilNextWave = waveIntervalSeconds;
      _selectedShopper = null;
    });
    _startWaveProgression();
  }

  void _selectShopper(UserModel shopper) {
    setState(() {
      _selectedShopper = shopper;
    });
    if (shopper.location != null) {
      _mapController.move(
        LatLng(shopper.location!.latitude, shopper.location!.longitude),
        15.0,
      );
    }
  }

  void _launchErrandWithShopper(UserModel? preferredShopper) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateErrandScreen(
          clientId: widget.currentUser.uid,
          errandService: widget.errandService,
          catalogService: widget.catalogService,
          initialAddress: 'Position GPS Radar Client',
          initialStoreName: preferredShopper != null
              ? 'Course confiée en priorité à ${preferredShopper.fullName}'
              : null,
        ),
      ),
    );
  }

  bool _isShopperFresh(UserModel shopper) {
    if (shopper.updatedAt == null) return true;
    final diffSeconds = DateTime.now()
        .difference(shopper.updatedAt!)
        .inSeconds
        .abs();
    return diffSeconds <= 120;
  }

  @override
  Widget build(BuildContext context) {
    final clientLatLng = _clientPosition ?? const LatLng(36.7538, 3.0588);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.radar, color: AppTheme.primaryOrange),
            SizedBox(width: 8),
            Text('Radar Shoppers 📡'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Réinitialiser la recherche',
            icon: const Icon(Icons.refresh),
            onPressed: _resetRadarWaves,
          ),
        ],
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: widget.userService.streamAvailableShoppers(),
        builder: (context, snapshot) {
          final rawShoppers = snapshot.data ?? [];

          // 1. Filtrer les shoppers : position non nulle + fraîcheur <= 120s
          final eligibleShoppers = rawShoppers.where((s) {
            if (s.location == null) return false;
            return _isShopperFresh(s);
          }).toList();

          // 2. Calculer la distance et filtrer par rayon de vague progressive
          final List<MapEntry<UserModel, double>> shoppersWithDistance = [];
          for (final s in eligibleShoppers) {
            final shopperPos = LatLng(
              s.location!.latitude,
              s.location!.longitude,
            );
            final distKm = MapTrackingService.calculateDistanceKm(
              clientLatLng,
              shopperPos,
            );
            if (distKm <= currentRadiusKm) {
              shoppersWithDistance.add(MapEntry(s, distKm));
            }
          }

          // 3. Trier par distance croissante et limiter aux 10 plus proches
          shoppersWithDistance.sort((a, b) => a.value.compareTo(b.value));
          final displayedShoppers = shoppersWithDistance
              .take(maxShoppersDisplayed)
              .toList();

          return Stack(
            children: [
              // 1. CARTE FLUTTER_MAP
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: clientLatLng,
                  initialZoom: 13.5,
                  minZoom: 9.0,
                  maxZoom: 18.0,
                ),
                children: [
                  MapTrackingService.buildOsmTileLayer(),

                  // Cercle de rayon de recherche de la vague active
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: clientLatLng,
                        radius: currentRadiusKm * 1000,
                        useRadiusInMeter: true,
                        color: AppTheme.primaryOrange.withValues(alpha: 0.08),
                        borderColor: AppTheme.primaryOrange.withValues(
                          alpha: 0.5,
                        ),
                        borderStrokeWidth: 2.0,
                      ),
                    ],
                  ),

                  // Marqueurs des Shoppers
                  MarkerLayer(
                    markers: [
                      // Marqueur Client
                      Marker(
                        point: clientLatLng,
                        width: 50,
                        height: 50,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 44 + (_pulseController.value * 12),
                                  height: 44 + (_pulseController.value * 12),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.accentGreen.withValues(
                                      alpha:
                                          (1.0 - _pulseController.value) * 0.4,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.2,
                                        ),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.person_pin_circle,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      // Marqueurs Shoppers
                      ...displayedShoppers.map((entry) {
                        final shopper = entry.key;
                        final isSelected = _selectedShopper?.uid == shopper.uid;
                        final pos = LatLng(
                          shopper.location!.latitude,
                          shopper.location!.longitude,
                        );

                        return Marker(
                          point: pos,
                          width: 48,
                          height: 48,
                          child: GestureDetector(
                            onTap: () => _selectShopper(shopper),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (isSelected)
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppTheme.primaryOrange,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                const ShopperMarkerWidget(size: 40),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ),

              // 2. BANDEAU HAUT : ÉTAT DU RADAR, VAGUE ET COMPTEUR
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: Colors.white.withValues(alpha: 0.95),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryOrange.withValues(
                                      alpha: 0.15,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.radar,
                                    color: AppTheme.primaryOrange,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Rayon : ${currentRadiusKm.toStringAsFixed(0)} km (Vague ${_currentWaveIndex + 1}/${progressiveWaves.length})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      _isLoadingGps
                                          ? 'Acquisition du signal GPS...'
                                          : displayedShoppers.isEmpty
                                          ? 'Recherche en cours... (Prochaine vague : ${_secondsUntilNextWave}s)'
                                          : '${displayedShoppers.length} shoppeur(s) détecté(s) <= 120s',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            _isLoadingGps ||
                                                displayedShoppers.isEmpty
                                            ? AppTheme.warningOrange
                                            : AppTheme.accentGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // Bouton expansion manuelle
                            if (_currentWaveIndex < progressiveWaves.length - 1)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _currentWaveIndex++;
                                    _secondsUntilNextWave = waveIntervalSeconds;
                                  });
                                },
                                icon: const Icon(Icons.zoom_out_map, size: 14),
                                label: const Text(
                                  'Élargir',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                        if (_gpsError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _gpsError!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.errorRed,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // 3. BANDEAU BAS : SHOPPERS DÉTECTÉS OU ÉTAT VIDE
              Positioned(
                bottom: 16,
                left: 12,
                right: 12,
                child: displayedShoppers.isEmpty
                    ? _buildEmptyShopperCard()
                    : _buildShopperCarousel(displayedShoppers),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyShopperCard() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.primaryOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aucun Shopper disponible dans un rayon de ${currentRadiusKm.toStringAsFixed(0)} km.',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Le Radar élargit automatiquement la zone toutes les 15 secondes (jusqu\'à 14 km). Vous pouvez également créer votre commande maintenant pour être averti dès qu\'un shoppeur se connecte.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                minimumSize: const Size.fromHeight(42),
              ),
              onPressed: () => _launchErrandWithShopper(null),
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: const Text('Créer ma course sur le Radar 🚀'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopperCarousel(
    List<MapEntry<UserModel, double>> displayedShoppers,
  ) {
    final activeShopper = _selectedShopper ?? displayedShoppers.first.key;
    final activeDist = displayedShoppers
        .firstWhere(
          (e) => e.key.uid == activeShopper.uid,
          orElse: () => displayedShoppers.first,
        )
        .value;

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.primaryOrange,
                      radius: 20,
                      child: Text(
                        activeShopper.fullName.isNotEmpty
                            ? activeShopper.fullName[0].toUpperCase()
                            : 'S',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeShopper.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 14,
                            ),
                            Text(
                              ' ${activeShopper.rating.toStringAsFixed(1)} • ${activeShopper.transport.labelFr}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${activeDist.toStringAsFixed(1)} km',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppTheme.accentGreen,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Sélecteur horizontal de shoppers si plusieurs disponibles
            if (displayedShoppers.length > 1) ...[
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: displayedShoppers.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, idx) {
                    final s = displayedShoppers[idx].key;
                    final dist = displayedShoppers[idx].value;
                    final isSel = s.uid == activeShopper.uid;

                    return ChoiceChip(
                      selected: isSel,
                      label: Text(
                        '${s.fullName.split(' ').first} (${dist.toStringAsFixed(1)} km)',
                        style: TextStyle(
                          fontSize: 11,
                          color: isSel ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                      selectedColor: AppTheme.violetAccent,
                      onSelected: (_) => _selectShopper(s),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _launchErrandWithShopper(activeShopper),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                'Commander avec ${activeShopper.fullName.split(' ').first} 🚀',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
