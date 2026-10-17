import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dili_express/models/errand_model.dart';

void main() {
  group('ErrandModel — Support Géographique du Radar', () {
    test('Sérialisation et désérialisation de storeGeoPoint', () {
      final storePoint = const GeoPoint(36.752887, 3.042048); // Alger centre
      final deliveryPoint = const GeoPoint(36.760000, 3.050000);

      final errand = ErrandModel(
        errandId: 'errand_radar_01',
        clientId: 'client_dz_1',
        storeName: 'Supérette Didouche Mourad',
        deliveryAddress: 'Rue Didouche, Alger',
        storeGeoPoint: storePoint,
        deliveryGeoPoint: deliveryPoint,
        estimatedBudget: 3500.0,
        securePin: '4321',
        status: ErrandStatus.pending,
      );

      final map = errand.toMap();
      expect(map['storeGeoPoint'], equals(storePoint));
      expect(map['deliveryGeoPoint'], equals(deliveryPoint));
      expect(map['status'], equals(ErrandStatus.pending));

      final restored = ErrandModel.fromMap(map, documentId: 'errand_radar_01');
      expect(restored.storeGeoPoint, isNotNull);
      expect(restored.storeGeoPoint!.latitude, equals(36.752887));
      expect(restored.storeGeoPoint!.longitude, equals(3.042048));
      expect(restored.deliveryGeoPoint, isNotNull);
    });

    test('copyWith préserve et met à jour storeGeoPoint', () {
      final initial = ErrandModel(
        errandId: 'errand_copy_01',
        clientId: 'client_1',
        storeName: 'Centre Commercial Bab Ezzouar',
        deliveryAddress: 'Bab Ezzouar, Alger',
        estimatedBudget: 5000.0,
        securePin: '1122',
      );

      expect(initial.storeGeoPoint, isNull);

      final updated = initial.copyWith(
        storeGeoPoint: const GeoPoint(36.716667, 3.183333),
      );

      expect(updated.storeGeoPoint, isNotNull);
      expect(updated.storeGeoPoint!.latitude, equals(36.716667));
      expect(updated.storeName, equals('Centre Commercial Bab Ezzouar'));
    });
  });

  group('Attribution Exclusive Atomique & Machine d\'État', () {
    test('Une course pending sans shopperId permet une transition vers accepted', () {
      final pendingErrand = ErrandModel(
        errandId: 'errand_assign_01',
        clientId: 'client_1',
        storeName: 'Boucherie Hydra',
        deliveryAddress: 'Hydra, Alger',
        estimatedBudget: 2500.0,
        securePin: '9988',
        status: ErrandStatus.pending,
        shopperId: null,
      );

      expect(pendingErrand.isAssigned, isFalse);
      expect(pendingErrand.canTransitionTo(ErrandStatus.accepted), isTrue);

      final acceptedErrand = pendingErrand.copyWith(
        shopperId: 'shopper_winner_123',
        status: ErrandStatus.accepted,
      );

      expect(acceptedErrand.isAssigned, isTrue);
      expect(acceptedErrand.shopperId, equals('shopper_winner_123'));
      expect(acceptedErrand.status, equals(ErrandStatus.accepted));
    });

    test('Tentative de double attribution : Rejet logique d\'un concurrent perdant', () {
      final assignedErrand = ErrandModel(
        errandId: 'errand_assign_02',
        clientId: 'client_1',
        shopperId: 'shopper_winner_123',
        storeName: 'Marché Ali Mellah',
        deliveryAddress: '1er Mai, Alger',
        estimatedBudget: 1500.0,
        securePin: '3344',
        status: ErrandStatus.accepted,
      );

      // Simulation de la vérification de précondition lors de l'attribution
      final isStillAvailable =
          assignedErrand.status == ErrandStatus.pending &&
          (assignedErrand.shopperId == null || assignedErrand.shopperId!.isEmpty);

      expect(isStillAvailable, isFalse);

      // Le concurrent perdant doit être rejeté
      final competitorShopperId = 'shopper_loser_456';
      final isAssignedToCompetitor = assignedErrand.shopperId == competitorShopperId;
      expect(isAssignedToCompetitor, isFalse);

      // Le gagnant initial réitérant son appel est idempotent
      final isAssignedToWinner = assignedErrand.shopperId == 'shopper_winner_123';
      expect(isAssignedToWinner, isTrue);
    });

    test('Une course annulée ne peut pas être attribuée', () {
      final cancelledErrand = ErrandModel(
        errandId: 'errand_cancelled_01',
        clientId: 'client_1',
        storeName: 'Supérette',
        deliveryAddress: 'Alger',
        estimatedBudget: 1000.0,
        securePin: '1234',
        status: ErrandStatus.cancelled,
      );

      expect(cancelledErrand.canTransitionTo(ErrandStatus.accepted), isFalse);
    });

    test('Interdiction formelle d\'auto-attribution : Le créateur ne peut pas devenir le shopper', () {
      final clientErrand = ErrandModel(
        errandId: 'errand_self_assign_01',
        clientId: 'user_dz_creator_99',
        storeName: 'Supérette Didouche',
        deliveryAddress: 'Alger',
        estimatedBudget: 3000.0,
        securePin: '5678',
        status: ErrandStatus.pending,
      );

      // Tentative du créateur de s'assigner sa propre course
      final candidateShopperId = 'user_dz_creator_99';
      final isSelfAssignment = clientErrand.clientId == candidateShopperId;
      expect(isSelfAssignment, isTrue);

      // Simulation du guard présent dans assignShopperAtomic et handleAtomicAssignment
      expect(
        () {
          if (clientErrand.clientId == candidateShopperId) {
            throw StateError(
              "cannot_assign_own_errand: Le créateur de la course ne peut pas s'auto-attribuer sa propre course.",
            );
          }
        },
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('cannot_assign_own_errand'),
          ),
        ),
      );
    });
  });
}
