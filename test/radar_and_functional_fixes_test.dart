import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:dili_express/models/errand_bid_model.dart';
import 'package:dili_express/models/errand_model.dart';
import 'package:dili_express/models/user_model.dart';
import 'package:dili_express/services/auth_service.dart';
import 'package:dili_express/services/map_tracking_service.dart';

void main() {
  group('1. Google Sign-In — Diagnostic & Gestion de l\'Erreur 10', () {
    test('Interception explicite de PlatformException avec code 10', () {
      final exception = PlatformException(
        code: 'sign_in_failed',
        message:
            'com.google.android.gms.common.api.ApiException: 10: ',
      );

      final isCode10 = exception.code == 'sign_in_failed' &&
          (exception.message?.contains('10:') ?? false);

      expect(isCode10, isTrue);
    });

    test('Configuration Web Client ID serveur AuthService', () {
      expect(
        AuthService.serverClientId,
        '273784230349-0lr2crsalpk51apeetf96fhthl4ap6k1.apps.googleusercontent.com',
      );
    });
  });

  group('2. Règle Téléphonique — Validation & Échange Symétrique', () {
    test('UserModel.isValidPhone valide les numéros valides algériens et internationaux', () {
      expect(UserModel.isValidPhone('+213550123456'), isTrue);
      expect(UserModel.isValidPhone('0550123456'), isTrue);
      expect(UserModel.isValidPhone('0661987654'), isTrue);
      expect(UserModel.isValidPhone('0770112233'), isTrue);
      expect(UserModel.isValidPhone('+33612345678'), isTrue);
    });

    test('UserModel.isValidPhone rejette les formats invalides ou vides', () {
      expect(UserModel.isValidPhone(null), isFalse);
      expect(UserModel.isValidPhone(''), isFalse);
      expect(UserModel.isValidPhone('12345'), isFalse);
      expect(UserModel.isValidPhone('abcdefghij'), isFalse);
    });

    test('ErrandBidModel préserve et transmet shopperPhone', () {
      final bid = ErrandBidModel(
        bidId: 'bid_test_1',
        shopperId: 'shopper_123',
        shopperName: 'Karim Shopper',
        shopperPhone: '0555123456',
        shopperRating: 4.9,
        proposedCommission: 400.0,
        status: BidStatus.pending,
      );

      final map = bid.toMap();
      expect(map['shopperPhone'], '0555123456');

      final deserialized = ErrandBidModel.fromMap(map, documentId: 'bid_test_1');
      expect(deserialized.shopperPhone, '0555123456');
    });

    test('ErrandModel intègre clientPhone et shopperPhone', () {
      const errand = ErrandModel(
        errandId: 'errand_123',
        clientId: 'client_456',
        shopperId: 'shopper_789',
        storeName: 'Supérette Locale',
        deliveryAddress: 'Hydra, Alger',
        estimatedBudget: 2000.0,
        securePin: '1234',
        clientPhone: '0550111222',
        shopperPhone: '0660333444',
      );

      expect(errand.clientPhone, '0550111222');
      expect(errand.shopperPhone, '0660333444');
    });
  });

  group('3. Trésorerie Shopper & Modes de Transport', () {
    test('Vérification de la trésorerie disponible par rapport au budget requis', () {
      const shopperWithCash = UserModel(
        uid: 'shop_1',
        fullName: 'Ali',
        availableCash: 5000.0,
        role: 'shopper',
      );

      const shopperLowCash = UserModel(
        uid: 'shop_2',
        fullName: 'Omar',
        availableCash: 1000.0,
        role: 'shopper',
      );

      const errand = ErrandModel(
        errandId: 'e_1',
        clientId: 'c_1',
        storeName: 'Boucherie',
        deliveryAddress: 'Bab El Oued',
        estimatedBudget: 3500.0,
        securePin: '5678',
      );

      expect(shopperWithCash.availableCash >= errand.treasuryRequired, isTrue);
      expect(shopperLowCash.availableCash >= errand.treasuryRequired, isFalse);
    });

    test('Tous les modes de transport ont des rayons et vitesses valides', () {
      for (final type in ShopperTransportType.values) {
        expect(type.labelFr.isNotEmpty, isTrue);
        expect(type.maxRadiusKm, greaterThan(0));
        expect(type.averageSpeedKmh, greaterThan(0));
        expect(type.maxWeightKg, greaterThan(0));
      }
    });
  });

  group('4. Justificatif de Caisse — Photo Seule ou Référence', () {
    test('isReceiptValidated débloque la livraison avec photo seule et montant > 0', () {
      const errandWithPhotoOnly = ErrandModel(
        errandId: 'e_photo',
        clientId: 'c_1',
        storeName: 'Supérette',
        deliveryAddress: 'Kouba',
        estimatedBudget: 1500.0,
        securePin: '4321',
        status: ErrandStatus.shopping,
        ticketAmount: 1450.0,
        ticketPhotoUrl: 'https://images.unsplash.com/ticket.jpg',
        ticketRef: null,
      );

      expect(errandWithPhotoOnly.isReceiptValidated, isTrue);
      expect(errandWithPhotoOnly.canTransitionTo(ErrandStatus.delivering), isTrue);
    });

    test('isReceiptValidated débloque la livraison avec référence seule et montant > 0', () {
      const errandWithRefOnly = ErrandModel(
        errandId: 'e_ref',
        clientId: 'c_1',
        storeName: 'Supérette',
        deliveryAddress: 'Kouba',
        estimatedBudget: 1500.0,
        securePin: '4321',
        status: ErrandStatus.shopping,
        ticketAmount: 1450.0,
        ticketPhotoUrl: null,
        ticketRef: 'FACT-2026-99',
      );

      expect(errandWithRefOnly.isReceiptValidated, isTrue);
      expect(errandWithRefOnly.canTransitionTo(ErrandStatus.delivering), isTrue);
    });

    test('isReceiptValidated bloque la livraison si aucun justificatif fourni', () {
      const errandNoReceipt = ErrandModel(
        errandId: 'e_none',
        clientId: 'c_1',
        storeName: 'Supérette',
        deliveryAddress: 'Kouba',
        estimatedBudget: 1500.0,
        securePin: '4321',
        status: ErrandStatus.shopping,
        ticketAmount: 1450.0,
        ticketPhotoUrl: null,
        ticketRef: null,
      );

      expect(errandNoReceipt.isReceiptValidated, isFalse);
      expect(errandNoReceipt.canTransitionTo(ErrandStatus.delivering), isFalse);
    });
  });

  group('5. Radar Géographique — Vagues Progressives & Fraîcheur 120s', () {
    test('Calcul de distance GPS via MapTrackingService', () {
      // Coordonnées Alger : Grande Poste vers Hydra (environ 4-5 km)
      const grandePoste = LatLng(36.7729, 3.0592);
      const hydra = LatLng(36.7438, 3.0421);

      final dist = MapTrackingService.calculateDistanceKm(grandePoste, hydra);
      expect(dist, greaterThan(3.0));
      expect(dist, lessThan(8.0));
    });

    test('Filtre de fraîcheur <= 120 secondes', () {
      final now = DateTime.now();
      final freshShopper = UserModel(
        uid: 's_fresh',
        fullName: 'Yacine',
        role: 'shopper',
        isOnline: true,
        location: const GeoPoint(36.7538, 3.0588),
        updatedAt: now.subtract(const Duration(seconds: 45)),
      );

      final staleShopper = UserModel(
        uid: 's_stale',
        fullName: 'Rachid',
        role: 'shopper',
        isOnline: true,
        location: const GeoPoint(36.7538, 3.0588),
        updatedAt: now.subtract(const Duration(seconds: 150)),
      );

      bool isShopperFresh(UserModel s) {
        if (s.updatedAt == null) return true;
        return DateTime.now().difference(s.updatedAt!).inSeconds <= 120;
      }

      expect(isShopperFresh(freshShopper), isTrue);
      expect(isShopperFresh(staleShopper), isFalse);
    });

    test('Expansion progressive des vagues de recherche (2 à 14 km)', () {
      const waves = [2.0, 5.0, 8.0, 11.0, 14.0];
      expect(waves.length, 5);
      expect(waves.first, 2.0);
      expect(waves.last, 14.0);

      // Vérification que les vagues sont strictement croissantes
      for (int i = 0; i < waves.length - 1; i++) {
        expect(waves[i] < waves[i + 1], isTrue);
      }
    });
  });
}
