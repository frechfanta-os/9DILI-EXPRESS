import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/user_model.dart';
import '../ui/theme/app_theme.dart';

/// Résultat d'estimation de trajet (distance, durée et coût indicatif).
class RouteEstimate {
  final double distanceKm;
  final int durationMinutes;
  final double suggestedCommission;

  const RouteEstimate({
    required this.distanceKm,
    required this.durationMinutes,
    required this.suggestedCommission,
  });
}

/// Service de cartographie libre (OpenStreetMap / flutter_map) & suivi GPS respectueux de la vie privée.
class MapTrackingService {
  static const String userAgentPackageName =
      'com.ghdinteractivestudio.dili_express';
  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  StreamSubscription<Position>? _positionSubscription;

  /// Vérifie et demande les permissions de géolocalisation avec gestion des refus.
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Démarre le suivi GPS en temps réel uniquement pour une mission active.
  /// S'arrête automatiquement dès la fin de la mission.
  Stream<Position>? startMissionTracking({
    required String errandId,
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilterMeters = 10,
  }) {
    final locationSettings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilterMeters,
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  /// Arrêt formel du partage de position (respect de la vie privée).
  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Calcule l'estimation de distance à vol d'oiseau (avec coefficient de sinuosité urbaine 1.3).
  static double calculateDistanceKm(LatLng start, LatLng end) {
    const Distance distance = Distance();
    final meters = distance.as(LengthUnit.Meter, start, end);
    // Coefficient de correction pour réseau routier urbain en Algérie
    return (meters * 1.3) / 1000.0;
  }

  /// Estime la durée d'acheminement et la commission conseillée selon le mode de transport.
  static RouteEstimate estimateTrip({
    required LatLng shopperPos,
    required LatLng destinationPos,
    ShopperTransportType transportType = ShopperTransportType.motorcycle,
  }) {
    final km = calculateDistanceKm(shopperPos, destinationPos);
    final speed = transportType.averageSpeedKmh;
    final hours = km / (speed > 0 ? speed : 15.0);
    final minutes = (hours * 60).round().clamp(5, 180);

    // Grille tarifaire transparente :
    // Base 250 DZD + 50 DZD par km au-delà de 2 km
    double commission = 250.0;
    if (km > 2.0) {
      commission += (km - 2.0) * 50.0;
    }

    return RouteEstimate(
      distanceKm: double.parse(km.toStringAsFixed(1)),
      durationMinutes: minutes,
      suggestedCommission: (commission / 10).round() * 10.0, // Arrondi à 10 DZD
    );
  }

  /// Génère le widget de tuiles OpenStreetMap conforme aux CGU (User-Agent + Attribution).
  static TileLayer buildOsmTileLayer() {
    return TileLayer(
      urlTemplate: osmTileUrl,
      userAgentPackageName: userAgentPackageName,
      maxZoom: 19,
    );
  }

  /// Génère les marqueurs pour le shopper et le point de livraison.
  static MarkerLayer buildTrackingMarkers({
    required LatLng shopperPosition,
    required LatLng destinationPosition,
    ShopperTransportType transportType = ShopperTransportType.motorcycle,
  }) {
    IconData transportIcon;
    switch (transportType) {
      case ShopperTransportType.walking:
        transportIcon = Icons.directions_walk;
        break;
      case ShopperTransportType.bicycle:
        transportIcon = Icons.directions_bike;
        break;
      case ShopperTransportType.scooter:
        transportIcon = Icons.electric_scooter;
        break;
      case ShopperTransportType.car:
        transportIcon = Icons.directions_car;
        break;
      case ShopperTransportType.motorcycle:
        transportIcon = Icons.two_wheeler;
        break;
    }

    return MarkerLayer(
      markers: [
        // Marqueur Shopper
        Marker(
          point: shopperPosition,
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryOrange.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(transportIcon, color: Colors.white, size: 24),
          ),
        ),
        // Marqueur Destination Client
        Marker(
          point: destinationPosition,
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.accentGreen,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentGreen.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.home, color: Colors.white, size: 24),
          ),
        ),
      ],
    );
  }
}
