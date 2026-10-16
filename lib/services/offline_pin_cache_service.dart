import 'package:shared_preferences/shared_preferences.dart';

/// Service de mise en cache locale du code PIN de sécurité (4 chiffres).
///
/// LIMITES DE SÉCURITÉ DU MODE HORS-LIGNE :
/// 1. La validation locale via [verifyPin] est une attestation PROVISOIRE de commodité.
///    Elle permet de poursuivre les opérations physiques en cas de zone blanche (ex: sous-sol, parking).
/// 2. Elle ne constitue en aucun cas une validation serveur définitive.
/// 3. Dès le retour de la connectivité réseau, le règlement [recordOfflineSettlement]
///    doit être réconcilié auprès de Firestore pour garantir l'absence de double clôture.
class OfflinePinCacheService {
  static const String _keyPrefix = 'errand_pin_';
  static const String _settlementPrefix = 'offline_settlement_';

  final SharedPreferences? _prefs;

  OfflinePinCacheService([this._prefs]);

  Future<SharedPreferences> get _instance async =>
      _prefs ?? await SharedPreferences.getInstance();

  /// Enregistre le code PIN à 4 chiffres pour une course donnée.
  Future<bool> savePin(String errandId, String pin) async {
    if (errandId.isEmpty) return false;
    final prefs = await _instance;
    return prefs.setString('$_keyPrefix$errandId', pin.trim());
  }

  /// Récupère le code PIN en cache pour une course donnée.
  Future<String?> getPin(String errandId) async {
    if (errandId.isEmpty) return null;
    final prefs = await _instance;
    return prefs.getString('$_keyPrefix$errandId');
  }

  /// Valide un code PIN saisi contre le code en cache localement.
  Future<bool> verifyPin(String errandId, String inputPin) async {
    final cached = await getPin(errandId);
    if (cached == null) return false;
    return cached.trim() == inputPin.trim();
  }

  /// Supprime le code PIN du cache (ex: après livraison terminée).
  Future<bool> clearPin(String errandId) async {
    final prefs = await _instance;
    return prefs.remove('$_keyPrefix$errandId');
  }

  /// Enregistre une tentative de validation hors-ligne à réconcilier ultérieurement.
  Future<bool> recordOfflineSettlement(String errandId, String inputPin) async {
    final prefs = await _instance;
    final timestamp = DateTime.now().toIso8601String();
    return prefs.setString(
      '$_settlementPrefix$errandId',
      '$inputPin|$timestamp',
    );
  }

  /// Récupère les règlements en attente de synchronisation.
  Future<Map<String, String>> getPendingOfflineSettlements() async {
    final prefs = await _instance;
    final keys = prefs.getKeys().where((k) => k.startsWith(_settlementPrefix));
    final map = <String, String>{};
    for (final k in keys) {
      final errandId = k.substring(_settlementPrefix.length);
      final val = prefs.getString(k);
      if (val != null) {
        map[errandId] = val.split('|').first;
      }
    }
    return map;
  }

  /// Supprime un règlement après synchronisation serveur réussie.
  Future<bool> clearOfflineSettlement(String errandId) async {
    final prefs = await _instance;
    return prefs.remove('$_settlementPrefix$errandId');
  }

  /// Récupère l'ensemble des courses avec PIN en cache.
  Future<Map<String, String>> getAllCachedPins() async {
    final prefs = await _instance;
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
    final map = <String, String>{};
    for (final k in keys) {
      final errandId = k.substring(_keyPrefix.length);
      final pin = prefs.getString(k);
      if (pin != null) {
        map[errandId] = pin;
      }
    }
    return map;
  }
}
