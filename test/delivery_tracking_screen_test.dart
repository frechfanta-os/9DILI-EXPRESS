import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dili_express/models/errand_model.dart';
import 'package:dili_express/services/errand_service.dart';
import 'package:dili_express/services/map_tracking_service.dart';
import 'package:dili_express/services/realtime_tracking_service.dart';
import 'package:dili_express/ui/screens/delivery_tracking_screen.dart';

class MockMapTrackingService extends MapTrackingService {
  final bool permissionGranted;

  MockMapTrackingService({this.permissionGranted = true});

  @override
  Future<bool> checkAndRequestPermission() async {
    return permissionGranted;
  }

  @override
  Stream<Position>? startMissionTracking({
    required String errandId,
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilterMeters = 10,
  }) {
    return const Stream<Position>.empty();
  }
}

class MockRealtimeTrackingService extends RealtimeTrackingService {
  @override
  Stream<LatLng?> streamActiveErrandLocation(String errandId) {
    return Stream.value(const LatLng(36.7510, 3.0520));
  }

  @override
  Future<bool> pushActiveErrandLocation({
    required String errandId,
    required String shopperId,
    required String clientId,
    required double latitude,
    required double longitude,
    bool force = false,
  }) async {
    return true;
  }

  @override
  Future<void> cleanUpActiveErrand(String errandId) async {}
}

class FakeErrandService extends ErrandService {
  final ErrandModel errand;
  FakeErrandService(this.errand);

  @override
  Stream<ErrandModel?> streamErrand(String errandId) {
    return Stream.value(errand);
  }
}

void main() {
  const testErrand = ErrandModel(
    errandId: 'errand_tracking_test_1',
    clientId: 'client_alpha',
    shopperId: 'shopper_bravo',
    storeName: 'Supérette Alger Centre',
    deliveryAddress: 'Didouche Mourad, Alger',
    estimatedBudget: 3500.0,
    ticketAmount: 3200.0,
    ticketRef: 'TCK-2026-001',
    negotiatedCommission: 400.0,
    status: ErrandStatus.delivering,
    securePin: '4892',
    deliveryGeoPoint: GeoPoint(36.7538, 3.0588),
    shopperLocation: GeoPoint(36.7500, 3.0500),
  );

  group('DeliveryTrackingScreen & Suivi Temps Réel', () {
    testWidgets('Rendu de la vue Client avec ETA et marqueurs', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        MaterialApp(
          home: DeliveryTrackingScreen(
            errand: testErrand,
            errandService: FakeErrandService(testErrand),
            trackingService: MockRealtimeTrackingService(),
            mapTrackingService: MockMapTrackingService(permissionGranted: true),
            isShopperView: false,
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Suivi en Direct 📍'), findsOneWidget);
      expect(find.textContaining('ETA :'), findsOneWidget);
      expect(find.text('Afficher mon QR Code / PIN'), findsOneWidget);
      expect(find.textContaining('3600.00 DA'), findsOneWidget); // 3200 + 400
    });

    testWidgets(
      'Affichage du bandeau GPS indisponible en vue Shopper sans permission',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(412, 915));

        await tester.pumpWidget(
          MaterialApp(
            home: DeliveryTrackingScreen(
              errand: testErrand,
              errandService: FakeErrandService(testErrand),
              trackingService: MockRealtimeTrackingService(),
              mapTrackingService: MockMapTrackingService(
                permissionGranted: false,
              ),
              isShopperView: true,
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(
          find.text(
            'Position GPS indisponible — Veuillez activer la localisation pour diffuser votre trajet.',
          ),
          findsOneWidget,
        );
        expect(find.text('Valider le PIN de Remise'), findsOneWidget);
      },
    );

    testWidgets('Bascule et affichage du mode hors-ligne / réseau instable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        MaterialApp(
          home: DeliveryTrackingScreen(
            errand: testErrand,
            errandService: FakeErrandService(testErrand),
            trackingService: MockRealtimeTrackingService(),
            mapTrackingService: MockMapTrackingService(permissionGranted: true),
            isShopperView: false,
          ),
        ),
      );

      await tester.pump();

      // Clic sur l'icône réseau pour simuler la perte de réseau
      await tester.tap(find.byTooltip('Synchronisé'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Connexion réseau instable — Données et PIN synchronisés localement.',
        ),
        findsOneWidget,
      );
    });
  });
}
