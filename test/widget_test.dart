import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dili_express/models/user_model.dart';
import 'package:dili_express/models/errand_model.dart';
import 'package:dili_express/models/errand_item_model.dart';
import 'package:dili_express/models/errand_bid_model.dart';
import 'package:dili_express/services/offline_pin_cache_service.dart';
import 'package:dili_express/services/auth_service.dart';

void main() {
  group('1. Modèle Utilisateur & Règle Téléphone Non-Obligatoire', () {
    test('UserModel supporte un numéro de téléphone nul ou absent', () {
      final user = UserModel(
        uid: 'user_123',
        fullName: 'Karim Z.',
        email: 'karim@dili.dz',
        phone: null, // STRICTEMENT OPTIONNEL
        role: 'client',
      );

      expect(user.phone, isNull);
      expect(user.isClient, isTrue);
      expect(user.isShopper, isFalse);

      final map = user.toMap();
      expect(map['phone'], isNull);
      expect(map['fullName'], equals('Karim Z.'));

      final restored = UserModel.fromMap(map, documentId: 'user_123');
      expect(restored.phone, isNull);
      expect(restored.fullName, equals('Karim Z.'));
    });

    test(
      'UserModel copyWith permet de modifier le nom sans imposer le téléphone',
      () {
        const user = UserModel(
          uid: 'user_456',
          fullName: 'Ancien Nom',
          phone: null,
        );

        final updated = user.copyWith(fullName: 'Nouveau Nom');
        expect(updated.fullName, equals('Nouveau Nom'));
        expect(updated.phone, isNull);
      },
    );

    test('UserModel Shopper gère la trésorerie et la disponibilité', () {
      const shopper = UserModel(
        uid: 'shopper_01',
        fullName: 'Yacine Livreur',
        role: 'shopper',
        isOnline: true,
        availableCash: 5000.0,
      );

      expect(shopper.isShopper, isTrue);
      expect(shopper.isOnline, isTrue);
      expect(shopper.availableCash, equals(5000.0));
    });
  });

  group('2. Modèle Course (ErrandModel) & Formules Métier V2', () {
    test('Formule obligatoire : Total à payer = Montant ticket + Commission négociée', () {
      const errand = ErrandModel(
        errandId: 'errand_001',
        clientId: 'client_001',
        storeName: 'Supermarché Uno',
        deliveryAddress: 'Hydra, Alger',
        estimatedBudget: 3000.0,
        ticketAmount: 2850.50, // Montant réel du ticket de caisse
        negotiatedCommission: 400.0, // Commission négociée
        securePin: '4821',
      );

      // Formule obligatoire vérifiée
      expect(errand.totalAmount, equals(3250.50));
      expect(errand.treasuryRequired, equals(3000.0));
      expect(errand.securePin, equals('4821'));
    });

    test(
      'Validation justificatif de caisse bloquant pour le départ en livraison',
      () {
        // Sans photo ni montant -> Bloqué
        const pendingErrand = ErrandModel(
          errandId: 'errand_002',
          clientId: 'client_001',
          storeName: 'Supérette',
          deliveryAddress: 'Bab Ezzouar',
          estimatedBudget: 1500.0,
          securePin: '1234',
        );
        expect(pendingErrand.isReceiptValidated, isFalse);

        // Avec photo et montant validés -> Débloqué
        final validatedErrand = pendingErrand.copyWith(
          ticketAmount: 1450.0,
          ticketPhotoUrl: 'https://storage.googleapis.com/ticket.jpg',
        );
        expect(validatedErrand.isReceiptValidated, isTrue);
      },
    );

    test('Étape d\'appel obligatoire entre client et shoppeur', () {
      const errand = ErrandModel(
        errandId: 'errand_003',
        clientId: 'client_001',
        storeName: 'Marché',
        deliveryAddress: 'Kouba',
        estimatedBudget: 2000.0,
        securePin: '9999',
        callCompleted: false,
      );

      expect(errand.callCompleted, isFalse);

      final callValidated = errand.copyWith(callCompleted: true);
      expect(callValidated.callCompleted, isTrue);
    });
  });

  group('3. Modèles Articles (/items) & Offres (/bids)', () {
    test('ErrandItemModel gère les 3 statuts : Trouvé, Remplacé, Rupture', () {
      const item = ErrandItemModel(
        itemId: 'item_01',
        name: 'Lait Candia',
        quantity: 2,
        unit: 'x',
      );

      expect(item.isPending, isTrue);

      final foundItem = item.copyWith(status: ErrandItemStatus.found);
      expect(foundItem.isFound, isTrue);

      final replacedItem = item.copyWith(
        status: ErrandItemStatus.replaced,
        replacementNote: 'Lait Soummam disponible à 110 DA',
      );
      expect(replacedItem.isReplaced, isTrue);
      expect(replacedItem.replacementNote, isNotNull);

      final unavailableItem = item.copyWith(
        status: ErrandItemStatus.unavailable,
      );
      expect(unavailableItem.isUnavailable, isTrue);
    });

    test('ErrandBidModel gère les offres de commission des shoppeurs', () {
      const bid = ErrandBidModel(
        bidId: 'bid_01',
        shopperId: 'shopper_01',
        shopperName: 'Nassim',
        shopperRating: 4.8,
        proposedCommission: 350.0,
      );

      expect(bid.isPending, isTrue);
      expect(bid.proposedCommission, equals(350.0));

      final acceptedBid = bid.copyWith(status: BidStatus.accepted);
      expect(acceptedBid.isAccepted, isTrue);
    });
  });

  group('4. Service Cache Offline du Code PIN (SharedPreferences)', () {
    test('Sauvegarde, vérification et suppression du PIN localement', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cacheService = OfflinePinCacheService(prefs);

      const errandId = 'errand_test_100';
      const securePin = '7341';

      // 1. Sauvegarde
      final saved = await cacheService.savePin(errandId, securePin);
      expect(saved, isTrue);

      // 2. Récupération
      final retrieved = await cacheService.getPin(errandId);
      expect(retrieved, equals('7341'));

      // 3. Vérification du PIN valide et invalide
      final isValid = await cacheService.verifyPin(errandId, '7341');
      expect(isValid, isTrue);

      final isInvalid = await cacheService.verifyPin(errandId, '0000');
      expect(isInvalid, isFalse);

      // 4. Suppression après clôture
      await cacheService.clearPin(errandId);
      final afterClear = await cacheService.getPin(errandId);
      expect(afterClear, isNull);
    });
  });

  group(
    '5. Validation des entrées d\'authentification sans téléphone obligatoire',
    () {
      test(
        'AuthResult gère correctement les retours de succès et d\'échec',
        () {
          const success = AuthResult.success(null);
          expect(success.isSuccess, isTrue);
          expect(success.errorMessage, isNull);

          const failure = AuthResult.failure(
            'Identifiant incorrect',
            errorCode: 'invalid-credential',
          );
          expect(failure.isSuccess, isFalse);
          expect(failure.errorCode, equals('invalid-credential'));
          expect(failure.errorMessage, equals('Identifiant incorrect'));
        },
      );
    },
  );
}
