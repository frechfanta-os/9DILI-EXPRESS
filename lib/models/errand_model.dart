import 'package:cloud_firestore/cloud_firestore.dart';

/// Statuts possibles d'une course 9DILI EXPRESS.
class ErrandStatus {
  static const String pending = 'pending';
  static const String accepted = 'accepted';
  static const String shopping = 'shopping';
  static const String delivering = 'delivering';
  static const String completed = 'completed';
  static const String cancelled = 'cancelled';

  static const List<String> all = [
    pending,
    accepted,
    shopping,
    delivering,
    completed,
    cancelled,
  ];

  /// Vérifie si une transition de statut est légitime selon la machine d'état stricte.
  static bool isValidTransition(String from, String to) {
    if (from == to) return true;
    switch (from) {
      case pending:
        return to == accepted || to == cancelled;
      case accepted:
        return to == shopping || to == cancelled;
      case shopping:
        return to == delivering || to == cancelled;
      case delivering:
        return to == completed || to == cancelled;
      case completed:
      case cancelled:
        return false; // États terminaux immuables
      default:
        return false;
    }
  }
}

/// Modèle pour la collection /errands/{errandId} avec contrôles de sécurité et machine d'état.
class ErrandModel {
  final String errandId;
  final String clientId;
  final String? shopperId;
  final String storeName;
  final String deliveryAddress;
  final GeoPoint? deliveryGeoPoint;
  final double estimatedBudget;
  final double? ticketAmount;
  final double negotiatedCommission;
  final String? ticketPhotoUrl;
  final String status; // 'pending', 'accepted', 'shopping', 'delivering', 'completed', 'cancelled'
  final String securePin; // Code PIN à 4 chiffres sécurisé
  final DateTime?
  pinExpiresAt; // Expiration temporelle du code PIN (ex: 15-30 min)
  final int pinFailedAttempts; // Protection anti-brute force (max 3 tentatives)
  final bool pinLocked; // Verrouillage après échecs répétés
  final GeoPoint? shopperLocation;
  final bool callCompleted; // Étape obligatoire : appel passé et attesté
  final DateTime? callConfirmedAt; // Horodatage de l'attestation d'appel
  final String? callConfirmedBy; // UID de l'utilisateur ayant validé l'échange
  final double? storeDistanceKm; // Distance commerce
  final int? etaMinutes; // Temps estimé
  final String? clientPhone;
  final String? shopperPhone;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ErrandModel({
    required this.errandId,
    required this.clientId,
    this.shopperId,
    required this.storeName,
    required this.deliveryAddress,
    this.deliveryGeoPoint,
    required this.estimatedBudget,
    this.ticketAmount,
    this.negotiatedCommission = 0.0,
    this.ticketPhotoUrl,
    this.status = ErrandStatus.pending,
    required this.securePin,
    this.pinExpiresAt,
    this.pinFailedAttempts = 0,
    this.pinLocked = false,
    this.shopperLocation,
    this.callCompleted = false,
    this.callConfirmedAt,
    this.callConfirmedBy,
    this.storeDistanceKm,
    this.etaMinutes,
    this.clientPhone,
    this.shopperPhone,
    this.createdAt,
    this.updatedAt,
  });

  bool get isAssigned => shopperId != null && shopperId!.isNotEmpty;
  bool get isPending => status == ErrandStatus.pending;
  bool get isAccepted => status == ErrandStatus.accepted;
  bool get isShopping => status == ErrandStatus.shopping;
  bool get isDelivering => status == ErrandStatus.delivering;
  bool get isCompleted => status == ErrandStatus.completed;
  bool get isCancelled => status == ErrandStatus.cancelled;

  /// Vérifie si le code PIN est expiré.
  bool get isPinExpired =>
      pinExpiresAt != null && DateTime.now().isAfter(pinExpiresAt!);

  /// Vérifie si les tentatives de PIN sont verrouillées (anti-brute force).
  bool get isPinLocked => pinLocked || pinFailedAttempts >= 3;

  /// Règle métier : Trésorerie requise pour avancer les achats.
  double get treasuryRequired => estimatedBudget;

  /// Formule obligatoire UI/UX : Total à payer = Montant du ticket + Commission négociée.
  double get totalAmount => (ticketAmount ?? 0.0) + negotiatedCommission;

  /// Indique si le justificatif et le montant sont validés pour autoriser le passage à "delivering".
  bool get isReceiptValidated =>
      ticketAmount != null &&
      ticketAmount! > 0 &&
      ticketPhotoUrl != null &&
      ticketPhotoUrl!.isNotEmpty;

  /// Valide si une transition vers [newStatus] est légale.
  bool canTransitionTo(String newStatus) {
    if (!ErrandStatus.isValidTransition(status, newStatus)) {
      return false;
    }
    // Règle stricte : passage en livraison uniquement avec ticket et montant validés
    if (newStatus == ErrandStatus.delivering && !isReceiptValidated) {
      return false;
    }
    // Règle stricte : clôture uniquement depuis delivering et sans verrou PIN
    if (newStatus == ErrandStatus.completed &&
        (status != ErrandStatus.delivering || isPinLocked)) {
      return false;
    }
    return true;
  }

