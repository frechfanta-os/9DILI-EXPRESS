import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

/// Service de gestion des utilisateurs dans Firestore (/users/{uid}).
class UserService {
  final FirebaseFirestore _firestore;

  UserService([FirebaseFirestore? firestore])
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection('users');

  /// Récupère les données d'un utilisateur par son UID.
  Future<UserModel?> getUser(String uid) async {
    if (uid.isEmpty) return null;
    final doc = await _usersRef.doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromFirestore(doc);
  }

  /// Écoute en temps réel le profil d'un utilisateur.
  Stream<UserModel?> streamUser(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _usersRef.doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromFirestore(doc);
    });
  }

  /// Crée ou met à jour le profil utilisateur (merge pour préserver les champs existants).
  Future<void> saveUser(UserModel user) async {
    await _usersRef.doc(user.uid).set(user.toMap(), SetOptions(merge: true));
  }

  /// Met à jour le statut en ligne (isOnline).
  Future<void> setOnlineStatus(String uid, bool isOnline) async {
    await _usersRef.doc(uid).update({
      'isOnline': isOnline,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Met à jour la trésorerie disponible en poche (availableCash) du shoppeur.
  Future<void> setAvailableCash(String uid, double availableCash) async {
    await _usersRef.doc(uid).update({
      'availableCash': availableCash,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Met à jour la position géographique de l'utilisateur (location).
  Future<void> updateLocation(String uid, GeoPoint location) async {
    await _usersRef.doc(uid).update({
      'location': location,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Met à jour les paramètres de déplacement du shoppeur (véhicule et rayon).
  Future<void> updateTransportSettings(
    String uid, {
    required String transportType,
    required double searchRadiusKm,
  }) async {
    await _usersRef.doc(uid).update({
      'transportType': transportType,
      'searchRadiusKm': searchRadiusKm,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Récupère la liste en temps réel des shoppeurs en ligne avec trésorerie suffisante.
  Stream<List<UserModel>> streamAvailableShoppers({double minCash = 0.0}) {
    return _usersRef
        .where('role', isEqualTo: 'shopper')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => UserModel.fromFirestore(doc))
              .where((shopper) => shopper.availableCash >= minCash)
              .toList();
        });
  }
}
