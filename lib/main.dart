import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/user_service.dart';
import 'services/errand_service.dart';
import 'services/notification_service.dart';
import 'services/notification_dispatch_service.dart';
import 'services/product_catalog_service.dart';
import 'services/user_mode_service.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/delivery_tracking_screen.dart';

/// Handler de messages FCM en arrière-plan (application fermée ou en tâche de fond).
/// Doit impérativement être une fonction de haut niveau (top-level) annotée.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    'FCM background message reçu: ${message.messageId} (data: ${message.data})',
  );
}

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

    // 4. Enregistrement du handler d'arrière-plan FCM
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('FirebaseMessaging onBackgroundMessage error: $e');
    }
  }

  runApp(const DiliExpressApp());
}

/// Racine de l'application 9DILI EXPRESS.
class DiliExpressApp extends StatefulWidget {
  final NotificationService? notificationService;
  final NotificationDispatchService? dispatchService;
  final AuthService? authService;
  final UserService? userService;
  final ErrandService? errandService;
  final ProductCatalogService? catalogService;

  const DiliExpressApp({
    super.key,
    this.notificationService,
    this.dispatchService,
    this.authService,
    this.userService,
    this.errandService,
    this.catalogService,
  });

  @override
  State<DiliExpressApp> createState() => _DiliExpressAppState();
}

class _DiliExpressAppState extends State<DiliExpressApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late final UserService _userService;
  late final AuthService _authService;
  late final NotificationDispatchService _dispatchService;
  late final NotificationService _notificationService;
  late final ErrandService _errandService;
  late final ProductCatalogService _catalogService;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<ErrandNotificationPayload>? _foregroundSub;

  @override
  void initState() {
    super.initState();
    _userService = widget.userService ?? UserService();
    _authService = widget.authService ?? AuthService(userService: _userService);
    _dispatchService = widget.dispatchService ?? NotificationDispatchService();
    _notificationService = widget.notificationService ?? NotificationService();
    _errandService =
        widget.errandService ??
        ErrandService(notificationDispatchService: _dispatchService);
    _catalogService = widget.catalogService ?? ProductCatalogService.instance;
    _catalogService.loadCatalog();
    UserModeService.instance.init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestStartupPermissions();
    });
    _setupNotificationListeners();
  }

  Future<void> _requestStartupPermissions() async {
    if (kIsWeb) return;
    try {
      // 1. Demande proactive des permissions essentielles via PermissionHandler
      // Notifications (Android 13+ / API 33+)
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      // Caméra (pour le scan des tickets de caisse)
      if (await Permission.camera.isDenied) {
        await Permission.camera.request();
      }

      // 2. Demande explicite de géolocalisation native via Geolocator
      final locationStatus = await Geolocator.checkPermission();
      if (locationStatus == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint('Startup permissions request error: $e');
    }
  }

  void _setupNotificationListeners() {
    // 1. Écoute du cycle d'authentification pour brancher/débrancher le token FCM
    _authSub = _authService.authStateChanges.listen((user) async {
      if (user != null) {
        debugPrint(
          'DiliExpressApp: Utilisateur authentifié ${user.uid}, initialisation des notifications.',
        );
        await _notificationService.initializeForUser(user.uid);
      } else {
        debugPrint(
          'DiliExpressApp: Utilisateur déconnecté, révocation des notifications.',
        );
        await _notificationService.unregisterUser();
      }
    });

    // 2. Écoute des notifications reçues au premier plan (Foreground)
    _foregroundSub = _notificationService.onForegroundNotification.listen((
      payload,
    ) {
      if (payload.title != null || payload.body != null) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              '${payload.title ?? '9DILI EXPRESS'}: ${payload.body ?? ''}',
            ),
            backgroundColor: AppTheme.primaryOrange,
            duration: const Duration(seconds: 4),
            action: payload.errandId != null
                ? SnackBarAction(
                    label: 'Voir',
                    textColor: Colors.white,
                    onPressed: () => _navigateToErrand(payload.errandId!),
                  )
                : null,
          ),
        );
      }
    });

    // 3. Gestion du clic sur notification (App en arrière-plan)
    if (!kIsWeb) {
      try {
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          final errandId =
              message.data['errandId'] ?? message.data['errand_id'];
          if (errandId != null) {
            _navigateToErrand(errandId.toString());
          }
        });

        // 4. Gestion du clic sur notification (App tuée / démarrage à froid)
        FirebaseMessaging.instance
            .getInitialMessage()
            .then((message) {
              if (message != null) {
                final errandId =
                    message.data['errandId'] ?? message.data['errand_id'];
                if (errandId != null) {
                  _navigateToErrand(errandId.toString());
                }
              }
            })
            .catchError((e) {
              debugPrint('getInitialMessage error: $e');
            });
      } catch (e) {
        debugPrint('FCM interaction listeners setup error: $e');
      }
    }
  }

  Future<void> _navigateToErrand(String errandId) async {
    debugPrint(
      'Navigation vers la course $errandId suite à un clic notification',
    );
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    try {
      final errand = await _errandService.getErrand(errandId);
      if (errand != null && nav.mounted) {
        nav.push(
          MaterialPageRoute(
            builder: (ctx) => DeliveryTrackingScreen(
              errand: errand,
              errandService: _errandService,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Navigation notification impossible: $e');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _foregroundSub?.cancel();
    _notificationService.dispose();
    _dispatchService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppMode>(
      valueListenable: UserModeService.instance.modeNotifier,
      builder: (context, activeMode, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _scaffoldMessengerKey,
          title: '9DILI EXPRESS',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.themeFor(activeMode),
          home: StreamBuilder<User?>(
            stream: _authService.authStateChanges,
            builder: (context, snapshot) {
              // État de chargement initial
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryFor(activeMode),
                    ),
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
                  notificationService: _notificationService,
                );
              }

              // Non connecté : Écran d'authentification
              return AuthScreen(authService: _authService);
            },
          ),
        );
      },
    );
  }
}
