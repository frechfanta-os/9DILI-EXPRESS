import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dili_express/models/errand_model.dart';
import 'package:dili_express/models/errand_item_model.dart';
import 'package:dili_express/services/errand_service.dart';
import 'package:dili_express/services/product_catalog_service.dart';
import 'package:dili_express/ui/screens/create_errand_screen.dart';
import 'package:dili_express/ui/theme/app_theme.dart';

class MockErrandService extends ErrandService {
  ErrandModel? lastCreatedErrand;
  List<ErrandItemModel>? lastCreatedItems;

  @override
  Future<String> createErrand(
    ErrandModel errand, {
    List<ErrandItemModel>? items,
  }) async {
    lastCreatedErrand = errand;
    lastCreatedItems = items;
    return 'mock_errand_123';
  }
}

const testCatalogJson = '''
[
  {
    "sku_id": "DZ-FRESH-0001",
    "barcode": "6130123456789",
    "name_fr": "Pomme de terre blanche (Batata)",
    "name_ar": "بطاطا بيضاء",
    "search_keywords_darja": ["batata", "pomme de terre"],
    "brand": "Marché Souk",
    "category": "Fruits & Légumes",
    "sub_category": "Légumes",
    "is_weighable": true,
    "unit_type": "kg",
    "unit_value": 1,
    "estimated_price_dzd": 85,
    "image_url": "https://example.com/batata.jpg"
  },
  {
    "sku_id": "DZ-FRESH-0002",
    "barcode": null,
    "name_fr": "Carotte fraîche",
    "name_ar": "جزر طازج",
    "search_keywords_darja": ["zroudiya", "carotte"],
    "brand": "Marché Souk",
    "category": "Fruits & Légumes",
    "sub_category": "Légumes",
    "is_weighable": true,
    "unit_type": "kg",
    "unit_value": 1,
    "estimated_price_dzd": 90,
    "image_url": null
  },
  {
    "sku_id": "DZ-BOIS-0001",
    "barcode": "6131112223334",
    "name_fr": "Hamoud Boualem Selecto 1L",
    "name_ar": "حمود بوعلام سيلكتو",
    "search_keywords_darja": ["selecto", "hamoud", "gazouz"],
    "brand": "Hamoud Boualem",
    "category": "Boissons",
    "sub_category": "Sodas & Gazouz",
    "is_weighable": false,
    "unit_type": "bouteille",
    "unit_value": 1,
    "estimated_price_dzd": 110,
    "image_url": null
  },
  {
    "sku_id": "DZ-EPIC-0001",
    "barcode": "6139876543210",
    "name_fr": "Pâtes Tassili Coquillettes 500g",
    "name_ar": "عجائن تاسيلي",
    "search_keywords_darja": ["maqrouna", "pates"],
    "brand": "Tassili",
    "category": "Épicerie Salée",
    "sub_category": "Pâtes & Féculents",
    "is_weighable": false,
    "unit_type": "paquet",
    "unit_value": 1,
    "estimated_price_dzd": 75,
    "image_url": null
  }
]
''';

