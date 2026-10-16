import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dili_express/models/user_model.dart';
import 'package:dili_express/models/errand_model.dart';
import 'package:dili_express/models/errand_item_model.dart';
import 'package:dili_express/models/errand_bid_model.dart';
import 'package:dili_express/services/offline_pin_cache_service.dart';
import 'package:dili_express/services/errand_service.dart';

void main() {
  group('1. Sécurité des Profils, Rôles & Règle Téléphone Facultatif', () {
    test('Séparation stricte des rôles : Client vs Shopper', () {
      final client = UserModel(
        uid: 'client_secure_01',
        fullName: 'Amina Client',
        email: 'amina@test.dz',
        phone: null, // Strictement optionnel
        role: 'client',
      );

      final shopper = UserModel(
        uid: 'shopper_secure_01',
        fullName: 'Bilal Shopper',
        email: 'bilal@test.dz',
        phone: null,
        role: 'shopper',
        availableCash: 12000.0,
        rating: 4.9,
      );

      expect(client.isClient, isTrue);
      expect(client.isShopper, isFalse);
      expect(client.phone, isNull);

      expect(shopper.isShopper, isTrue);
      expect(shopper.isClient, isFalse);
      expect(shopper.availableCash, equals(12000.0));
      expect(shopper.rating, equals(4.9));
    });

    test(
      'Préservation des données et mise à jour profil sans forcer le téléphone',
      () {
        final initialUser = UserModel(
          uid: 'user_auth_789',
          fullName: 'Sofiane Initial',
          email: 'sofiane@google.com',
          phone: null,
          role: 'client',
          rating: 5.0,
        );

        final updated = initialUser.copyWith(
          fullName: 'Sofiane Modifié',
          // Phone reste null
        );

        expect(updated.fullName, equals('Sofiane Modifié'));
        expect(updated.email, equals('sofiane@google.com'));
        expect(updated.phone, isNull);
        expect(updated.uid, equals('user_auth_789'));
        expect(updated.rating, equals(5.0));
      },
    );
  });

  group('2. Machine d\'État des Courses & Transitions Autorisées', () {
    test('Transitions valides conformes au cycle de vie', () {
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.pending,
          ErrandStatus.accepted,
        ),
        isTrue,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.accepted,
          ErrandStatus.shopping,
        ),
        isTrue,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.shopping,
          ErrandStatus.delivering,
        ),
        isTrue,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.delivering,
          ErrandStatus.completed,
        ),
        isTrue,
      );

      // Annulations autorisées aux étapes intermédiaires
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.pending,
          ErrandStatus.cancelled,
        ),
        isTrue,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.accepted,
          ErrandStatus.cancelled,
        ),
        isTrue,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.shopping,
          ErrandStatus.cancelled,
        ),
        isTrue,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.delivering,
          ErrandStatus.cancelled,
        ),
        isTrue,
      );
    });

    test('Transitions illégitimes formellement rejetées', () {
      // Saut d'étapes non permis
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.pending,
          ErrandStatus.delivering,
        ),
        isFalse,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.pending,
          ErrandStatus.completed,
        ),
        isFalse,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.accepted,
          ErrandStatus.completed,
        ),
        isFalse,
      );

      // Marche arrière non permise
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.delivering,
          ErrandStatus.shopping,
        ),
        isFalse,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.delivering,
          ErrandStatus.pending,
        ),
        isFalse,
      );

      // États terminaux immuables
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.completed,
          ErrandStatus.pending,
        ),
        isFalse,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.completed,
          ErrandStatus.cancelled,
        ),
        isFalse,
      );
      expect(
        ErrandStatus.isValidTransition(
          ErrandStatus.cancelled,
          ErrandStatus.completed,
        ),
        isFalse,
      );
    });
  });

  group('3. Concurrence des Offres (Bids) & Assignation', () {
    test('Offres concurrentes multiples avec sélection atomique', () {
      const errandId = 'errand_multi_bids';

      final bid1 = ErrandBidModel(
        bidId: 'bid_101',
        shopperId: 'shopper_A',
        shopperName: 'Shopper Rapide',
        shopperRating: 4.8,
        proposedCommission: 450.0,
      );

      final bid2 = ErrandBidModel(
        bidId: 'bid_102',
        shopperId: 'shopper_B',
        shopperName: 'Shopper Proche',
        shopperRating: 4.9,
        proposedCommission: 400.0,
      );

      // Les deux offres sont initialement pendantes
      expect(bid1.isPending, isTrue);
      expect(bid2.isPending, isTrue);

      // Le client accepte l'offre 2
      final acceptedBid = bid2.copyWith(status: BidStatus.accepted);
      final rejectedBid = bid1.copyWith(status: BidStatus.rejected);

      expect(acceptedBid.isAccepted, isTrue);
      expect(rejectedBid.isRejected, isTrue);

      // Course assignée avec la commission négociée de l'offre retenue
      final assignedErrand = ErrandModel(
        errandId: errandId,
        clientId: 'client_999',
        shopperId: acceptedBid.shopperId,
        storeName: 'Carrefour El Biar',
        deliveryAddress: 'El Biar, Alger',
        estimatedBudget: 4000.0,
        negotiatedCommission: acceptedBid.proposedCommission,
        status: ErrandStatus.accepted,
        securePin: '5566',
      );

      expect(assignedErrand.isAssigned, isTrue);
      expect(assignedErrand.shopperId, equals('shopper_B'));
      expect(assignedErrand.negotiatedCommission, equals(400.0));
      expect(assignedErrand.status, equals(ErrandStatus.accepted));
    });
  });

  group('4. Contrôle Bloquant du Justificatif de Caisse & Formule Financière', () {
    test(
      'Passage au statut delivering strictement bloqué sans ticket et montant',
      () {
        const errandInShop = ErrandModel(
          errandId: 'errand_receipt_check',
          clientId: 'client_01',
          shopperId: 'shopper_01',
          storeName: 'Supermarché Ardis',
          deliveryAddress: 'Mohammadia',
          estimatedBudget: 5000.0,
          status: ErrandStatus.shopping,
          securePin: '7890',
          ticketAmount: null,
          ticketPhotoUrl: null,
        );

        // Impossible de passer en livraison sans justificatif
        expect(errandInShop.isReceiptValidated, isFalse);
        expect(errandInShop.canTransitionTo(ErrandStatus.delivering), isFalse);

        // Tentative avec montant 0 DA (invalide)
        final zeroAmountErrand = errandInShop.copyWith(
          ticketAmount: 0.0,
          ticketPhotoUrl: 'https://storage/ticket.jpg',
        );
        expect(zeroAmountErrand.isReceiptValidated, isFalse);
        expect(
          zeroAmountErrand.canTransitionTo(ErrandStatus.delivering),
          isFalse,
        );

        // Justificatif complet et validé
        final validatedErrand = errandInShop.copyWith(
          ticketAmount: 4850.0,
          ticketPhotoUrl: 'https://storage/ticket_ok.jpg',
        );
        expect(validatedErrand.isReceiptValidated, isTrue);
        expect(
          validatedErrand.canTransitionTo(ErrandStatus.delivering),
          isTrue,
        );
      },
    );

    test(
      'Formule financière obligatoire : Total = Montant Ticket + Commission',
      () {
        const errand = ErrandModel(
          errandId: 'errand_finance',
          clientId: 'client_01',
          storeName: 'Uno City Center',
          deliveryAddress: 'Bab Ezzouar',
          estimatedBudget: 3500.0,
          ticketAmount: 3200.75,
          negotiatedCommission: 500.0,
          securePin: '1122',
        );

        expect(errand.totalAmount, equals(3700.75));
        expect(errand.treasuryRequired, equals(3500.0));
      },
    );
  });

  group('5. Attestation Téléphonique Obligatoire & Traçabilité', () {
    test(
      'Garde-fou appel : confirmation requise avant clôture de négociation',
      () {
        const errandWithoutCall = ErrandModel(
          errandId: 'errand_call_guard',
          clientId: 'client_alpha',
          storeName: 'Marché Ali Mellah',
          deliveryAddress: '1er Mai',
          estimatedBudget: 2500.0,
          securePin: '3344',
          callCompleted: false,
        );

        expect(errandWithoutCall.callCompleted, isFalse);
        expect(errandWithoutCall.callConfirmedAt, isNull);
        expect(errandWithoutCall.callConfirmedBy, isNull);

        // Attestation explicite de l'appel
        final timestamp = DateTime.now();
        final errandWithCall = errandWithoutCall.copyWith(
          callCompleted: true,
          callConfirmedAt: timestamp,
          callConfirmedBy: 'client_alpha',
        );

        expect(errandWithCall.callCompleted, isTrue);
        expect(errandWithCall.callConfirmedAt, equals(timestamp));
        expect(errandWithCall.callConfirmedBy, equals('client_alpha'));
      },
    );
  });

  group('6. Sécurité Cryptographique PIN, Anti-Brute Force & Expiration', () {
    test('Génération cryptographique (Random.secure) du PIN à 4 chiffres', () {
      for (int i = 0; i < 20; i++) {
        final pin = ErrandService.generateCryptographicPin();
        expect(pin.length, equals(4));
        final pinInt = int.tryParse(pin);
        expect(pinInt, isNotNull);
        expect(pinInt! >= 1000 && pinInt <= 9999, isTrue);
      }
    });

    test('Détection de l\'expiration temporelle du PIN', () {
      final validErrand = ErrandModel(
        errandId: 'errand_pin_time',
        clientId: 'client_01',
        storeName: 'Magasin',
        deliveryAddress: 'Alger',
        estimatedBudget: 1000.0,
        securePin: '1234',
        pinExpiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );
      expect(validErrand.isPinExpired, isFalse);

      final expiredErrand = validErrand.copyWith(
        pinExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(expiredErrand.isPinExpired, isTrue);
    });

    test('Anti-Brute Force : verrouillage immédiat après 3 tentatives infructueuses', () {
      const errand = ErrandModel(
        errandId: 'errand_bruteforce',
        clientId: 'client_01',
        storeName: 'Boutique',
        deliveryAddress: 'Kouba',
        estimatedBudget: 2000.0,
        securePin: '4321',
        status: ErrandStatus.delivering,
        pinFailedAttempts: 0,
        pinLocked: false,
      );

      expect(errand.isPinLocked, isFalse);
      expect(errand.canTransitionTo(ErrandStatus.completed), isTrue);

      // 1ère erreur
      final attempt1 = errand.copyWith(pinFailedAttempts: 1);
      expect(attempt1.isPinLocked, isFalse);

      // 2ème erreur
      final attempt2 = errand.copyWith(pinFailedAttempts: 2);
      expect(attempt2.isPinLocked, isFalse);

      // 3ème erreur -> Verrouillage activé
      final attempt3 = errand.copyWith(pinFailedAttempts: 3, pinLocked: true);
      expect(attempt3.isPinLocked, isTrue);

      // Transition vers completed bloquée
      expect(attempt3.canTransitionTo(ErrandStatus.completed), isFalse);
    });

    test('Protection contre la double clôture', () {
      const completedErrand = ErrandModel(
        errandId: 'errand_double_close',
        clientId: 'client_01',
        storeName: 'Boutique',
        deliveryAddress: 'Alger',
        estimatedBudget: 2000.0,
        securePin: '4321',
        status: ErrandStatus.completed,
      );

      // Impossible de re-clôturer une course déjà terminée
      expect(completedErrand.canTransitionTo(ErrandStatus.completed), isFalse);
    });
  });

  group('7. Mode Hors-Ligne & Synchronisation Résiliente', () {
    test(
      'Enregistrement, réconciliation et purge des règlements hors-ligne',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final cacheService = OfflinePinCacheService(prefs);

        const errandId = 'errand_offline_sync';
        const pin = '8821';

        // 1. Mise en cache du code PIN avant la livraison en zone blanche
        await cacheService.savePin(errandId, pin);
        expect(await cacheService.getPin(errandId), equals('8821'));

        // 2. Vérification locale hors-ligne
        final isValidLocally = await cacheService.verifyPin(errandId, '8821');
        expect(isValidLocally, isTrue);

        // 3. Enregistrement du règlement hors-ligne pour réconciliation ultérieure
        await cacheService.recordOfflineSettlement(errandId, '8821');
        final pendingSettlements = await cacheService
            .getPendingOfflineSettlements();
        expect(pendingSettlements.containsKey(errandId), isTrue);
        expect(pendingSettlements[errandId], equals('8821'));

        // 4. Réconciliation et nettoyage
        await cacheService.clearOfflineSettlement(errandId);
        await cacheService.clearPin(errandId);

        final emptySettlements = await cacheService
            .getPendingOfflineSettlements();
        expect(emptySettlements.containsKey(errandId), isFalse);
        expect(await cacheService.getPin(errandId), isNull);
      },
    );
  });

  group('8. Articles en Magasin : Statuts & Remplacement', () {
    test('Gestion des articles avec note de remplacement', () {
      const item = ErrandItemModel(
        itemId: 'it_001',
        name: 'Huile Fleurial 5L',
        quantity: 1,
        unit: 'x',
        notes: 'Prendre marque Afia si absent',
      );

      expect(item.isPending, isTrue);

      final replaced = item.copyWith(
        status: ErrandItemStatus.replaced,
        replacementNote: 'Remplacé par Afia 5L à 650 DA',
      );

      expect(replaced.isReplaced, isTrue);
      expect(replaced.replacementNote, equals('Remplacé par Afia 5L à 650 DA'));
    });
  });
}
