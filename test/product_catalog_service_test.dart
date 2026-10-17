import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dili_express/services/product_catalog_service.dart';

void main() {
  group('ProductCatalogService — Tests Unitaires & Parsing Algérien', () {
    late ProductCatalogService service;

    setUp(() {
      service = ProductCatalogService();
    });

    tearDown(() {
      service.clear();
    });

    const sampleJson = '''
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
        "sku_id": "DZ-EPIC-0002",
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
        "estimated_price_dzd": 70,
        "image_url": "https://example.com/tassili.jpg"
      },
      {
        "sku_id": "DZ-FRESH-0002",
        "barcode": null,
        "name_fr": "Oignon rouge sec",
        "name_ar": "بَصَلٌ أَحْمَرُ",
        "search_keywords_darja": ["bsel", "oignon"],
        "brand": "Marché Souk",
        "category": "Fruits & Légumes",
        "sub_category": "Légumes",
        "is_weighable": true,
        "unit_type": "kg",
        "unit_value": 1,
        "estimated_price_dzd": 60,
        "image_url": null
      }
    ]
    ''';

    test('Chargement et parsing correct du JSON de test', () async {
      await service.loadCatalog(rawJsonString: sampleJson);

      expect(service.isLoaded, isTrue);
      expect(service.productCount, equals(3));
      expect(service.categories, containsAll(['Fruits & Légumes', 'Épicerie Salée']));
    });

    test('Recherche insensible à la casse et tolérance aux accents français', () async {
      await service.loadCatalog(rawJsonString: sampleJson);

      // "pates" sans accent doit trouver "Pâtes Tassili"
      final results1 = service.search('pates');
      expect(results1, isNotEmpty);
      expect(results1.first.nameFr, contains('Pâtes Tassili'));

      // "POMME" en majuscules doit trouver "Pomme de terre"
      final results2 = service.search('POMME');
      expect(results2, isNotEmpty);
      expect(results2.first.skuId, equals('DZ-FRESH-0001'));
    });

    test('Recherche arabe avec et sans voyelles (Tashkeel)', () async {
      await service.loadCatalog(rawJsonString: sampleJson);

      // Recherche sans voyelles "بصل" doit trouver "بَصَلٌ أَحْمَرُ"
      final results = service.search('بصل');
      expect(results, isNotEmpty);
      expect(results.first.nameFr, equals('Oignon rouge sec'));
    });

    test('Recherche par mot-clé Darja populaire', () async {
      await service.loadCatalog(rawJsonString: sampleJson);

      // "maqrouna" (Darja) doit matcher Pâtes Tassili
      final results = service.search('maqrouna');
      expect(results, isNotEmpty);
      expect(results.first.skuId, equals('DZ-EPIC-0002'));
    });

    test('Recherche directe O(1) par code-barres', () async {
      await service.loadCatalog(rawJsonString: sampleJson);

      final product = service.findByBarcode('6130123456789');
      expect(product, isNotNull);
      expect(product!.nameFr, contains('Pomme de terre'));

      final notFound = service.findByBarcode('0000000000000');
      expect(notFound, isNull);
    });

    test('Filtrage par catégorie', () async {
      await service.loadCatalog(rawJsonString: sampleJson);

      final fresh = service.getByCategory('Fruits & Légumes');
      expect(fresh.length, equals(2));

      final filteredSearch = service.search('pomme', categoryFilter: 'Fruits & Légumes');
      expect(filteredSearch.length, equals(1));
    });

    test('Gestion des erreurs de JSON corrompu', () async {
      expect(
        () => service.loadCatalog(rawJsonString: '{"invalid": "json format"}'),
        throwsA(isA<CatalogLoadException>()),
      );
    });

    test('Chargement réel du fichier catalogue complet assets/data/algeria_full_catalog.json', () async {
      final file = File('assets/data/algeria_full_catalog.json');
      expect(file.existsSync(), isTrue);

      final content = await file.readAsString();
      await service.loadCatalog(rawJsonString: content);

      expect(service.isLoaded, isTrue);
      expect(service.productCount, greaterThan(2200));
      expect(service.categories, isNotEmpty);

      // Vérification d'une recherche réelle dans le catalogue national
      final searchResults = service.search('lait');
      expect(searchResults, isNotEmpty);
    });
  });
}
