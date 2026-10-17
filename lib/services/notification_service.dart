import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Statuts de permission de notification normalisés.
enum AppNotificationPermissionStatus {
  granted,
  provisional,
  denied,
  notDetermined,
}

/// Modèle d'événement de notification métier 9DILI EXPRESS.
class ErrandNotificationPayload {
  final String? errandId;
  final String? eventType;
  final String? newStatus;
  final String? title;
  final String? body;

  const ErrandNotificationPayload({
    this.errandId,
    this.eventType,
    this.newStatus,
    this.title,
    this.body,
  });

  factory ErrandNotificationPayload.fromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    return ErrandNotificationPayload(
      errandId: data['errandId'] ?? data['errand_id'],
      eventType: data['eventType'] ?? data['event_type'],
      newStatus: data['status'],
      title: message.notification?.title ?? data['title'],
      body: message.notification?.body ?? data['body'],
    );
  }
}

/// Service de gestion complète des notifications Firebase Cloud Messaging (FCM)
/// et des autorisations Android 13+ / 14 / 16.
class NotificationService {
  static const String errandUpdatesChannelId = 'errand_updates_channel';
  static const String errandUpdatesChannelName = 'Mises à jour des courses';
  static const String errandUpdatesChannelDescription =
      'Notifications en temps réel pour le suivi et l\'attribution des courses 9DILI EXPRESS';

  final FirebaseMessaging? _customMessaging;
  final FirebaseFirestore? _customFirestore;

  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _customMessaging = messaging,
        _customFirestore = firestore;

  FirebaseMessaging get _messaging =>
      _customMessaging ?? FirebaseMessaging.instance;
  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;

  String? _currentToken;
  String? _currentUserId;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;

  final _foregroundPayloadController =
      StreamController<ErrandNotificationPayload>.broadcast();

  /// Stream des notifications reçues au premier plan.
  Stream<ErrandNotificationPayload> get onForegroundNotification =>
      _foregroundPayloadController.stream;

  String? get currentToken => _currentToken;
  String? get maskedToken {
    if (_currentToken == null || _currentToken!.length < 10) return null;
    return '${_currentToken!.substring(0, 6)}...${_currentToken!.substring(_currentToken!.length - 4)}';
  }

  /// Demande explicite des permissions de notification pour Android 13+ (API 33+) et iOS.
  Future<AppNotificationPermissionStatus> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
          return AppNotificationPermissionStatus.granted;
        case AuthorizationStatus.provisional:
          return AppNotificationPermissionStatus.provisional;
        case AuthorizationStatus.denied:
          return AppNotificationPermissionStatus.denied;
        case AuthorizationStatus.notDetermined:
          return AppNotificationPermissionStatus.notDetermined;
        default:
          return AppNotificationPermissionStatus.denied;
      }
    } catch (_) {
      return AppNotificationPermissionStatus.denied;
    }
  }

  /// Initialise l'enregistrement de l'appareil et l'écoute des messages pour un utilisateur authentifié.
  Future<void> initializeForUser(String userId) async {
    _currentUserId = userId;

    // 1. Demande ou vérification de l'autorisation
    final status = await requestPermission();
    if (status == AppNotificationPermissionStatus.denied) {
      return;
    }

    // 2. Récupération du jeton FCM de l'appareil
    try {
      // ignore: deprecated_member_use
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        await _saveTokenToFirestore(userId, token);
      }
    } catch (_) {
      // Ignorer l'échec de récupération temporaire
    }

    // 3. Écoute du renouvellement automatique du jeton FCM
    await _tokenRefreshSub?.cancel();
    // ignore: deprecated_member_use
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
      _currentToken = newToken;
      if (_currentUserId != null) {
        await _saveTokenToFirestore(_currentUserId!, newToken);
      }
    });

    // 4. Écoute des messages en premier plan (Foreground)
    await _foregroundMessageSub?.cancel();
    _foregroundMessageSub = FirebaseMessaging.onMessage.listen((message) {
      final payload = ErrandNotificationPayload.fromRemoteMessage(message);
      _foregroundPayloadController.add(payload);
    });
  }

  /// Enregistre de façon sécurisée le jeton FCM de l'appareil dans le profil Firestore.
  Future<void> _saveTokenToFirestore(String userId, String token) async {
    try {
      final now = FieldValue.serverTimestamp();

      // Enregistrement dans la sous-collection multi-appareils
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('fcm_tokens')
          .doc(token)
          .set({
        'token': token,
        'platform': 'android',
        'updatedAt': now,
        'createdAt': now,
      }, SetOptions(merge: true));

      // Mise à jour du champ racine fcmToken pour compatibilité backend direct
      await _firestore.collection('users').doc(userId).set({
        'fcmToken': token,
        'updatedAt': now,
      }, SetOptions(merge: true));
    } catch (_) {
      // Les règles de sécurité Firestore encadrent l'écriture à l'utilisateur propriétaire
    }
  }

  /// Révocation et suppression du jeton lors de la déconnexion d'un utilisateur.
  Future<void> unregisterUser() async {
    final uid = _currentUserId;
    final token = _currentToken;

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    await _foregroundMessageSub?.cancel();
    _foregroundMessageSub = null;

    if (uid != null && token != null) {
      try {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('fcm_tokens')
            .doc(token)
            .delete();

        await _firestore.collection('users').doc(uid).update({
          'fcmToken': FieldValue.delete(),
        });
      } catch (_) {
        // Ignorer si déjà supprimé ou hors-ligne
      }
    }

    _currentUserId = null;
    _currentToken = null;
  }

  /// Diagnostic complet du sous-système de notification.
  Future<Map<String, dynamic>> getDiagnosticReport() async {
    final status = await requestPermission();
    return {
      'permissionStatus': status.name,
      'isAuthorized': status == AppNotificationPermissionStatus.granted,
      'hasToken': _currentToken != null && _currentToken!.isNotEmpty,
      'maskedToken': maskedToken ?? 'AUCUN_JETON',
      'channelId': errandUpdatesChannelId,
      'userId': _currentUserId ?? 'NON_CONNECTÉ',
    };
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundMessageSub?.cancel();
    _foregroundPayloadController.close();
  }
}
