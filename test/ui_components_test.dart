import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dili_express/ui/theme/app_theme.dart';
import 'package:dili_express/models/errand_model.dart';

void main() {
  Widget buildTestableWidget(
    Widget child, {
    Size surfaceSize = const Size(390, 844),
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(size: surfaceSize),
        child: child,
      ),
    );
  }

  group('1. Audit Visuel — Design System & Tokens UI', () {
    test('Vérification de la palette officielle Stitch V2', () {
      expect(AppTheme.primaryOrange, equals(const Color(0xFFFF6D00)));
      expect(AppTheme.accentGreen, equals(const Color(0xFF10B981)));
      expect(AppTheme.violetSurface, equals(const Color(0xFFEDE9FE)));
      expect(AppTheme.violetAccent, equals(const Color(0xFF8B5CF6)));
      expect(AppTheme.backgroundLight, equals(const Color(0xFFF8FAFC)));
      expect(AppTheme.textDark, equals(const Color(0xFF0F172A)));
    });

    testWidgets('Rendu visuel des boutons Stitch et cartes arrondies', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () {},
                        child: const Text('Bouton Primaire Orange'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Bouton Secondaire'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Bouton Primaire Orange'), findsOneWidget);
      expect(find.text('Bouton Secondaire'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });
  });

  group('2. Audit Visuel — Cartes & Décomposition des Prix DZD', () {
    testWidgets('Affichage transparent des montants et formule Total', (
      tester,
    ) async {
      const errand = ErrandModel(
        errandId: 'errand_ui_01',
        clientId: 'c1',
        storeName: 'Carrefour El Biar',
        deliveryAddress: 'Hydra, Alger',
        estimatedBudget: 3500.0,
        ticketAmount: 3200.50,
        negotiatedCommission: 450.0,
        securePin: '1234',
        status: ErrandStatus.shopping,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: Card(
              color: AppTheme.violetSurface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      errand.storeName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Budget : ${errand.estimatedBudget.toStringAsFixed(0)} DA',
                    ),
                    Text(
                      'Ticket : ${errand.ticketAmount!.toStringAsFixed(2)} DA',
                    ),
                    Text(
                      'Commission : ${errand.negotiatedCommission.toStringAsFixed(0)} DA',
                    ),
                    Text('Total : ${errand.totalAmount.toStringAsFixed(2)} DA'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Carrefour El Biar'), findsOneWidget);
      expect(find.text('Budget : 3500 DA'), findsOneWidget);
      expect(find.text('Ticket : 3200.50 DA'), findsOneWidget);
      expect(find.text('Commission : 450 DA'), findsOneWidget);
      expect(find.text('Total : 3650.50 DA'), findsOneWidget);
    });
  });

  group('3. Audit Visuel — Responsive Multi-Tailles Android', () {
    testWidgets('Format compact Android (360 x 640 dp)', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            appBar: AppBar(title: const Text('9DILI EXPRESS')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    height: 80,
                    color: AppTheme.violetSurface,
                    child: const Center(child: Text('Bannière Adresse')),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {},
                      child: const Text('Créer ma liste'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          surfaceSize: const Size(360, 640),
        ),
      );

      expect(find.text('9DILI EXPRESS'), findsOneWidget);
      expect(find.text('Créer ma liste'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
      ); // Aucune erreur de dépassement (RenderFlex overflow)
    });

    testWidgets('Format standard moderne Pixel 7 (412 x 915 dp)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: ListView(
              children: List.generate(
                5,
                (i) => ListTile(
                  title: Text('Course #$i'),
                  subtitle: const Text('Prix : 1200 DA'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ),
          ),
          surfaceSize: const Size(412, 915),
        ),
      );

      expect(find.text('Course #0'), findsOneWidget);
      expect(find.text('Course #4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('4. Audit Visuel — États de l\'Interface (Vide, Erreur, Succès)', () {
    testWidgets('État vide de liste avec icône et message informatif', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shopping_basket_outlined,
                    size: 48,
                    color: AppTheme.textMuted,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Aucune commande active',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Aucune commande active'), findsOneWidget);
      expect(find.byIcon(Icons.shopping_basket_outlined), findsOneWidget);
    });

    testWidgets('État d\'erreur avec bannière rouge accessible', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: Container(
              padding: const EdgeInsets.all(12),
              color: AppTheme.errorRed.withValues(alpha: 0.1),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: AppTheme.errorRed),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Erreur de connexion au serveur',
                      style: TextStyle(
                        color: AppTheme.errorRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Erreur de connexion au serveur'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });
}
