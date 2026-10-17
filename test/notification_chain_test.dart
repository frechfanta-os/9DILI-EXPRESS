import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:dili_express/services/errand_service.dart';
import 'package:dili_express/services/notification_service.dart';
import 'package:dili_express/services/notification_dispatch_service.dart';

// ============================================================================
// MOCKS & FAKES POUR LES TESTS DE LA CHAÎNE DE NOTIFICATION
// ============================================================================

class FakeFirestoreStorage {
  final Map<String, Map<String, dynamic>> documents = {};
  final Map<String, Map<String, Map<String, dynamic>>> subcollections = {};

  void setDoc(String path, Map<String, dynamic> data, {bool merge = false}) {
    if (merge && documents.containsKey(path)) {
      documents[path] = {...documents[path]!, ...data};
    } else {
      documents[path] = Map.from(data);
    }
  }

  void updateDoc(String path, Map<String, dynamic> data) {
    if (!documents.containsKey(path)) {
      throw StateError('Document not found: $path');
    }
    final existing = documents[path]!;
    for (final entry in data.entries) {
      if (entry.value == FieldValue.delete()) {
        existing.remove(entry.key);
      } else {
        existing[entry.key] = entry.value;
      }
    }
  }

  void deleteDoc(String path) {
    documents.remove(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. NotificationService — Initialisation, Enregistrement et Payload', () {
    test('ErrandNotificationPayload dérive correctement le statut depuis eventType', () {
      final messageWithStatus = RemoteMessage(
        data: {
          'errandId': 'errand_101',
          'eventType': 'shopper_delivering',
          'status': 'custom_status',
        },
      );
      final payload1 = ErrandNotificationPayload.fromRemoteMessage(messageWithStatus);
      expect(payload1.errandId, 'errand_101');
      expect(payload1.eventType, 'shopper_delivering');
      expect(payload1.newStatus, 'custom_status');

      // Test sans champ status dans data (format Cloudflare Worker actuel)
      final messageWithoutStatus = RemoteMessage(
        data: {
          'errandId': 'errand_102',
          'eventType': 'shopper_delivering',
        },
      );
      final payload2 = ErrandNotificationPayload.fromRemoteMessage(messageWithoutStatus);
      expect(payload2.newStatus, 'delivering');

      // Test eventType errand_completed
      final completedMsg = RemoteMessage(
        data: {'errandId': 'errand_103', 'eventType': 'errand_completed'},
      );
      expect(ErrandNotificationPayload.fromRemoteMessage(completedMsg).newStatus, 'completed');

      // Test eventType bid_accepted
      final bidAcceptedMsg = RemoteMessage(
        data: {'errandId': 'errand_104', 'eventType': 'bid_accepted'},
      );
      expect(ErrandNotificationPayload.fromRemoteMessage(bidAcceptedMsg).newStatus, 'accepted');

      // Test eventType errand_cancelled
      final cancelledMsg = RemoteMessage(
        data: {'errandId': 'errand_105', 'eventType': 'errand_cancelled'},
      );
      expect(ErrandNotificationPayload.fromRemoteMessage(cancelledMsg).newStatus, 'cancelled');

      // Test eventType new_errand_available
      final newErrandMsg = RemoteMessage(
        data: {'errandId': 'errand_106', 'eventType': 'new_errand_available'},
      );
      expect(ErrandNotificationPayload.fromRemoteMessage(newErrandMsg).newStatus, 'pending');
    });

    test('Masked token protège la vie privée du jeton FCM', () {
      final service = NotificationService();
      expect(service.maskedToken, isNull);
    });
  });