void main() {
  late ProductCatalogService catalogService;
  late MockErrandService errandService;

  setUp(() async {
    catalogService = ProductCatalogService();
    await catalogService.loadCatalog(rawJsonString: testCatalogJson);
    errandService = MockErrandService();
  });

  tearDown(() {
    catalogService.clear();
  });

  Widget buildTestScreen() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateErrandScreen(
        clientId: 'client_dz_456',
        errandService: errandService,
        catalogService: catalogService,
        initialAddress: '15 Rue Didouche Mourad, Alger',
        initialStoreName: 'Supérette El Amel',
      ),
    );
  }

  group('CreateErrandScreen — Catalogue, Rayons & Panier (Tests Widget)', () {
    testWidgets('1. Affichage des rayons et de la liste de produits après chargement', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Vérification des en-têtes
      expect(find.text('Commander mes courses 🛒'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Tous les rayons'), findsOneWidget);

      // Vérification des catégories / rayons
      expect(find.widgetWithText(ChoiceChip, 'Fruits & Légumes'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Boissons'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Épicerie Salée'), findsOneWidget);

      // Vérification des cartes produits affichées
      expect(find.text('Pomme de terre blanche (Batata)'), findsOneWidget);
      expect(find.text('Hamoud Boualem Selecto 1L'), findsOneWidget);
      expect(find.text('Pâtes Tassili Coquillettes 500g'), findsOneWidget);

      // Vérification des prix et badges
      expect(find.text('85 DA'), findsOneWidget);
      expect(find.text('110 DA'), findsOneWidget);
      expect(find.text('75 DA'), findsOneWidget);
    });

    testWidgets('2. Filtrage des produits par sélection d\'un rayon', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Au départ, tous les rayons sont actifs (4 produits visibles)
      expect(find.text('Pomme de terre blanche (Batata)'), findsOneWidget);
      expect(find.text('Hamoud Boualem Selecto 1L'), findsOneWidget);

      // Clic sur le rayon « Boissons »
      await tester.tap(find.widgetWithText(ChoiceChip, 'Boissons'));
      await tester.pumpAndSettle();

      // Seul le produit du rayon Boissons doit être affiché
      expect(find.text('Hamoud Boualem Selecto 1L'), findsOneWidget);
      expect(find.text('Pomme de terre blanche (Batata)'), findsNothing);
      expect(find.text('Pâtes Tassili Coquillettes 500g'), findsNothing);

      // Retour sur « Tous les rayons »
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tous les rayons'));
      await tester.pumpAndSettle();

      expect(find.text('Pomme de terre blanche (Batata)'), findsOneWidget);
      expect(find.text('Hamoud Boualem Selecto 1L'), findsOneWidget);
    });

    testWidgets('3. Recherche de produit par mot-clé populaire Darja', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Recherche par "maqrouna" (terme Darja pour Pâtes Tassili)
      await tester.enterText(find.byType(TextField).first, 'maqrouna');
      await tester.pumpAndSettle();

      expect(find.text('Pâtes Tassili Coquillettes 500g'), findsOneWidget);
      expect(find.text('Pomme de terre blanche (Batata)'), findsNothing);
      expect(find.text('Hamoud Boualem Selecto 1L'), findsNothing);
    });

    testWidgets('4. Ajout au panier et préservation lors du changement de rayon', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Panier initialement vide (pas de barre en bas)
      expect(find.text('Voir mon panier'), findsNothing);

      // Ajout du premier produit (Pomme de terre)
      final addButtons = find.byIcon(Icons.add);
      expect(addButtons, findsWidgets);
      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();

      // La barre panier doit apparaître avec 1 article
      expect(find.text('1 article au panier'), findsOneWidget);
      expect(find.text('Voir mon panier'), findsOneWidget);

      // Changement de rayon vers « Boissons »
      await tester.tap(find.widgetWithText(ChoiceChip, 'Boissons'));
      await tester.pumpAndSettle();

      // Le panier doit être préservé malgré le changement de filtre/rayon
      expect(find.text('1 article au panier'), findsOneWidget);

      // Ajout d'une bouteille de Selecto
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Le panier contient maintenant 2 articles
      expect(find.text('2 articles au panier'), findsOneWidget);
    });

    testWidgets('5. Test de régression : le catalogue réel ne reste jamais vide', (
      tester,
    ) async {
      // Test avec le catalogue complet national de 2 261 produits
      final realFile = File('assets/data/algeria_full_catalog.json');
      expect(realFile.existsSync(), isTrue);

      final fullCatalogService = ProductCatalogService();
      final fullContent = realFile.readAsStringSync();
      await fullCatalogService.loadCatalog(rawJsonString: fullContent);

      expect(fullCatalogService.productCount, greaterThan(2200));
      expect(fullCatalogService.categories.length, greaterThanOrEqualTo(25));

      final testWidget = MaterialApp(
        theme: AppTheme.lightTheme,
        home: CreateErrandScreen(
          clientId: 'client_real_789',
          errandService: errandService,
          catalogService: fullCatalogService,
        ),
      );

      await tester.pumpWidget(testWidget);
      await tester.pump();

      // Les rayons réels doivent être rendus
      expect(find.widgetWithText(ChoiceChip, 'Tous les rayons'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Fruits & Légumes'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Boissons'), findsOneWidget);

      // Des cartes produits réelles doivent être affichées immédiatement
      expect(find.byType(Card), findsWidgets);
      expect(find.text('Aucun article trouvé dans ce rayon'), findsNothing);
    });
  });
}
