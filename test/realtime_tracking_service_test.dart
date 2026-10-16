import 'package:flutter_test/flutter_test.dart';
import 'package:dili_express/models/errand_model.dart';
import 'package:dili_express/services/realtime_tracking_service.dart';

void main() {
  group('RealtimeTrackingService & RTDB Quota Throttling (Spark)', () {
    test('Rejette les coordonnées géographiques invalides', () async {
      final service = RealtimeTrackingService();

      expect(
        () => service.updateShopperLocation(
          uid: 'shopper1',
          latitude: 95.0, // Invalide (> 90)
          longitude: 3.0,
        ),
        throwsArgumentError,
      );

      expect(
        () => service.updateShopperLocation(
          uid: 'shopper1',
          latitude: 36.75,
          longitude: 200.0, // Invalide (> 180)
        ),
        throwsArgumentError,
      );

      expect(
        () => service.pushActiveErrandLocation(
          errandId: 'errand1',
          shopperId: 'shopper1',
          clientId: 'client1',
          latitude: -95.0, // Invalide (< -90)
          longitude: 3.0,
        ),
        throwsArgumentError,
      );
    });

    test('Constante minWriteInterval configurée pour préserver le forfait Spark', () {
      expect(RealtimeTrackingService.minWriteInterval.inSeconds, equals(8));
    });
  });

  group('ErrandModel & Ticket Verification (Spark sans Storage)', () {
    test('Un montant seul ne suffit pas à valider le justificatif de caisse', () {
      const errand = ErrandModel(
        errandId: 'e1',
        clientId: 'c1',
        storeName: 'Supérette Alger',
        deliveryAddress: 'Hydra',
        estimatedBudget: 1500,
        ticketAmount: 1450,
        ticketRef: null,
        ticketPhotoUrl: null,
        securePin: '1234',
        status: ErrandStatus.shopping,
      );

      // Règle impérative : Le simple champ ticketAmount n'est PAS une preuve vérifiée
      expect(errand.isReceiptValidated, isFalse);
      expect(errand.canTransitionTo(ErrandStatus.delivering), isFalse);
    });

    test('Validation réussie avec ticketRef de caisse (>= 3 car) sans Storage', () {
      const errand = ErrandModel(
        errandId: 'e1',
        clientId: 'c1',
        storeName: 'Supérette Alger',
        deliveryAddress: 'Hydra',
        estimatedBudget: 1500,
        ticketAmount: 1450,
        ticketRef: 'TCK-2026-08492', // Référence probante
        ticketPhotoUrl: null,
        securePin: '1234',
        status: ErrandStatus.shopping,
      );

      expect(errand.isReceiptValidated, isTrue);
      expect(errand.canTransitionTo(ErrandStatus.delivering), isTrue);
    });

    test('Validation rétrocompatible réussie avec ticketPhotoUrl', () {
      const errand = ErrandModel(
        errandId: 'e1',
        clientId: 'c1',
        storeName: 'Supérette Alger',
        deliveryAddress: 'Hydra',
        estimatedBudget: 1500,
        ticketAmount: 1450,
        ticketRef: null,
        ticketPhotoUrl: 'https://example.com/receipt.jpg',
        securePin: '1234',
        status: ErrandStatus.shopping,
      );

      expect(errand.isReceiptValidated, isTrue);
      expect(errand.canTransitionTo(ErrandStatus.delivering), isTrue);
    });

    test('Formule obligatoire du total à encaisser', () {
      const errand = ErrandModel(
        errandId: 'e1',
        clientId: 'c1',
        storeName: 'Supérette Alger',
        deliveryAddress: 'Hydra',
        estimatedBudget: 1500,
        ticketAmount: 1450,
        negotiatedCommission: 350,
        securePin: '1234',
      );

      expect(errand.totalAmount, equals(1800.0));
    });
  });
}