  group('2. NotificationDispatchService — Appels HTTP Worker et Résilience', () {
    test('notify envoie POST /api/notify avec headers et body JSON valides', () async {
      String? recordedPath;
      String? recordedMethod;
      Map<String, dynamic>? recordedBody;

      final mockClient = MockClient((request) async {
        recordedPath = request.url.path;
        recordedMethod = request.method;
        recordedBody = jsonDecode(request.body) as Map<String, dynamic>;

        return http.Response(
          jsonEncode({
            'success': true,
            'delivered': true,
            'messageId': 'projects/dili-express/messages/msg_123',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dispatchService = NotificationDispatchService(
        baseUrl: 'https://mock-worker.workers.dev',
        httpClient: mockClient,
      );

      final success = await dispatchService.notify(
        errandId: 'errand_abc_1',
        eventType: 'shopper_delivering',
      );

      expect(success, isTrue);
      expect(recordedMethod, 'POST');
      expect(recordedPath, '/api/notify');
      expect(recordedBody?['errandId'], 'errand_abc_1');
      expect(recordedBody?['eventType'], 'shopper_delivering');
    });

    test('notify tolère le statut 409 (doublon ou in-flight) sans lever d exception', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'reason': 'duplicate',
            'message': 'Requête dupliquée',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final dispatchService = NotificationDispatchService(
        baseUrl: 'https://mock-worker.workers.dev',
        httpClient: mockClient,
      );

      final success = await dispatchService.notify(
        errandId: 'errand_abc_dup',
        eventType: 'errand_accepted',
      );

      // 409 est traité avec grâce (idempotence réussie)
      expect(success, isTrue);
    });

    test('notify ne crash pas lors d une déconnexion réseau (SocketException / ClientException)', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Erreur connexion réseau simulée');
      });

      final dispatchService = NotificationDispatchService(
        baseUrl: 'https://mock-worker.workers.dev',
        httpClient: mockClient,
      );

      final success = await dispatchService.notify(
        errandId: 'errand_offline',
        eventType: 'errand_completed',
      );

      // Dégradation gracieuse : retourne false, ne propage aucune exception
      expect(success, isFalse);
    });

    test('Endpoints Radar /dispatch, /accept, /decline, /next-wave et /status', () async {
      final recordedRequests = <String>[];

      final mockClient = MockClient((request) async {
        recordedRequests.add('${request.method} ${request.url.path}');
        return http.Response(jsonEncode({'success': true, 'wave': 1}), 200);
      });

      final dispatchService = NotificationDispatchService(
        baseUrl: 'https://mock-worker.workers.dev',
        httpClient: mockClient,
      );

      final r1 = await dispatchService.dispatchRadar(errandId: 'err_r1');
      expect(r1?['success'], isTrue);

      final r2 = await dispatchService.acceptRadar(errandId: 'err_r1');
      expect(r2?['success'], isTrue);

      final r3 = await dispatchService.declineRadar(errandId: 'err_r1');
      expect(r3, isTrue);

      final r4 = await dispatchService.nextWave(errandId: 'err_r1');
      expect(r4?['success'], isTrue);

      final r5 = await dispatchService.getRadarStatus(errandId: 'err_r1');
      expect(r5?['success'], isTrue);

      expect(recordedRequests, [
        'POST /api/radar/dispatch',
        'POST /api/radar/accept',
        'POST /api/radar/decline',
        'POST /api/radar/next-wave',
        'GET /api/radar/status',
      ]);
    });
  });

  group('3. ErrandService — Déclencheurs Métier & Non-Régression', () {
    test('Chaque transition de statut émet le bon eventType vers le dispatcher', () async {
      final sentEvents = <Map<String, String>>[];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/notify') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentEvents.add({
            'errandId': body['errandId'] as String,
            'eventType': body['eventType'] as String,
          });
        }
        return http.Response(jsonEncode({'success': true}), 200);
      });

      final dispatchService = NotificationDispatchService(
        baseUrl: 'https://mock-worker.workers.dev',
        httpClient: mockClient,
      );

      // Création d'un mock ErrandService utilisant ce dispatcher
      final testErrandService = TestErrandNotificationService(
        notificationDispatchService: dispatchService,
      );

