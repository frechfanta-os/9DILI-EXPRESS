import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import '../ui/theme/app_theme.dart';

/// Résultat de la vérification des prérequis pour activer le Mode Shoppeur.
class ShopperPrerequisitesResult {
  final bool isEligible;
  final bool hasFullName;
  final bool hasValidPhone;
  final bool hasTransport;
  final List<String> missingPrerequisites;

  const ShopperPrerequisitesResult({
    required this.isEligible,
    required this.hasFullName,
    required this.hasValidPhone,
    required this.hasTransport,
    required this.missingPrerequisites,
  });

  @override
  String toString() {
    return 'ShopperPrerequisitesResult(eligible: $isEligible, missing: $missingPrerequisites)';
  }
}

/// Service centralisant la gestion du mode d'interface (Client vs Shopper).
/// - Un seul compte Firebase Auth et un seul profil Firestore.
/// - Persistance de la préférence dans SharedPreferences ('preferred_app_mode').
/// - Réactivité immédiate via ValueNotifier sans déconnexion ni création de compte secondaire.
/// - Contrôle strict des prérequis Shopper avant activation.
class UserModeService {
  static final UserModeService _singleton = UserModeService._internal();
  static UserModeService get instance => _singleton;

  UserModeService._internal()
    : _modeNotifier = ValueNotifier<AppMode>(AppMode.client);

  /// Constructeur pour injection ou tests unitaires.
  @visibleForTesting
  UserModeService.forTesting({
    SharedPreferences? prefs,
    AppMode initialMode = AppMode.client,
  }) : _modeNotifier = ValueNotifier<AppMode>(initialMode) {
    _prefs = prefs;
  }

  static const String prefKey = 'preferred_app_mode';

  SharedPreferences? _prefs;
  final ValueNotifier<AppMode> _modeNotifier;

  /// Notifier écoutable pour la réactivité du thème et de l'interface.
  ValueListenable<AppMode> get modeNotifier => _modeNotifier;

  /// Mode d'interface actif actuel.
  AppMode get currentMode => _modeNotifier.value;

  bool get isClient => currentMode == AppMode.client;
  bool get isShopper => currentMode == AppMode.shopper;

  /// Initialise la préférence de mode depuis SharedPreferences.
  Future<void> init({
    SharedPreferences? customPrefs,
    AppMode? defaultMode,
    UserModel? initialUser,
  }) async {
    _prefs = customPrefs ?? await SharedPreferences.getInstance();
    final saved = _prefs?.getString(prefKey);

    if (saved == 'shopper') {
      // Vérifier les droits du profil si l'utilisateur est déjà connu
      if (initialUser != null &&
          !checkShopperPrerequisites(initialUser).isEligible) {
        _modeNotifier.value = AppMode.client;
        await _prefs?.setString(prefKey, 'client');
      } else {
        _modeNotifier.value = AppMode.shopper;
      }
    } else if (saved == 'client') {
      _modeNotifier.value = AppMode.client;
    } else {
      // Aucune préférence : si le rôle initial est shopper, démarrer en shopper, sinon client
      if (initialUser?.role == 'shopper') {
        _modeNotifier.value = AppMode.shopper;
      } else {
        _modeNotifier.value = defaultMode ?? AppMode.client;
      }
    }
  }

  /// Change le mode actif et persiste le choix dans SharedPreferences.
  Future<void> setMode(AppMode mode) async {
    if (_modeNotifier.value == mode) return;
    _modeNotifier.value = mode;

    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(
        prefKey,
        mode == AppMode.shopper ? 'shopper' : 'client',
      );
    } catch (_) {
      // Tolérance gracieuse en environnement de test sans SharedPreferences mock
    }
  }

  /// Bascule entre Client et Shopper si les prérequis sont respectés.
  Future<bool> toggleMode(UserModel user) async {
    if (isClient) {
      final prereq = checkShopperPrerequisites(user);
      if (!prereq.isEligible) {
        return false;
      }
      await setMode(AppMode.shopper);
      return true;
    } else {
      await setMode(AppMode.client);
      return true;
    }
  }

  /// Vérifie les prérequis actuels pour utiliser le Mode Shopper :
  /// 1. Profil avec nom complet renseigné.
  /// 2. Numéro de téléphone vérifié/valide (format national algérien ou international).
  /// 3. Moyen de transport configuré.
  ShopperPrerequisitesResult checkShopperPrerequisites(UserModel user) {
    final hasFullName =
        user.fullName.trim().isNotEmpty &&
        user.fullName.trim() != 'Utilisateur';
    final hasValidPhone = user.hasValidPhone;
    final hasTransport = user.transportType.trim().isNotEmpty;

    final missing = <String>[];
    if (!hasFullName) {
      missing.add('Nom complet renseigné');
    }
    if (!hasValidPhone) {
      missing.add('Numéro de téléphone valide (requis pour joindre le client)');
    }
    if (!hasTransport) {
      missing.add('Moyen de transport (vélo, scooter, moto, voiture, piéton)');
    }

    final isEligible = hasFullName && hasValidPhone && hasTransport;

    return ShopperPrerequisitesResult(
      isEligible: isEligible,
      hasFullName: hasFullName,
      hasValidPhone: hasValidPhone,
      hasTransport: hasTransport,
      missingPrerequisites: missing,
    );
  }

  /// Réinitialise l'état pour les tests automatisés.
  @visibleForTesting
  void resetForTesting({AppMode defaultMode = AppMode.client}) {
    _modeNotifier.value = defaultMode;
  }
}
