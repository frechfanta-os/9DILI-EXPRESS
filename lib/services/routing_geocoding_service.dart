import 'dart:math';

/// Modèle générique de coordonnées géographiques pour le routage et le géocodage.
class GeoCoordinate {
  final double latitude;
  final double longitude;

  const GeoCoordinate({
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() => 'GeoCoordinate($latitude, $longitude)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoCoordinate &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Résultat d'un calcul d'itinéraire routier.
class RouteResult {
  final double distanceMeters;
  final double durationSeconds;
  final List<GeoCoordinate> geometryPoints;
  final String providerName;
  final String attributionNotice;
  final bool isFallbackEstimation;

  const RouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.geometryPoints,
    required this.providerName,
    required this.attributionNotice,
    this.isFallbackEstimation = false,
  });

  /// Distance formatée en kilomètres ou mètres.
  String get formattedDistance {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.toStringAsFixed(0)} m';
  }

  /// Durée formatée en minutes.
  String get formattedDuration {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 1) return '< 1 min';
    return '$minutes min';
  }
}

/// Résultat d'un géocodage ou d'une recherche d'adresse.
class GeocodingResult {
  final String displayName;
  final GeoCoordinate coordinate;
  final String? street;
  final String? city;
  final String? state;
  final String? country;
  final String providerName;

  const GeocodingResult({
    required this.displayName,
    required this.coordinate,
    this.street,
    this.city,
    this.state,
    this.country,
    required this.providerName,
  });
}

/// Contrat d'interface abstrait pour le routage (Shopper -> Client).
/// Permet d'interchanger le moteur (OSRM, Valhalla, OpenRouteService, Cloudflare R2 PMTiles)
/// sans impacter l'interface utilisateur.
///
/// NOTE CRITIQUE DE PRODUCTION :
/// Les serveurs de démonstration publics (comme router.project-osrm.org) sont réservés aux tests
/// et prototypes. Ils ne disposent d'aucun SLA garanti pour la production commerciale 9DILI EXPRESS.
abstract class RoutingService {
  /// Calcule l'itinéraire routier entre l'origine et la destination.
  Future<RouteResult?> calculateRoute({
    required GeoCoordinate origin,
    required GeoCoordinate destination,
  });
}

/// Contrat d'interface abstrait pour le géocodage et la recherche d'adresses.
///
/// NOTE CRITIQUE DE PRODUCTION :
/// Les API publiques (Nominatim, Photon) sont soumises à des politiques strictes de fair-use
/// (ex: max 1 req/sec pour OSM). Un service dédié ou un cache local est requis en production.
abstract class GeocodingService {
  /// Recherche des lieux ou adresses par mots-clés.
  Future<List<GeocodingResult>> searchAddress(
    String query, {
    GeoCoordinate? proximityCenter,
  });

  /// Résolution d'adresse à partir de coordonnées GPS (Reverse geocoding).
  Future<GeocodingResult?> reverseGeocode(GeoCoordinate coordinate);
}

/// Implémentation de démonstration locale et résiliente pour tests et prototypes.
/// Calcule une estimation géodésique directe (formule Haversine) sans aucun appel réseau.
class FallbackLocalRoutingService implements RoutingService {
  @override
  Future<RouteResult?> calculateRoute({
    required GeoCoordinate origin,
    required GeoCoordinate destination,
  }) async {
    // Calcul de distance géodésique directe (Haversine)
    const earthRadiusMeters = 6371000.0;
    final dLat = (destination.latitude - origin.latitude) * (pi / 180.0);
    final dLon = (destination.longitude - origin.longitude) * (pi / 180.0);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(origin.latitude * (pi / 180.0)) *
            cos(destination.latitude * (pi / 180.0)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final directDistance = earthRadiusMeters * c;

    // Facteur d'encombrement urbain approximatif (1.3x la ligne droite)
    final estimatedDistance = directDistance * 1.3;
    // Vitesse moyenne en scooter urbain à Alger : ~25 km/h (~6.94 m/s)
    final estimatedDuration = estimatedDistance / 6.94;

    return RouteResult(
      distanceMeters: estimatedDistance,
      durationSeconds: estimatedDuration,
      geometryPoints: [origin, destination],
      providerName: 'Estimation Locale Résiliente (Offline Fallback)',
      attributionNotice: 'Calcul local estimatif — Aucun appel réseau',
      isFallbackEstimation: true,
    );
  }
}