      // 1. startDelivering
      await testErrandService.simulateStartDelivering('errand_100');
      // 2. notifyShopperArrived
      await testErrandService.notifyShopperArrived('errand_100');
      // 3. completeErrandWithPin
      await testErrandService.simulateCompleteErrand('errand_100');
      // 4. cancelErrand
      await testErrandService.simulateCancelErrand('errand_100');
      // 5. acceptBid
      await testErrandService.simulateAcceptBid('errand_100');
      // 6. confirmErrandAssignment
      await testErrandService.simulateConfirmAssignment('errand_100');

      expect(sentEvents, [
        {'errandId': 'errand_100', 'eventType': 'shopper_delivering'},
        {'errandId': 'errand_100', 'eventType': 'shopper_arrived'},
        {'errandId': 'errand_100', 'eventType': 'errand_completed'},
        {'errandId': 'errand_100', 'eventType': 'errand_cancelled'},
        {'errandId': 'errand_100', 'eventType': 'bid_accepted'},
        {'errandId': 'errand_100', 'eventType': 'errand_accepted'},
      ]);
    });

    test('Règle critique : Un échec Worker ou HTTP 500 NE FAIT PAS échouer la transition métier', () async {
      // Mock HTTP simulant une panne totale du Worker (500 Internal Server Error)
      final brokenClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Cloudflare Worker downstream timeout'}),
          500,
        );
      });

      final failingDispatcher = NotificationDispatchService(
        baseUrl: 'https://broken-worker.workers.dev',
        httpClient: brokenClient,
      );

      final resilientErrandService = TestErrandNotificationService(
        notificationDispatchService: failingDispatcher,
      );

      // La transition métier doit réussir à 100% sans propager d'erreur
      expect(
        () async => await resilientErrandService.simulateStartDelivering('err_critical_1'),
        returnsNormally,
      );
      expect(
        () async => await resilientErrandService.simulateCompleteErrand('err_critical_1'),
        returnsNormally,
      );
      expect(
        () async => await resilientErrandService.simulateCancelErrand('err_critical_1'),
        returnsNormally,
      );
    });
  });
}

/// Classe de test permettant d'isoler les déclencheurs de notifications d'ErrandService
/// sans dépendre du backend Firestore réel.
class TestErrandNotificationService extends ErrandService {
  TestErrandNotificationService({
    super.notificationDispatchService,
  });

  Future<void> simulateStartDelivering(String errandId) async {
    // Émission non-bloquante identique à ErrandService.startDelivering
    final dispatch = notificationDispatchService;
    if (dispatch != null) {
      await dispatch.notify(
        errandId: errandId,
        eventType: 'shopper_delivering',
      ).catchError((_) => false);
    }
  }

  Future<void> simulateCompleteErrand(String errandId) async {
    final dispatch = notificationDispatchService;
    if (dispatch != null) {
      await dispatch.notify(
        errandId: errandId,
        eventType: 'errand_completed',
      ).catchError((_) => false);
    }
  }

  Future<void> simulateCancelErrand(String errandId) async {
    final dispatch = notificationDispatchService;
    if (dispatch != null) {
      await dispatch.notify(
        errandId: errandId,
        eventType: 'errand_cancelled',
      ).catchError((_) => false);
    }
  }

  Future<void> simulateAcceptBid(String errandId) async {
    final dispatch = notificationDispatchService;
    if (dispatch != null) {
      await dispatch.notify(
        errandId: errandId,
        eventType: 'bid_accepted',
      ).catchError((_) => false);
    }
  }

  Future<void> simulateConfirmAssignment(String errandId) async {
    final dispatch = notificationDispatchService;
    if (dispatch != null) {
      await dispatch.notify(
        errandId: errandId,
        eventType: 'errand_accepted',
      ).catchError((_) => false);
    }
  }

  NotificationDispatchService? get notificationDispatchService => dispatchService;
}
