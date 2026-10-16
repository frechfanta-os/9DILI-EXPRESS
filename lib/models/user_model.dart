import 'package:cloud_firestore/cloud_firestore.dart';

/// Rôle utilisateur : 'client' ou 'shopper'.
enum UserRole { client, shopper }

/// Mode de transport du Shopper.
enum ShopperTransportType { walking, bicycle, scooter, motorcycle, car }

extension ShopperTransportTypeExtension on ShopperTransportType {
  String get value {
    switch (this) {
      case ShopperTransportType.walking:
        return 'walking';
      case ShopperTransportType.bicycle:
        return 'bicycle';
      case ShopperTransportType.scooter:
        return 'scooter';
      case ShopperTransportType.motorcycle:
        return 'motorcycle';
      case ShopperTransportType.car:
        return 'car';
    }
  }

  String get labelFr {
    switch (this) {
      case ShopperTransportType.walking:
        return 'À pied';
      case ShopperTransportType.bicycle:
        return 'À vélo';
      case ShopperTransportType.scooter:
        return 'En trottinette';
      case ShopperTransportType.motorcycle:
        return 'En moto / scooter';
      case ShopperTransportType.car:
        return 'En voiture';
    }
  }

  /// Rayon maximal conseillé en kilomètres.
  double get maxRadiusKm {
    switch (this) {
      case ShopperTransportType.walking:
        return 1.5;
      case ShopperTransportType.bicycle:
        return 3.5;
      case ShopperTransportType.scooter:
        return 3.0;
      case ShopperTransportType.motorcycle:
        return 10.0;
      case ShopperTransportType.car:
        return 25.0;
    }
  }

  /// Capacité d'emport maximale conseillée en kilogrammes.
  double get maxWeightKg {
    switch (this) {
      case ShopperTransportType.walking:
        return 5.0;
      case ShopperTransportType.bicycle:
        return 10.0;
      case ShopperTransportType.scooter:
        return 8.0;
      case ShopperTransportType.motorcycle:
        return 20.0;
      case ShopperTransportType.car:
        return 80.0;
    }
  }

  /// Vitesse moyenne urbaine estimée en km/h.
  double get averageSpeedKmh {
    switch (this) {
      case ShopperTransportType.walking:
        return 4.5;
      case ShopperTransportType.bicycle:
        return 14.0;
      case ShopperTransportType.scooter:
        return 16.0;
      case ShopperTransportType.motorcycle:
        return 30.0;
      case ShopperTransportType.car:
        return 25.0;
    }
  }

  static ShopperTransportType fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'bicycle':
      case 'velo':
        return ShopperTransportType.bicycle;
      case 'scooter':
      case 'trottinette':
        return ShopperTransportType.scooter;
      case 'motorcycle':
      case 'moto':
        return ShopperTransportType.motorcycle;
      case 'car':
      case 'voiture':
        return ShopperTransportType.car;
      case 'walking':
      case 'pied':
      default:
        return ShopperTransportType.walking;
    }
  }
}

extension UserRoleExtension on UserRole {
  String get value => this == UserRole.shopper ? 'shopper' : 'client';

  static UserRole fromString(String? role) {
    if (role?.toLowerCase() == 'shopper') {
      return UserRole.shopper;
    }
    return UserRole.client;
  }
}

/// Modèle Utilisateur pour Firestore (/users/{uid}).
/// Note : Le numéro de téléphone est strictement optionnel (nullable).
class UserModel {
  final String uid;
  final String fullName;
  final String? email;
  final String? phone; // Optionnel : jamais obligatoire
  final String role; // 'client' ou 'shopper'
  final bool isOnline;
  final double
  availableCash; // Trésorerie en poche pour le filtre d'acceptation
  final double rating;
  final GeoPoint? location;
  final String
  transportType; // 'walking', 'bicycle', 'scooter', 'motorcycle', 'car'
  final double searchRadiusKm;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserModel({
    required this.uid,
    required this.fullName,
    this.email,
    this.phone,
    this.role = 'client',
    this.isOnline = false,
    this.availableCash = 0.0,
    this.rating = 5.0,
    this.location,
    this.transportType = 'walking',
    this.searchRadiusKm = 5.0,
    this.createdAt,
    this.updatedAt,
  });

  bool get isShopper => role == 'shopper';
  bool get isClient => role == 'client';

  ShopperTransportType get transport =>
      ShopperTransportTypeExtension.fromString(transportType);

  /// Vérifie la compatibilité du moyen de transport avec le poids estimé des courses.
  bool canCarry(double estimatedWeightKg) =>
      estimatedWeightKg <= transport.maxWeightKg;

  factory UserModel.fromMap(Map<String, dynamic> data, {String? documentId}) {
    return UserModel(
      uid: documentId ?? data['uid'] ?? '',
      fullName: data['fullName'] ?? '',
      email: data['email'],
      phone: data['phone'],
      role: data['role'] ?? 'client',
      isOnline: data['isOnline'] is bool ? data['isOnline'] as bool : false,
      availableCash: (data['availableCash'] as num?)?.toDouble() ?? 0.0,
      rating: (data['rating'] as num?)?.toDouble() ?? 5.0,
      location: data['location'] is GeoPoint
          ? data['location'] as GeoPoint
          : null,
      transportType: data['transportType']?.toString() ?? 'walking',
      searchRadiusKm: (data['searchRadiusKm'] as num?)?.toDouble() ?? 5.0,
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: (data['updatedAt'] is Timestamp)
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  factory UserModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return UserModel.fromMap(data, documentId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'fullName': fullName,
      if (email != null) 'email': email,
      'phone': phone, // Peut être null
      'role': role,
      'isOnline': isOnline,
      'availableCash': availableCash,
      'rating': rating,
      if (location != null) 'location': location,
      'transportType': transportType,
      'searchRadiusKm': searchRadiusKm,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  UserModel copyWith({
    String? uid,
    String? fullName,
    String? email,
    String? phone,
    String? role,
    bool? isOnline,
    double? availableCash,
    double? rating,
    GeoPoint? location,
    String? transportType,
    double? searchRadiusKm,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      isOnline: isOnline ?? this.isOnline,
      availableCash: availableCash ?? this.availableCash,
      rating: rating ?? this.rating,
      location: location ?? this.location,
      transportType: transportType ?? this.transportType,
      searchRadiusKm: searchRadiusKm ?? this.searchRadiusKm,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'UserModel(uid: $uid, fullName: $fullName, role: $role, online: $isOnline, cash: $availableCash, transport: $transportType, rating: $rating)';
  }
}
