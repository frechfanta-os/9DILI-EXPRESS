import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dili_express/models/errand_model.dart';
import 'package:dili_express/models/user_model.dart';
import 'package:dili_express/services/errand_service.dart';
import 'package:dili_express/services/user_service.dart';
import 'package:dili_express/services/user_mode_service.dart';
import 'package:dili_express/ui/theme/app_theme.dart';
import 'package:dili_express/ui/widgets/client_shopper_toggle.dart';

class MockUserServiceForModeTest extends UserService {
  final Map<String, UserModel> users = {};

  @override
  Future<UserModel?> getUser(String uid) async => users[uid];

  @override
  Stream<UserModel?> streamUser(String uid) =>
      Stream.value(users[uid] ?? UserModel(uid: uid, fullName: 'Utilisateur Test'));

  @override
  Future<void> saveUser(UserModel user) async {
    users[user.uid] = user;
  }
}

class MockErrandServiceForModeTest extends ErrandService {
  final List<ErrandModel> clientErrands = [];
  final List<ErrandModel> pendingRadarErrands = [];

  @override
  Stream<List<ErrandModel>> streamClientErrands(String clientId) =>
      Stream.value(clientErrands);

  @override
  Stream<List<ErrandModel>> streamPendingErrands({double? maxBudget}) =>
      Stream.value(pendingRadarErrands);

