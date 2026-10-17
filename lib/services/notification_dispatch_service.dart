import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Service client assurant la communication HTTP sécurisée entre l'application 9DILI EXPRESS
/// et le backend Cloudflare Worker (notifications_dispatcher).
class NotificationDispatchService {
  /// URL de base configurable (via --dart-define=NOTIFICATIONS_DISPATCHER_URL=... ou valeur par défaut)
  static const String defaultDispatcherUrl = String.fromEnvironment(
    'NOTIFICATIONS_DISPATCHER_URL',
    defaultValue: 'https://dili-express-notifications-dispatcher.workers.dev',
  );

  final String baseUrl;
  final FirebaseAuth? _customAuth;
  final http.Client _httpClient;

  NotificationDispatchService({
    String? baseUrl,
    FirebaseAuth? auth,
    http.Client? httpClient,
  })  : baseUrl = (baseUrl ?? defaultDispatcherUrl).replaceAll(RegExp(r'/+$'), ''),
        _customAuth = auth,
        _httpClient = httpClient ?? http.Client();

  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  /// Récupère le jeton Firebase ID Token de l'utilisateur courant
  Future<String?> _getIdToken() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (e) {
      debugPrint('NotificationDispatchService: échec récupération ID Token: $e');
      return null;
    }
  }

  /// Prépare les en-têtes d'authentification Bearer
  Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final token = await _getIdToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Émet une notification métier via l'endpoint autoritatif `/api/notify` du Worker.
  ///
  /// - [errandId] : Identifiant unique de la course
  /// - [eventType] : Type d'événement conforme à `ErrandEvents` (ex: `bid_accepted`, `errand_accepted`, etc.)
  /// - [idempotencyKey] : Clé d'idempotence optionnelle (déduite de errandId_eventType si omise)
  ///
  /// Gestion des erreurs :
  /// - 200..299 : Succès
  /// - 409 : Conflit/doublon ignoré proprement (opération déjà traitée)
  /// - 404 / 504 / réseau : Dégradation gracieuse, ne lève jamais d'exception non gérée.
  Future<bool> notify({
    required String errandId,
    required String eventType,
    String? idempotencyKey,
  }) async {
    final uri = Uri.parse('$baseUrl/api/notify');
    try {
      final headers = await _buildHeaders();
      final payload = <String, dynamic>{
        'errandId': errandId,
        'eventType': eventType,
      };
      if (idempotencyKey != null) {
        payload['idempotencyKey'] = idempotencyKey;
      }
      final body = jsonEncode(payload);

      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: body,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('NotificationDispatchService: notification $eventType envoyée pour $errandId (${response.statusCode})');
        return true;
      } else if (response.statusCode == 409) {
        debugPrint('NotificationDispatchService: notification $eventType pour $errandId déjà en cours ou doublon (409) - ignoré.');
        return true;
      } else {
        debugPrint('NotificationDispatchService: Worker a retourné le code ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('NotificationDispatchService: échec réseau non-bloquant pour $eventType sur $errandId: $e');
      return false;
    }
  }

  /// Déclenche la première vague du radar intelligent pour une nouvelle course.
  Future<Map<String, dynamic>?> dispatchRadar({
    required String errandId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/radar/dispatch');
    try {
      final headers = await _buildHeaders();
      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode({'errandId': errandId}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 409) {
        debugPrint('NotificationDispatchService: Radar dispatch déjà en cours ou terminé pour $errandId (409)');
        return null;
      } else {
        debugPrint('NotificationDispatchService: /api/radar/dispatch a échoué (${response.statusCode}): ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('NotificationDispatchService: Erreur réseau /api/radar/dispatch: $e');
      return null;
    }
  }

  /// Accepte une course candidate côté Shopper de manière atomique via le Worker.
  Future<Map<String, dynamic>?> acceptRadar({
    required String errandId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/radar/accept');
    try {
      final headers = await _buildHeaders();
      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode({'errandId': errandId}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('NotificationDispatchService: /api/radar/accept a échoué (${response.statusCode}): ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('NotificationDispatchService: Erreur réseau /api/radar/accept: $e');
      return null;
    }
  }

  /// Décline une course candidate côté Shopper.
  Future<bool> declineRadar({
    required String errandId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/radar/decline');
    try {
      final headers = await _buildHeaders();
      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode({'errandId': errandId}),
      );

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('NotificationDispatchService: Erreur réseau /api/radar/decline: $e');
      return false;
    }
  }

  /// Demande l'avancement immédiat vers la vague suivante du radar (fallback client si Cloudflare queue indisponible).
  Future<Map<String, dynamic>?> nextWave({
    required String errandId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/radar/next-wave');
    try {
      final headers = await _buildHeaders();
      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode({'errandId': errandId}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('NotificationDispatchService: Erreur réseau /api/radar/next-wave: $e');
      return null;
    }
  }

  /// Récupère l'état courant du radar pour une commande donnée.
  Future<Map<String, dynamic>?> getRadarStatus({
    required String errandId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/radar/status?errandId=$errandId');
    try {
      final headers = await _buildHeaders();
      final response = await _httpClient.get(uri, headers: headers);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('NotificationDispatchService: Erreur réseau /api/radar/status: $e');
      return null;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
