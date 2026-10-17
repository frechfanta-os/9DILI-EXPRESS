import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dili_express/models/errand_model.dart';
import 'package:dili_express/models/errand_item_model.dart';
import 'package:dili_express/services/errand_service.dart';
import 'package:dili_express/services/product_catalog_service.dart';
import 'package:dili_express/ui/screens/create_errand_screen.dart';
import 'package:dili_express/ui/screens/shopping_mode_screen.dart';
import 'package:dili_express/ui/theme/app_theme.dart';

class MockErrandServiceForTests extends ErrandService {
  final Map<String, ErrandModel> mockErrands = {};
  final Map<String, List<ErrandItemModel>> mockItems = {};
  bool simulateNetworkError = false;

  @override
  Future<String> createErrand(
    ErrandModel errand, {
    List<ErrandItemModel>? items,
  }) async {
    if (simulateNetworkError) {
      throw const SocketException("Erreur de connexion réseau");
    }
    final id = errand.errandId.isNotEmpty
        ? errand.errandId
        : 'mock_errand_${mockErrands.length + 1}';
    final saved = errand.copyWith(errandId: id);
    mockErrands[id] = saved;
    if (items != null) {
      mockItems[id] = List.from(items);
    }
    return id;
  }

  @override
  Future<ErrandModel?> getErrand(String errandId) async {
    return mockErrands[errandId];
  }

  @override
  Stream<List<ErrandItemModel>> streamItems(String errandId) {
    return Stream.value(mockItems[errandId] ?? []);
  }

  @override
  Stream<List<ErrandModel>> streamPendingErrands({double? maxBudget}) {
    return Stream.value(
      mockErrands.values
          .where((e) => e.status == ErrandStatus.pending)
          .toList(),
    );
  }

  @override
  Future<void> cancelErrand({
    required String errandId,
    required String clientId,
    String? reason,
  }) async {
    if (simulateNetworkError) {
      throw const SocketException("Erreur réseau");
    }
    final errand = mockErrands[errandId];
    if (errand == null) {
      throw StateError("Course introuvable: $errandId");
    }
    if (errand.clientId != clientId) {
      throw StateError(
        "unauthorized: Seul le client propriétaire peut annuler cette commande.",
      );
    }
    if (errand.status == ErrandStatus.cancelled) {
      return;
    }
    if (errand.status == ErrandStatus.completed) {
      throw StateError(
        "cannot_cancel_completed: Impossible d'annuler une course déjà terminée.",
      );
    }
    if (!ErrandStatus.isValidTransition(
      errand.status,
      ErrandStatus.cancelled,
    )) {
      throw StateError(
        "invalid_transition: Impossible d'annuler la course au statut '${errand.status}'.",
      );
    }

    mockErrands[errandId] = errand.copyWith(status: ErrandStatus.cancelled);
  }
}

const testCatalogJson = '''
[
  {
    "sku_id": "DZ-TEST-001",
    "barcode": "613000000001",
    "name_fr": "Lait Soummam Candia 1L",
    "name_ar": "حليب صومام كانديا",
    "search_keywords_darja": ["lait", "hlib", "candia"],
    "brand": "Candia",
    "category": "Crémerie & Produits Laitiers",
    "sub_category": "Lait",
    "is_weighable": false,
    "unit_type": "bouteille",
    "unit_value": 1,
    "estimated_price_dzd": 120,
    "image_url": "https://example.com/lait.png"
  },
  {
    "sku_id": "DZ-TEST-002",
    "barcode": "613000000002",
    "name_fr": "Baguette de Pain tradition",
    "name_ar": "خبز تقليدي",
    "search_keywords_darja": ["pain", "khobz"],
    "brand": "Boulangerie",
    "category": "Boulangerie & Pâtisserie",
    "sub_category": "Pain",
    "is_weighable": false,
    "unit_type": "x",
    "unit_value": 1,
    "estimated_price_dzd": 15,
    "image_url": null
  }
]
''';

