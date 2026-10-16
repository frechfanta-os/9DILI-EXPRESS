import 'package:cloud_firestore/cloud_firestore.dart';

/// Produit du catalogue algérien avec support bilingue (FR/AR), marques locales et prix indicatif en DZD.
class CatalogProductModel {
  final String productId;
  final String categoryId;
  final String nameFr;
  final String nameAr;
  final String? brand;
  final String
  unit; // 'kg', 'g', 'L', 'pièce', 'paquet', 'bouteille', 'botte', 'sachet'
  final double defaultQuantity;
  final double
  indicativePrice; // EN DZD (Dinar Algérien) - INDICATIF UNIQUEMENT
  final String? barcode; // Ex: EAN-13 débutant par 613...
  final String? imageUrl;
  final List<String> aliases;
  final bool isActive;
  final DateTime? priceUpdatedAt;

  const CatalogProductModel({
    required this.productId,
    required this.categoryId,
    required this.nameFr,
    required this.nameAr,
    this.brand,
    this.unit = 'pièce',
    this.defaultQuantity = 1.0,
    this.indicativePrice = 0.0,
    this.barcode,
    this.imageUrl,
    this.aliases = const [],
    this.isActive = true,
    this.priceUpdatedAt,
  });

  /// Recherche tolérante par mot-clé (Français, Arabe, Marque ou Alias).
  bool matchesQuery(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return true;
    if (nameFr.toLowerCase().contains(clean)) return true;
    if (nameAr.contains(clean)) return true;
    if (brand != null && brand!.toLowerCase().contains(clean)) return true;
    if (barcode != null && barcode!.contains(clean)) return true;
    for (final alias in aliases) {
      if (alias.toLowerCase().contains(clean)) return true;
    }
    return false;
  }

  factory CatalogProductModel.fromMap(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    return CatalogProductModel(
      productId: documentId ?? data['productId'] ?? '',
      categoryId: data['categoryId'] ?? '',
      nameFr: data['nameFr'] ?? '',
      nameAr: data['nameAr'] ?? '',
      brand: data['brand'],
      unit: data['unit'] ?? 'pièce',
      defaultQuantity: (data['defaultQuantity'] as num?)?.toDouble() ?? 1.0,
      indicativePrice: (data['indicativePrice'] as num?)?.toDouble() ?? 0.0,
      barcode: data['barcode'],
      imageUrl: data['imageUrl'],
      aliases:
          (data['aliases'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
      priceUpdatedAt: (data['priceUpdatedAt'] is Timestamp)
          ? (data['priceUpdatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'categoryId': categoryId,
      'nameFr': nameFr,
      'nameAr': nameAr,
      if (brand != null) 'brand': brand,
      'unit': unit,
      'defaultQuantity': defaultQuantity,
      'indicativePrice': indicativePrice,
      if (barcode != null) 'barcode': barcode,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'aliases': aliases,
      'isActive': isActive,
      if (priceUpdatedAt != null)
        'priceUpdatedAt': Timestamp.fromDate(priceUpdatedAt!),
    };
  }

  CatalogProductModel copyWith({
    String? productId,
    String? categoryId,
    String? nameFr,
    String? nameAr,
    String? brand,
    String? unit,
    double? defaultQuantity,
    double? indicativePrice,
    String? barcode,
    String? imageUrl,
    List<String>? aliases,
    bool? isActive,
    DateTime? priceUpdatedAt,
  }) {
    return CatalogProductModel(
      productId: productId ?? this.productId,
      categoryId: categoryId ?? this.categoryId,
      nameFr: nameFr ?? this.nameFr,
      nameAr: nameAr ?? this.nameAr,
      brand: brand ?? this.brand,
      unit: unit ?? this.unit,
      defaultQuantity: defaultQuantity ?? this.defaultQuantity,
      indicativePrice: indicativePrice ?? this.indicativePrice,
      barcode: barcode ?? this.barcode,
      imageUrl: imageUrl ?? this.imageUrl,
      aliases: aliases ?? this.aliases,
      isActive: isActive ?? this.isActive,
      priceUpdatedAt: priceUpdatedAt ?? this.priceUpdatedAt,
    );
  }
}
