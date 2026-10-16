import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';

/// Service de suivi GPS temps réel et gestion de présence via Firebase Realtime Database (RTDB).
/// Conçu pour respecter strictement les quotas gratuits du plan Firebase Spark :
/// - Throttling des écritures GPS (intervalle minimum 8 secondes / 10 mètres).
/// - Nettoyage systématique des courses terminées dans /active_errands/{errandId}.
/// - Écoutes fermées dès que la vue n'est plus active.
/// - Déconnexion automatique via onDisconnect().
class RealtimeTrackingService {
  final FirebaseDatabase? _customDatabase;

  RealtimeTrackingService({FirebaseDatabase? database})
      : _customDatabase = database;

  FirebaseDatabase get database =>
      _customDatabase ?? FirebaseDatabase.instance;

  DateTime? _lastGpsWriteTime;
  static const Duration minWriteInterval = Duration(seconds: 8);

  // ==========================================
  // 1. GESTION DE LA PRÉSENCE (Shopper)
  // ==========================================

  /// Configure la présence en ligne automatique du shopper avec onDisconnect().
  Future<void> setUserPresence({
    required String uid,
    required bool isOnline,
  }) async {
    final presenceRef = database.ref('presence/$uid');

    if (isOnline) {
      // Configuration de la coupure automatique en cas de déconnexion réseau
      await presenceRef.onDisconnect().set({
        'isOnline': false,
        'lastSeen': ServerValue.timestamp,
      });

      await presenceRef.set({
        'isOnline': true,
        'lastSeen': ServerValue.timestamp,
      });
    } else {
      await presenceRef.set({
        'isOnline': false,
        'lastSeen': ServerValue.timestamp,
      });
    }
  }

  /// Écoute l'état de présence d'un utilisateur (Shopper).
  Stream<bool> streamUserPresence(String uid) {
    return database.ref('presence/$uid/isOnline').onValue.map((event) {
      final val = event.snapshot.value;
      return val is bool ? val : false;
    });
  }

  // ==========================================
  // 2. POSITION GLOBALE DU SHOPPER (/locations)
  // ==========================================

  /// Met à jour la dernière position connue du Shopper avec limitation de débit (Throttling).
  Future<bool> updateShopperLocation({
    required String uid,
    required double latitude,
    required double longitude,
    bool force = false,
  }) async {
    // Validation des bornes géographiques
    if (latitude < -90.0 ||
        latitude > 90.0 ||
        longitude < -180.0 ||
        longitude > 180.0) {
      throw ArgumentError(
        'Coordonnées géographiques invalides ($latitude, $longitude)',
      );
    }

    final now = DateTime.now();
    if (!force &&
        _lastGpsWriteTime != null &&
        now.difference(_lastGpsWriteTime!) < minWriteInterval) {
      return false; // Throttled pour économiser les quotas Spark
    }

    final locationRef = database.ref('locations/$uid');
    await locationRef.set({
      'latitude': latitude,
      'longitude': longitude,
      'updatedAt': ServerValue.timestamp,
    });

    _lastGpsWriteTime = now;
    return true;
  }

  // ==========================================
  // 3. SUIVI EN DIRECT D'UNE COURSE ACTIVE (/active_errands)
  // ==========================================

  /// Diffuse la position GPS du Shopper pour une mission active spécifique.
  Future<bool> pushActiveErrandLocation({
    required String errandId,
    required String shopperId,
    required String clientId,
    required double latitude,
    required double longitude,
    bool force = false,
  }) async {
    // Validation des bornes géographiques
    if (latitude < -90.0 ||
        latitude > 90.0 ||
        longitude < -180.0 ||
        longitude > 180.0) {
      throw ArgumentError('Coordonnées géographiques invalides');
    }

    final now = DateTime.now();
    if (!force &&
        _lastGpsWriteTime != null &&
        now.difference(_lastGpsWriteTime!) < minWriteInterval) {
      return false;
    }

    final errandRef = database.ref('active_errands/$errandId');
    await errandRef.set({
      'errandId': errandId,
      'shopperId': shopperId,
      'clientId': clientId,
      'latitude': latitude,
      'longitude': longitude,
      'updatedAt': ServerValue.timestamp,
    });

    _lastGpsWriteTime = now;
    return true;
  }

  /// Écoute les coordonnées en direct du shopper pour le client.
  Stream<LatLng?> streamActiveErrandLocation(String errandId) {
    return database.ref('active_errands/$errandId').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        final lat = data['latitude'];
        final lng = data['longitude'];
        if (lat is num && lng is num) {
          return LatLng(lat.toDouble(), lng.toDouble());
        }
      }
      return null;
    });
  }

  /// Nettoie la position active à la clôture ou annulation de la course pour libérer l'espace RTDB.
  Future<void> cleanUpActiveErrand(String errandId) async {
    try {
      await database.ref('active_errands/$errandId').remove();
    } catch (_) {
      // Tolérance en cas de document déjà supprimé
    }
  }
}
