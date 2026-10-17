import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/user_service.dart';
import 'services/errand_service.dart';
import 'services/product_catalog_service.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/home_screen.dart';

void main() async {
  // 1. Initialisation obligatoire des liaisons Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialisation cohérente de Firebase (stratégie unique anti-duplicate-app)
  // Sur Android, le plugin Google Services et FirebaseInitProvider initialisent
  // nativement l'instance [DEFAULT] au démarrage du processus via google-services.json.
  // L'utilisation de options: null sur Android rattache le SDK Flutter à l'instance
  // native sans conflit d'options, tandis que le guard Firebase.apps préserve les hot-restarts.
  if (Firebase.apps.any((app) => app.name == defaultFirebaseAppName)) {
    Firebase.app();
  } else {
    await Firebase.initializeApp(
      options: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? null
          : DefaultFirebaseOptions.currentPlatform,
    );
  }

  // 3. Activation progressive de Firebase App Check
  if (!kIsWeb) {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: const AppleDeviceCheckProvider(),
      );
    } catch (_) {
      // Tolérance gracieuse pour environnements de test / hors-ligne
    }
  }

  runApp(const DiliExpressApp());
}

/// Racine de l'application 9DILI EXPRESS.
class DiliExpressApp extends StatefulWidget {
  const DiliExpressApp({super.key});

  @override
  State<DiliExpressApp> createState() => _DiliExpressAppState();
}

class _DiliExpressAppState extends State<DiliExpressApp> {
  late final UserService _userService;
  late final AuthService _authService;
  late final ErrandService _errandService;
  late final ProductCatalogService _catalogService;

  @override
  void initState() {
    super.initState();
    _userService = UserService();
    _authService = AuthService(userService: _userService);
    _errandService = ErrandService();
    _catalogService = ProductCatalogService.instance;
    _catalogService.loadCatalog();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '9DILI EXPRESS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: StreamBuilder<User?>(
        stream: _authService.authStateChanges,
        builder: (context, snapshot) {
          // État de chargement initial
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppTheme.primaryOrange),
              ),
            );
          }

          // Utilisateur authentifié (Google ou Email)
          if (snapshot.hasData && snapshot.data != null) {
            return HomeScreen(
              authService: _authService,
              userService: _userService,
              errandService: _errandService,
              catalogService: _catalogService,
            );
          }

          // Non connecté : Écran d'authentification
          return AuthScreen(authService: _authService);
        },
      ),
    );
  }
}
