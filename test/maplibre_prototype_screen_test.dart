import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dili_express/services/routing_geocoding_service.dart';
import 'package:dili_express/ui/screens/maplibre_prototype_screen.dart';
import 'package:dili_express/ui/widgets/map_markers.dart';

void main() {
  group('MapLibrePrototypeScreen — Tests du Prototype Isolé', () {
    testWidgets('Rendu de base avec bannière isolée, marqueurs et attribution légale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        MaterialApp(
          home: MapLibrePrototypeScreen(
            mapBuilder: (context, state) => Container(
              color: Colors.blueGrey.shade100,
              child: const Center(child: Text('Map Viewport Mock')),
            ),
          ),
        ),
      );

      await tester.pump();

      // Vérification du titre et de la bannière isolée
      expect(find.text('Prototype MapLibre (Isolé)'), findsOneWidget);
      expect(
        find.textContaining('PROTOTYPE MAPLIBRE ISOLÉ'),
        findsOneWidget,
      );

      // Vérification de l'attribution cartographique légale obligatoire
      expect(
        find.textContaining('© OpenStreetMap contributors • OpenFreeMap'),
        findsOneWidget,
      );

      // Vérification des marqueurs personnalisés
      expect(find.byType(Shopper3DMarkerWidget), findsOneWidget);
      expect(find.text('Shopper Test (Alger Centre)'), findsOneWidget);
    });

    testWidgets('Bascule de la visibilité des marqueurs de test',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        MaterialApp(
          home: MapLibrePrototypeScreen(
            mapBuilder: (context, state) => const SizedBox(),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(Shopper3DMarkerWidget), findsOneWidget);

      // Clic sur l'icône calques pour masquer
      await tester.tap(find.byTooltip('Basculer Marqueurs'));
      await tester.pump();
      expect(find.byType(ShopperMarkerWidget), findsNothing);

      // Clic à nouveau pour réafficher
      await tester.tap(find.byTooltip('Basculer Marqueurs'));
      await tester.pump();
      expect(find.byType(Shopper3DMarkerWidget), findsOneWidget);
    });

    testWidgets('Gestion et affichage de l\'état d\'erreur avec réessai',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      final key = GlobalKey<MapLibrePrototypeState>();

      await tester.pumpWidget(
        MaterialApp(
          home: MapLibrePrototypeScreen(
            key: key,
            mapBuilder: (context, state) => const SizedBox(),
          ),
        ),
      );

      await tester.pump();

      // Simulation d'une perte réseau / échec de chargement des tuiles
      key.currentState!.simulateError('Délai d\'attente dépassé (Timeout)');
      await tester.pump();

      expect(find.text('Échec du chargement de la carte'), findsOneWidget);
      expect(find.text('Délai d\'attente dépassé (Timeout)'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);

      // Clic sur Réessayer
      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      expect(find.text('Chargement d\'OpenFreeMap Liberty...'), findsOneWidget);
    });

    testWidgets('Calcul de l\'estimation locale résiliente (Offline Fallback)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        MaterialApp(
          home: MapLibrePrototypeScreen(
            mapBuilder: (context, state) => const SizedBox(),
          ),
        ),
      );

      await tester.pump();

      // Clic sur le bouton de calcul d'estimation locale
      await tester.tap(find.text('Calculer estimation locale (Offline Fallback)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Distance :'), findsOneWidget);
      expect(find.textContaining('Durée :'), findsOneWidget);
      expect(
        find.textContaining('Calcul local estimatif — Aucun appel réseau'),
        findsOneWidget,
      );
    });
  });

  group('Routing & Geocoding Service Contracts', () {
    test('FallbackLocalRoutingService calcule une distance et durée positives', () async {
      final service = FallbackLocalRoutingService();
      const origin = GeoCoordinate(latitude: 36.7725, longitude: 3.0588); // Alger Grande Poste
      const destination = GeoCoordinate(latitude: 36.7645, longitude: 3.0535); // Didouche Mourad

      final result = await service.calculateRoute(origin: origin, destination: destination);

      expect(result, isNotNull);
      expect(result!.distanceMeters, greaterThan(500));
      expect(result.distanceMeters, lessThan(3000));
      expect(result.durationSeconds, greaterThan(30));
      expect(result.isFallbackEstimation, isTrue);
      expect(result.formattedDistance.contains('km') || result.formattedDistance.contains('m'), isTrue);
    });
  });
}
