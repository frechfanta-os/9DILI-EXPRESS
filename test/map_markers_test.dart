import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dili_express/ui/widgets/map_markers.dart';

void main() {
  group('Marqueurs Cartographiques (MapLibre & FlutterMap)', () {
    testWidgets('Rendu du ShopperMarkerWidget avec orientation', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShopperMarkerWidget(
              heading: 45.0,
              isMoving: true,
              size: 48.0,
            ),
          ),
        ),
      );

      expect(find.byType(ShopperMarkerWidget), findsOneWidget);
      expect(find.byIcon(Icons.delivery_dining), findsOneWidget);
    });

    testWidgets('Rendu du ClientDestinationMarkerWidget avec adresse', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ClientDestinationMarkerWidget(
              addressSnippet: 'Didouche Mourad, Alger',
              size: 48.0,
            ),
          ),
        ),
      );

      expect(find.byType(ClientDestinationMarkerWidget), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.text('Didouche Mourad, Alger'), findsOneWidget);
    });

    testWidgets('Rendu du StoreMarkerWidget avec enseigne', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StoreMarkerWidget(storeName: 'Supérette El Biar', size: 48.0),
          ),
        ),
      );

      expect(find.byType(StoreMarkerWidget), findsOneWidget);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      expect(find.text('Supérette El Biar'), findsOneWidget);
    });

    test(
      'Génération des bitmaps PNG pour MapLibre Native SymbolLayer',
      () async {
        final shopperBytes =
            await MapMarkerBitmapGenerator.generateShopperMarkerBytes(
              width: 64,
              height: 64,
            );
        expect(shopperBytes.isNotEmpty, isTrue);
        // Signature magique PNG : 0x89 0x50 0x4E 0x47
        expect(shopperBytes.sublist(0, 4), equals([0x89, 0x50, 0x4E, 0x47]));

        final destinationBytes =
            await MapMarkerBitmapGenerator.generateDestinationMarkerBytes(
              width: 64,
              height: 64,
            );
        expect(destinationBytes.isNotEmpty, isTrue);
        expect(
          destinationBytes.sublist(0, 4),
          equals([0x89, 0x50, 0x4E, 0x47]),
        );
      },
    );

    testWidgets('Rendu du Shopper3DMarkerWidget avec fallback', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Shopper3DMarkerWidget(heading: 90.0, size: 54.0),
          ),
        ),
      );

      expect(find.byType(Shopper3DMarkerWidget), findsOneWidget);
    });

    testWidgets(
      'Rendu du ClientDestination3DMarkerWidget avec adresse et fallback',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ClientDestination3DMarkerWidget(
                addressSnippet: 'Bab El Oued, Alger',
                size: 54.0,
              ),
            ),
          ),
        );

        expect(find.byType(ClientDestination3DMarkerWidget), findsOneWidget);
        expect(find.text('Bab El Oued, Alger'), findsOneWidget);
      },
    );

    testWidgets('Rendu du Store3DMarkerWidget avec enseigne et fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Store3DMarkerWidget(
              storeName: 'Supérette Didouche',
              size: 54.0,
            ),
          ),
        ),
      );

      expect(find.byType(Store3DMarkerWidget), findsOneWidget);
      expect(find.text('Supérette Didouche'), findsOneWidget);
    });

    test(
      'loadAssetMarkerBytes charge un PNG valide ou bascule sur fallback',
      () async {
        final bytes = await MapMarkerBitmapGenerator.loadAssetMarkerBytes(
          MapMarkerAssets.shopperOrange3D01,
          isShopper: true,
        );
        expect(bytes.isNotEmpty, isTrue);
        // Signature magique PNG
        expect(bytes.sublist(0, 4), equals([0x89, 0x50, 0x4E, 0x47]));
      },
    );
  });
}
