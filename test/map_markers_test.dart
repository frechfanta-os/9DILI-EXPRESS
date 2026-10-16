import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dili_express/ui/widgets/map_markers.dart';

void main() {
  group('Marqueurs Cartographiques (MapLibre & FlutterMap)', () {
    testWidgets('Rendu du ShopperMarkerWidget avec orientation', (tester) async {
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

    testWidgets('Rendu du ClientDestinationMarkerWidget avec adresse', (tester) async {
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
            body: StoreMarkerWidget(
              storeName: 'Supérette El Biar',
              size: 48.0,
            ),
          ),
        ),
      );

      expect(find.byType(StoreMarkerWidget), findsOneWidget);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      expect(find.text('Supérette El Biar'), findsOneWidget);
    });

    test('Génération des bitmaps PNG pour MapLibre Native SymbolLayer', () async {
      final shopperBytes = await MapMarkerBitmapGenerator.generateShopperMarkerBytes(
        width: 64,
        height: 64,
      );
      expect(shopperBytes.isNotEmpty, isTrue);
      // Signature magique PNG : 0x89 0x50 0x4E 0x47
      expect(shopperBytes.sublist(0, 4), equals([0x89, 0x50, 0x4E, 0x47]));

      final destinationBytes = await MapMarkerBitmapGenerator.generateDestinationMarkerBytes(
        width: 64,
        height: 64,
      );
      expect(destinationBytes.isNotEmpty, isTrue);
      expect(destinationBytes.sublist(0, 4), equals([0x89, 0x50, 0x4E, 0x47]));
    });
  });
}