  factory ErrandModel.fromMap(Map<String, dynamic> data, {String? documentId}) {
    String addressStr = '';
    GeoPoint? addressGeo;

    final rawAddress = data['deliveryAddress'];
    if (rawAddress is GeoPoint) {
      addressGeo = rawAddress;
      addressStr = '${rawAddress.latitude}, ${rawAddress.longitude}';
    } else if (rawAddress is String) {
      addressStr = rawAddress;
    }

    if (data['deliveryGeoPoint'] is GeoPoint) {
      addressGeo = data['deliveryGeoPoint'] as GeoPoint;
    }

    return ErrandModel(
      errandId: documentId ?? data['errandId'] ?? '',
      clientId: data['clientId'] ?? '',
      shopperId: data['shopperId'],
      storeName: data['storeName'] ?? '',
      deliveryAddress: addressStr.isNotEmpty
          ? addressStr
          : (data['deliveryAddressText'] ?? ''),
      deliveryGeoPoint: addressGeo,
      estimatedBudget: (data['estimatedBudget'] as num?)?.toDouble() ?? 0.0,
      ticketAmount: (data['ticketAmount'] as num?)?.toDouble(),
      negotiatedCommission:
          (data['negotiatedCommission'] as num?)?.toDouble() ?? 0.0,
      ticketPhotoUrl: data['ticketPhotoUrl'],
      status: data['status'] ?? ErrandStatus.pending,
      securePin: data['securePin']?.toString() ?? '',
      pinExpiresAt: (data['pinExpiresAt'] is Timestamp)
          ? (data['pinExpiresAt'] as Timestamp).toDate()
          : null,
      pinFailedAttempts: (data['pinFailedAttempts'] as num?)?.toInt() ?? 0,
      pinLocked: data['pinLocked'] is bool ? data['pinLocked'] as bool : false,
      shopperLocation: data['shopperLocation'] is GeoPoint
          ? data['shopperLocation'] as GeoPoint
          : null,
      callCompleted: data['callCompleted'] is bool
          ? data['callCompleted'] as bool
          : false,
      callConfirmedAt: (data['callConfirmedAt'] is Timestamp)
          ? (data['callConfirmedAt'] as Timestamp).toDate()
          : null,
      callConfirmedBy: data['callConfirmedBy'],
      storeDistanceKm: (data['storeDistanceKm'] as num?)?.toDouble(),
      etaMinutes: (data['etaMinutes'] as num?)?.toInt(),
      clientPhone: data['clientPhone'],
      shopperPhone: data['shopperPhone'],
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: (data['updatedAt'] is Timestamp)
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  factory ErrandModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return ErrandModel.fromMap(data, documentId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'errandId': errandId,
      'clientId': clientId,
      'shopperId': shopperId,
      'storeName': storeName,
      'deliveryAddress': deliveryAddress,
      if (deliveryGeoPoint != null) 'deliveryGeoPoint': deliveryGeoPoint,
      'estimatedBudget': estimatedBudget,
      'ticketAmount': ticketAmount,
      'negotiatedCommission': negotiatedCommission,
      'ticketPhotoUrl': ticketPhotoUrl,
      'status': status,
      'securePin': securePin,
      if (pinExpiresAt != null)
        'pinExpiresAt': Timestamp.fromDate(pinExpiresAt!),
      'pinFailedAttempts': pinFailedAttempts,
      'pinLocked': pinLocked,
      if (shopperLocation != null) 'shopperLocation': shopperLocation,
      'callCompleted': callCompleted,
      if (callConfirmedAt != null)
        'callConfirmedAt': Timestamp.fromDate(callConfirmedAt!),
      if (callConfirmedBy != null) 'callConfirmedBy': callConfirmedBy,
      if (storeDistanceKm != null) 'storeDistanceKm': storeDistanceKm,
      if (etaMinutes != null) 'etaMinutes': etaMinutes,
      if (clientPhone != null) 'clientPhone': clientPhone,
      if (shopperPhone != null) 'shopperPhone': shopperPhone,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  ErrandModel copyWith({
    String? errandId,
    String? clientId,
    String? shopperId,
    String? storeName,
    String? deliveryAddress,
    GeoPoint? deliveryGeoPoint,
    double? estimatedBudget,
    double? ticketAmount,
    double? negotiatedCommission,
    String? ticketPhotoUrl,
    String? status,
    String? securePin,
    DateTime? pinExpiresAt,
    int? pinFailedAttempts,
    bool? pinLocked,
    GeoPoint? shopperLocation,
    bool? callCompleted,
    DateTime? callConfirmedAt,
    String? callConfirmedBy,
    double? storeDistanceKm,
    int? etaMinutes,
    String? clientPhone,
    String? shopperPhone,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ErrandModel(
      errandId: errandId ?? this.errandId,
      clientId: clientId ?? this.clientId,
      shopperId: shopperId ?? this.shopperId,
      storeName: storeName ?? this.storeName,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryGeoPoint: deliveryGeoPoint ?? this.deliveryGeoPoint,
      estimatedBudget: estimatedBudget ?? this.estimatedBudget,
      ticketAmount: ticketAmount ?? this.ticketAmount,
      negotiatedCommission: negotiatedCommission ?? this.negotiatedCommission,
      ticketPhotoUrl: ticketPhotoUrl ?? this.ticketPhotoUrl,
      status: status ?? this.status,
      securePin: securePin ?? this.securePin,
      pinExpiresAt: pinExpiresAt ?? this.pinExpiresAt,
      pinFailedAttempts: pinFailedAttempts ?? this.pinFailedAttempts,
      pinLocked: pinLocked ?? this.pinLocked,
      shopperLocation: shopperLocation ?? this.shopperLocation,
      callCompleted: callCompleted ?? this.callCompleted,
      callConfirmedAt: callConfirmedAt ?? this.callConfirmedAt,
      callConfirmedBy: callConfirmedBy ?? this.callConfirmedBy,
      storeDistanceKm: storeDistanceKm ?? this.storeDistanceKm,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      clientPhone: clientPhone ?? this.clientPhone,
      shopperPhone: shopperPhone ?? this.shopperPhone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'ErrandModel(id: $errandId, store: $storeName, status: $status, attempts: $pinFailedAttempts, locked: $pinLocked, total: $totalAmount)';
  }
}