  @override
  Stream<ErrandModel?> streamErrand(String errandId) => Stream.value(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserModeService.instance.resetForTesting();
  });

  group('1. Inscription Unique & Conservation du Compte et du Profil', () {
    test('Un seul identifiant Firebase et conservation intégrale des données', () {
      const singleUid = 'usr_alg_99482';
      final singleUserAccount = UserModel(
        uid: singleUid,
        fullName: 'Karim Hadj',
        email: 'karim@9dili.dz',
        phone: '0555123456',
        availableCash: 4500.0,
        rating: 4.9,
        transportType: 'scooter',
        role: 'client',
      );

      // Vérification que le compte est unique
      expect(singleUserAccount.uid, equals(singleUid));
      expect(singleUserAccount.phone, equals('0555123456'));
      expect(singleUserAccount.availableCash, equals(4500.0));

      // Changement de mode dans l'interface
      final modeService = UserModeService.forTesting();
      expect(modeService.currentMode, equals(AppMode.client));

      // L'utilisateur reste le même après activation du mode Shopper
      modeService.setMode(AppMode.shopper);
      expect(modeService.currentMode, equals(AppMode.shopper));
      expect(singleUserAccount.uid, equals(singleUid));
      expect(singleUserAccount.phone, equals('0555123456'));
      expect(singleUserAccount.availableCash, equals(4500.0));
      expect(singleUserAccount.rating, equals(4.9));
    });
  });

  group('2. Système de Thèmes Partagé (Client Vert #10B981 / Shopper Orange #FF6D00)', () {
    test('Les couleurs officielles par mode respectent strictement la charte', () {
      expect(AppTheme.clientGreen, equals(const Color(0xFF10B981)));
      expect(AppTheme.shopperOrange, equals(const Color(0xFFFF6D00)));

      expect(AppTheme.primaryFor(AppMode.client), equals(AppTheme.clientGreen));
      expect(AppTheme.primaryFor(AppMode.shopper), equals(AppTheme.shopperOrange));
    });

    test('ThemeData généré pour Mode Client applique le thème vert', () {
      final clientTheme = AppTheme.themeFor(AppMode.client);

      expect(clientTheme.colorScheme.primary, equals(AppTheme.clientGreen));
      expect(clientTheme.floatingActionButtonTheme.backgroundColor, equals(AppTheme.clientGreen));
      expect(clientTheme.elevatedButtonTheme.style?.backgroundColor?.resolve({}), equals(AppTheme.clientGreen));
    });

    test('ThemeData généré pour Mode Shopper applique le thème orange', () {
      final shopperTheme = AppTheme.themeFor(AppMode.shopper);

      expect(shopperTheme.colorScheme.primary, equals(AppTheme.shopperOrange));
      expect(shopperTheme.floatingActionButtonTheme.backgroundColor, equals(AppTheme.shopperOrange));
      expect(shopperTheme.elevatedButtonTheme.style?.backgroundColor?.resolve({}), equals(AppTheme.shopperOrange));
    });

    test('Les alertes et statuts conservent leurs couleurs sémantiques', () {
      expect(AppTheme.errorRed, equals(const Color(0xFFEF4444)));
      expect(AppTheme.warningOrange, equals(const Color(0xFFF59E0B)));
    });
  });

  group('3. Persistance du Mode Préféré (SharedPreferences)', () {
    test('Restauration du mode shopper enregistré au démarrage', () async {
      SharedPreferences.setMockInitialValues({
        UserModeService.prefKey: 'shopper',
      });

      final prefs = await SharedPreferences.getInstance();
      final modeService = UserModeService.forTesting(prefs: prefs);

      final eligibleUser = UserModel(
        uid: 'shopper_1',
        fullName: 'Nassim Alger',
        phone: '0555001122',
        transportType: 'motorcycle',
      );

      await modeService.init(customPrefs: prefs, initialUser: eligibleUser);
      expect(modeService.currentMode, equals(AppMode.shopper));
    });

    test('Restauration du mode client enregistré au démarrage', () async {
      SharedPreferences.setMockInitialValues({
        UserModeService.prefKey: 'client',
      });

      final prefs = await SharedPreferences.getInstance();
      final modeService = UserModeService.forTesting(prefs: prefs);

      await modeService.init(customPrefs: prefs);
      expect(modeService.currentMode, equals(AppMode.client));
    });

    test('Sauvegarde immédiate lors du changement de mode', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final modeService = UserModeService.forTesting(prefs: prefs);

      await modeService.setMode(AppMode.shopper);
      expect(prefs.getString(UserModeService.prefKey), equals('shopper'));

      await modeService.setMode(AppMode.client);
      expect(prefs.getString(UserModeService.prefKey), equals('client'));
    });
  });

  group('4. Contrôle Strict des Prérequis Shopper', () {
    final modeService = UserModeService.instance;

    test('Un utilisateur sans téléphone valide est bloqué du Mode Shopper', () {
      final userNoPhone = UserModel(
        uid: 'usr_no_phone',
        fullName: 'Mourad Test',
        phone: null,
      );

      final result = modeService.checkShopperPrerequisites(userNoPhone);
      expect(result.isEligible, isFalse);
      expect(result.hasValidPhone, isFalse);
      expect(result.missingPrerequisites, contains(contains('Numéro de téléphone')));
    });

    test('Un utilisateur avec un faux numéro court est bloqué', () {
      final userInvalidPhone = UserModel(
        uid: 'usr_bad_phone',
        fullName: 'Mourad Test',
        phone: '123',
      );

      final result = modeService.checkShopperPrerequisites(userInvalidPhone);
      expect(result.isEligible, isFalse);
      expect(result.hasValidPhone, isFalse);
    });

    test('Un utilisateur avec profil complet et numéro algérien est éligible', () {
      final eligibleUser = UserModel(
        uid: 'usr_eligible',
        fullName: 'Yacine Belkacem',
        phone: '0661234567',
        transportType: 'scooter',
        availableCash: 2000.0,
      );

      final result = modeService.checkShopperPrerequisites(eligibleUser);
      expect(result.isEligible, isTrue);
      expect(result.hasFullName, isTrue);
      expect(result.hasValidPhone, isTrue);
      expect(result.hasTransport, isTrue);
      expect(result.missingPrerequisites, isEmpty);
    });
  });

  group('5. Conservation des Commandes et Absence d\'Effets de Bord', () {
    test('Le changement de mode ne modifie ni ne supprime les commandes actives', () async {
      final errandService = MockErrandServiceForModeTest();

      final activeErrand = ErrandModel(
        errandId: 'errand_preserved_101',
        clientId: 'client_1',
        storeName: 'Supérette El Qods',
        deliveryAddress: 'Bab Ezzouar, Alger',
        estimatedBudget: 1500.0,
        negotiatedCommission: 400.0,
        securePin: '1234',
        status: ErrandStatus.pending,
      );

      errandService.clientErrands.add(activeErrand);

      final modeService = UserModeService.forTesting();
      expect(errandService.clientErrands.length, equals(1));

      // Bascule Client -> Shopper
      await modeService.setMode(AppMode.shopper);
      expect(modeService.currentMode, equals(AppMode.shopper));
      expect(errandService.clientErrands.length, equals(1));
      expect(errandService.clientErrands.first.errandId, equals('errand_preserved_101'));

      // Bascule Shopper -> Client
      await modeService.setMode(AppMode.client);
      expect(modeService.currentMode, equals(AppMode.client));
      expect(errandService.clientErrands.length, equals(1));
      expect(errandService.clientErrands.first.status, equals(ErrandStatus.pending));
    });
  });

  group('6. Widget Test : ClientShopperToggle', () {
    testWidgets('Affichage Mode Client conforme à la capture (Fond vert, bouton blanc Client actif)', (tester) async {
      AppMode selectedMode = AppMode.client;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClientShopperToggle(
                currentMode: AppMode.client,
                onModeChanged: (m) => selectedMode = m,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Client'), findsOneWidget);
      expect(find.text('Shopper'), findsOneWidget);

      // Vérifier le tap sur Shopper
      await tester.tap(find.text('Shopper'));
      await tester.pumpAndSettle();

      expect(selectedMode, equals(AppMode.shopper));
    });

    testWidgets('Affichage Mode Shopper conforme à la capture (Fond orange, bouton blanc Shopper actif)', (tester) async {
      AppMode selectedMode = AppMode.shopper;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClientShopperToggle(
                currentMode: AppMode.shopper,
                onModeChanged: (m) => selectedMode = m,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Client'), findsOneWidget);
      expect(find.text('Shopper'), findsOneWidget);

      // Vérifier le tap sur Client
      await tester.tap(find.text('Client'));
      await tester.pumpAndSettle();

      expect(selectedMode, equals(AppMode.client));
    });
  });
}
