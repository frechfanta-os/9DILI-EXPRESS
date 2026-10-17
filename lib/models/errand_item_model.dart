import 'package:cloud_firestore/cloud_firestore.dart';

/// Statuts d'un article dans une course.
class ErrandItemStatus {
  static const String pending = 'pending';
  static const String found = 'found';
  static const String replaced = 'replaced';
  static const String unavailable = 'unavailable';

  static const List<String> all = [pending, found, replaced, unavailable];
}

/// Unités d'articles supportées.
class ErrandItemUnit {
  static const String piece = 'x';
  static const String kilogram = 'kg';
  static const String liter = 'L';
  static const String pack = 'Pack';

  static const List<String> all = [piece, kilogram, liter, pack];
}

/// Modèle pour la sous-collection : /errands/{errandId}/items/{itemId}.
class ErrandItemModel {
  final String itemId;
  final String name;
  final double quantity;
  final String unit; // 'x', 'kg', 'L', 'Pack'
  final String notes;
  final String status; // 'pending', 'found', 'replaced', 'unavailable'
  final String? replacementNote;
  final bool isCustom; // Article personnalisé / hors catalogue
  final String? photoUrl; // Photo de référence de l'article (caméra ou galerie)
  final String? brand; // Marque / fabricant
  final double? estimatedPrice; // Budget unitaire estimé (DA)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ErrandItemModel({
    required this.itemId,
    required this.name,
    this.quantity = 1.0,
    this.unit = ErrandItemUnit.piece,
    this.notes = '',
    this.status = ErrandItemStatus.pending,
    this.replacementNote,
    this.isCustom = false,
    this.photoUrl,
    this.brand,
    this.estimatedPrice,
    this.createdAt,
    this.updatedAt,
  });

  bool get isFound => status == ErrandItemStatus.found;
  bool get isReplaced => status == ErrandItemStatus.replaced;
  bool get isUnavailable => status == ErrandItemStatus.unavailable;
  bool get isPending => status == ErrandItemStatus.pending;

  factory ErrandItemModel.fromMap(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    return ErrandItemModel(
      itemId: documentId ?? data['itemId'] ?? '',
      name: data['name'] ?? '',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: data['unit'] ?? ErrandItemUnit.piece,
      notes: data['notes'] ?? '',
      status: data['status'] ?? ErrandItemStatus.pending,
      replacementNote: data['replacementNote'],
      isCustom: data['isCustom'] == true,
      photoUrl: data['photoUrl'] as String?,
      brand: data['brand'] as String?,
      estimatedPrice: (data['estimatedPrice'] as num?)?.toDouble(),
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: (data['updatedAt'] is Timestamp)
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  factory ErrandItemModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return ErrandItemModel.fromMap(data, documentId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'notes': notes,
      'status': status,
      'replacementNote': replacementNote,
      'isCustom': isCustom,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (brand != null) 'brand': brand,
      if (estimatedPrice != null) 'estimatedPrice': estimatedPrice,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  ErrandItemModel copyWith({
    String? itemId,
    String? name,
    double? quantity,
    String? unit,
    String? notes,
    String? status,
    String? replacementNote,
    bool? isCustom,
    String? photoUrl,
    String? brand,
    double? estimatedPrice,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ErrandItemModel(
      itemId: itemId ?? this.itemId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      replacementNote: replacementNote ?? this.replacementNote,
      isCustom: isCustom ?? this.isCustom,
      photoUrl: photoUrl ?? this.photoUrl,
      brand: brand ?? this.brand,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'ErrandItemModel(id: $itemId, name: $name, qty: $quantity $unit, custom: $isCustom, status: $status)';
  }
}
