import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:dili_express/models/errand_item_model.dart';
import 'package:dili_express/models/user_model.dart';
import 'package:dili_express/services/catalog_service.dart';
import 'package:dili_express/services/map_tracking_service.dart';

void main() {
  group('1. Catalogue Produits Algériens & Catégories', () {
    test(
      'Contient exactement 11 catégories officielles avec noms FR et AR',
      () {
        expect(CatalogService.defaultCategories.length, equals(11));
        for (final cat in CatalogService.defaultCategories) {
          expect(cat.categoryId, isNotEmpty);
          expect(cat.nameFr, isNotEmpty);
          expect(cat.nameAr, isNotEmpty);
          expect(cat.iconName, isNotEmpty);
        }
      },
    );

    test('Contient les produits emblématiques du terroir algérien', () {
      expect(CatalogService.defaultProducts.length, greaterThanOrEqualTo(20));

      final brands = CatalogService.defaultProducts.map((p) => p.brand).toSet();
      expect(brands, contains('Cevital'));
      expect(brands, contains('Candia / Tchin-Lait'));
      expect(brands, contains('Soummam'));
      expect(brands, contains('Hamoud Boualem'));
      expect(brands, contains('Sim'));
      expect(brands, contains('Safina'));
      expect(brands, contains('Amor Benamor'));
      expect(brands, contains('Ifri'));
    });

    test(
      'Recherche locale de produits par mot-clé (bilingue) et catégorie',
      () {
        final service = CatalogService();

        // Recherche par nom français
        final huiles = service.searchLocalProducts(query: 'Fleurial');
        expect(huiles, isNotEmpty);
        expect(huiles.first.brand, equals('Cevital'));

        // Recherche par marque
        final hamoud = service.searchLocalProducts(query: 'Hamoud');
        expect(hamoud, isNotEmpty);
        expect(hamoud.first.brand, equals('Hamoud Boualem'));

        // Recherche par catégorie
        final boissons = service.searchLocalProducts(categoryId: 'boissons');
        expect(boissons, isNotEmpty);
        for (final p in boissons) {
          expect(p.categoryId, equals('boissons'));
        }
      },
    );

    test('Conversion d\'un produit du catalogue vers ErrandItemModel', () {
      final selecto = CatalogService.defaultProducts.firstWhere(
        (p) => p.productId == 'bs_02',
      );
      final item = CatalogService.toErrandItem(selecto, quantity: 2.0);

      expect(item.name, contains('Hamoud Boualem Selecto'));
      expect(item.quantity, equals(2.0));
      expect(item.unit, equals('bouteille'));
      expect(item.notes, contains('Hamoud Boualem'));
      expect(item.status, equals(ErrandItemStatus.pending));
    });
  });

  group('2. Modes de Transport Shopper & Rayon d\'action', () {
    test('Valeurs d\'énumération et conversion String <-> Enum', () {
      expect(ShopperTransportType.values.length, equals(5));
      expect(ShopperTransportType.values.map((e) => e.name).toList(), [
        'walking',
        'bicycle',
        'scooter',
        'motorcycle',
        'car',
      ]);
    });

    test('Sérialisation UserModel avec transportType et searchRadiusKm', () {
      final user = UserModel(
        uid: 'shopper_123',
        fullName: 'Karim Shopper',
        email: 'shopper@test.dz',
        role: 'shopper',
        transportType: 'car',
        searchRadiusKm: 15.0,
      );

      final map = user.toMap();
      expect(map['transportType'], equals('car'));
      expect(map['searchRadiusKm'], equals(15.0));

      final restored = UserModel.fromMap(map, documentId: 'shopper_123');
      expect(restored.transportType, equals('car'));
      expect(restored.transport, equals(ShopperTransportType.car));
      expect(restored.searchRadiusKm, equals(15.0));
      expect(restored.transport.labelFr, equals('En voiture'));
    });

    test('Vérification de la capacité de transport selon le panier', () {
      final shopperWalk = UserModel(
        uid: 's1',
        fullName: 'Yacine Marcheur',
        email: 'w@test.dz',
        transportType: 'walking',
      );
      final shopperCar = UserModel(
        uid: 's2',
        fullName: 'Livreur Automobiliste',
        email: 'c@test.dz',
        transportType: 'car',
      );

      // Panier léger (5kg <= 5kg max marche)
      expect(shopperWalk.canCarry(5.0), isTrue);
      // Panier lourd (15kg > 5kg max marche mais <= 80kg max voiture)
      expect(shopperWalk.canCarry(15.0), isFalse);
      expect(shopperCar.canCarry(15.0), isTrue);
    });
  });

  group('3. Cartographie OpenStreetMap & Calculs Distance/ETA', () {
    test('Calcul de distance orthodromique (Alger Centre -> Bab Ezzouar)', () {
      const algerCentre = LatLng(36.7538, 3.0588);
      const babEzzouar = LatLng(36.7208, 3.1834);

      final distanceKm = MapTrackingService.calculateDistanceKm(
        algerCentre,
        babEzzouar,
      );
      // Distance corrigée ~14-16 km avec coefficient urbain
      expect(distanceKm, greaterThan(10.0));
      expect(distanceKm, lessThan(20.0));
    });

    test('Estimation du trajet et de la durée selon le mode de transport', () {
      const p1 = LatLng(36.7538, 3.0588);
      const p2 = LatLng(36.7538, 3.0700); // ~1.5 km urbain

      final estimateWalk = MapTrackingService.estimateTrip(
        shopperPos: p1,
        destinationPos: p2,
        transportType: ShopperTransportType.walking,
      );
      final estimateMoto = MapTrackingService.estimateTrip(
        shopperPos: p1,
        destinationPos: p2,
        transportType: ShopperTransportType.motorcycle,
      );

      expect(estimateWalk.durationMinutes, greaterThanOrEqualTo(10));
      expect(estimateMoto.durationMinutes, lessThanOrEqualTo(10));
      expect(
        estimateMoto.durationMinutes,
        lessThan(estimateWalk.durationMinutes),
      );
      expect(estimateMoto.suggestedCommission, greaterThanOrEqualTo(250.0));
    });

    test('Génération de la couche de tuiles OpenStreetMap avec User-Agent conforme', () {
      final tileLayer = MapTrackingService.buildOsmTileLayer();
      expect(
        tileLayer.urlTemplate,
        equals('https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
      );
      expect(
        MapTrackingService.userAgentPackageName,
        equals('com.ghdinteractivestudio.dili_express'),
      );
    });
  });
}