void main() {
  late ProductCatalogService catalogService;
  late MockErrandServiceForTests errandService;

  setUp(() async {
    catalogService = ProductCatalogService();
    await catalogService.loadCatalog(rawJsonString: testCatalogJson);
    errandService = MockErrandServiceForTests();
  });

  tearDown(() {
    catalogService.clear();
  });

  Widget createTestWidget() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateErrandScreen(
        clientId: 'client_unit_test',
        errandService: errandService,
        catalogService: catalogService,
        initialAddress: 'El Biar, Alger',
        initialStoreName: 'Supérette Centrale',
        initialGeoPoint: const GeoPoint(36.75, 3.05),
      ),
    );
  }

  group('UX CATALOGUE, PANIER & PRODUITS PERSONNALISÉS', () {
    testWidgets(
      '1. La barre de recherche reste fixe au-dessus des rayons et des produits',
      (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Vérification que la barre de recherche est affichée
        final searchField = find.byType(TextField).first;
        expect(searchField, findsOneWidget);

        // Vérification que les boutons d'actions personnalisées sont visibles
        expect(find.text('📷 Photographier'), findsOneWidget);
        expect(find.text('+ Produit personnalisé'), findsOneWidget);

        // Vérification du défilement horizontal des rayons
        expect(
          find.widgetWithText(ChoiceChip, 'Tous les rayons'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(ChoiceChip, 'Crémerie & Produits Laitiers'),
          findsOneWidget,
        );

        // Les produits sont listés verticalement dans Expanded
        expect(find.text('Lait Soummam Candia 1L'), findsOneWidget);
        expect(find.text('Baguette de Pain tradition'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Désélection d\'un produit et recalcul immédiat du panier et budget',
      (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Panier initial vide
        expect(find.text('Voir mon panier'), findsNothing);

        // 1. Ajouter Lait Candia au panier
        final addIcons = find.byIcon(Icons.add);
        expect(addIcons, findsWidgets);
        await tester.tap(addIcons.first);
        await tester.pumpAndSettle();

        // Panier contient 1 article
        expect(find.text('1 article au panier'), findsOneWidget);
        expect(find.text('Liste prête 🛒'), findsOneWidget);

        // Vérifier que le bouton de désélection (poubelle) est apparu sur la carte produit
        final deleteProductIcon = find.byIcon(Icons.delete_outline);
        expect(deleteProductIcon, findsWidgets);

        // 2. Cliquer sur la poubelle pour désélectionner immédiatement le produit
        await tester.tap(deleteProductIcon.first);
        await tester.pumpAndSettle();

        // Le produit doit être retiré du panier et la barre du panier disparaître
        expect(find.text('Voir mon panier'), findsNothing);

        // La carte produit doit avoir retrouvé son état initial non sélectionné (bouton +)
        expect(find.byIcon(Icons.add), findsWidgets);
      },
    );

    testWidgets(
      '3. Ajout d\'un produit personnalisé par saisie manuelle et mise à jour du panier',
      (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Cliquer sur le bouton « + Produit personnalisé »
        await tester.tap(find.text('+ Produit personnalisé'));
        await tester.pumpAndSettle();

        // Formulaire ouvert
        expect(find.text('Article personnalisé ✍️'), findsOneWidget);

        // Saisir les champs obligatoires
        final textFields = find.byType(TextField);
        await tester.enterText(textFields.at(1), 'Chbiki artisanal'); // Nom
        await tester.enterText(textFields.at(2), '3'); // Quantité
        await tester.enterText(
          textFields.at(3),
          'Traditionnel sans sel',
        ); // Description

        // Valider l'ajout
        await tester.tap(find.text('Ajouter'));
        await tester.pumpAndSettle();

        // Le panier est mis à jour immédiatement
        expect(find.text('3 articles au panier'), findsOneWidget);
        expect(find.text('Liste prête 🛒'), findsOneWidget);
      },
    );

    testWidgets(
      '4. Suppression d\'un article personnalisé depuis le panier modal',
      (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Ajouter un article personnalisé
        await tester.tap(find.text('+ Produit personnalisé'));
        await tester.pumpAndSettle();

        final textFields = find.byType(TextField);
        await tester.enterText(textFields.at(1), 'Huile d\'olive kabyle');
        await tester.enterText(textFields.at(2), '2');
        await tester.tap(find.text('Ajouter'));
        await tester.pumpAndSettle();

        expect(find.text('2 articles au panier'), findsOneWidget);

        // Ouvrir le panier
        await tester.tap(find.text('Voir mon panier'));
        await tester.pumpAndSettle();

        // Vérifier le badge « Sur mesure »
        expect(find.text('Sur mesure'), findsOneWidget);
        expect(find.text('Huile d\'olive kabyle'), findsOneWidget);

        // Supprimer l'article via l'icône poubelle dans le panier
        final trashIcons = find.byIcon(Icons.delete_outline);
        expect(trashIcons, findsWidgets);
        await tester.tap(trashIcons.first);
        await tester.pumpAndSettle();

        // Panier vide dans le modal
        expect(
          find.text(
            'Votre panier est vide.\nSélectionnez des articles dans le catalogue.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('GESTION ET ANNULATION DE COMMANDE CLIENT', () {
    test(
      '5. Le client peut annuler une commande encore en attente (pending)',
      () async {
        final errand = ErrandModel(
          errandId: 'errand_pending_1',
          clientId: 'client_owner',
          storeName: 'Supérette El Amel',
          deliveryAddress: 'Hydra, Alger',
          estimatedBudget: 2500,
          securePin: '1234',
          status: ErrandStatus.pending,
        );
        await errandService.createErrand(errand);

        // Annulation
        await errandService.cancelErrand(
          errandId: 'errand_pending_1',
          clientId: 'client_owner',
          reason: 'Erreur d\'adresse',
        );

        final updated = await errandService.getErrand('errand_pending_1');
        expect(updated?.status, equals(ErrandStatus.cancelled));
      },
    );

    test('6. Une commande annulée disparaît du radar des shoppeurs', () async {
      final errand = ErrandModel(
        errandId: 'errand_radar_1',
        clientId: 'client_owner',
        storeName: 'Magasin Alger',
        deliveryAddress: 'Bab El Oued',
        estimatedBudget: 1500,
        securePin: '5678',
        status: ErrandStatus.pending,
      );
      await errandService.createErrand(errand);

      var pendingList = await errandService.streamPendingErrands().first;
      expect(pendingList.map((e) => e.errandId), contains('errand_radar_1'));

      // Annulation
      await errandService.cancelErrand(
        errandId: 'errand_radar_1',
        clientId: 'client_owner',
      );

      pendingList = await errandService.streamPendingErrands().first;
      expect(
        pendingList.map((e) => e.errandId),
        isNot(contains('errand_radar_1')),
      );
    });

    test(
      '7. Un tiers ne peut pas annuler la commande d\'un autre client',
      () async {
        final errand = ErrandModel(
          errandId: 'errand_auth_test',
          clientId: 'client_legitime',
          storeName: 'Boucherie',
          deliveryAddress: 'Alger',
          estimatedBudget: 4000,
          securePin: '9999',
          status: ErrandStatus.pending,
        );
        await errandService.createErrand(errand);

        expect(
          () => errandService.cancelErrand(
            errandId: 'errand_auth_test',
            clientId: 'client_usurpateur',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('unauthorized'),
            ),
          ),
        );
      },
    );

    test(
      '8. Une commande terminée (completed) ne peut pas être annulée',
      () async {
        final errand = ErrandModel(
          errandId: 'errand_completed_test',
          clientId: 'client_owner',
          storeName: 'Supérette',
          deliveryAddress: 'Alger',
          estimatedBudget: 1200,
          securePin: '1111',
          status: ErrandStatus.completed,
        );
        await errandService.createErrand(errand);

        expect(
          () => errandService.cancelErrand(
            errandId: 'errand_completed_test',
            clientId: 'client_owner',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('cannot_cancel_completed'),
            ),
          ),
        );
      },
    );

    test('9. Une erreur réseau lève une exception sans faux succès', () async {
      errandService.simulateNetworkError = true;

      expect(
        () => errandService.cancelErrand(
          errandId: 'any_errand',
          clientId: 'any_client',
        ),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('AFFICHAGE CÔTÉ SHOPPER (ShoppingModeScreen)', () {
    testWidgets(
      '10. Le shoppeur voit le badge « Produit personnalisé » et les détails de l\'article',
      (tester) async {
        final errand = const ErrandModel(
          errandId: 'errand_shopper_test',
          clientId: 'client_test',
          storeName: 'Supermarché Ardis',
          deliveryAddress: 'Mohammadia',
          estimatedBudget: 3500,
          securePin: '4321',
          status: ErrandStatus.shopping,
        );

        final customItem = const ErrandItemModel(
          itemId: 'item_custom_1',
          name: 'Fromage de chèvre frais',
          quantity: 2.0,
          unit: 'kg',
          notes: 'Format sous vide de préférence',
          isCustom: true,
          brand: 'Terroir Algérien',
          photoUrl: 'https://example.com/fromage.jpg',
          status: ErrandItemStatus.pending,
        );

        errandService.mockErrands[errand.errandId] = errand;
        errandService.mockItems[errand.errandId] = [customItem];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: ShoppingModeScreen(
              errand: errand,
              errandService: errandService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Vérifier le nom et les détails
        expect(find.text('Fromage de chèvre frais'), findsOneWidget);
        expect(find.text('2 kg'), findsOneWidget);
        expect(
          find.text('Note client : Format sous vide de préférence'),
          findsOneWidget,
        );
        expect(find.text('Marque : Terroir Algérien'), findsOneWidget);

        // Vérifier le badge Produit personnalisé
        expect(find.text('Produit personnalisé ✍️'), findsOneWidget);

        // Vérifier la présence du bouton Trouvé
        expect(find.text('Trouvé'), findsOneWidget);
      },
    );
  });
}
