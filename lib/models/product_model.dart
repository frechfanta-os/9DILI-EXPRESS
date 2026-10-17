/// Modèle de produit du catalogue national algérien 9DILI EXPRESS.
class ProductModel {
  final String skuId;
  final String? barcode;
  final String nameFr;
  final String? nameAr;
  final List<String> searchKeywordsDarja;
  final String? brand;
  final String? category;
  final String? subCategory;
  final bool isWeighable;
  final String? unitType;
  final num? unitValue;
  final double? estimatedPriceDzd;
  final String? aisleCode;
  final String? aisleNameFr;
  final String? aisleNameAr;
  final String? imageUrl;

  const ProductModel({
    required this.skuId,
    this.barcode,
    required this.nameFr,
    this.nameAr,
    this.searchKeywordsDarja = const [],
    this.brand,
    this.category,
    this.subCategory,
    this.aisleCode,
    this.aisleNameFr,
    this.aisleNameAr,
    this.isWeighable = false,
    this.unitType,
    this.unitValue,
    this.estimatedPriceDzd,
    this.imageUrl,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    // Parsing sécurisé des mots-clés Darja
    List<String> keywords = [];
    if (json['search_keywords_darja'] is List) {
      keywords = (json['search_keywords_darja'] as List)
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }

    // Conversion sécurisée du prix DZD
    double? price;
    if (json['estimated_price_dzd'] != null) {
      if (json['estimated_price_dzd'] is num) {
        price = (json['estimated_price_dzd'] as num).toDouble();
      } else {
        price = double.tryParse(json['estimated_price_dzd'].toString());
      }
    }

    // Conversion du code-barres en chaîne nettoyée
    String? rawBarcode = json['barcode']?.toString().trim();
    if (rawBarcode == null ||
        rawBarcode.isEmpty ||
        rawBarcode.toLowerCase() == 'null') {
      rawBarcode = null;
    }

    // Extraction robuste des métadonnées LSL & Packaging
    final merch = json['lsl_merchandising'] is Map
        ? (json['lsl_merchandising'] as Map)
        : null;
    final packaging = json['packaging'] is Map
        ? (json['packaging'] as Map)
        : null;

    final aisleNameFr = merch?['aisle_name_fr']?.toString();
    final aisleNameAr = merch?['aisle_name_ar']?.toString();
    final aisleCode = merch?['aisle_code']?.toString();

    final category =
        json['category']?.toString() ??
        aisleNameFr ??
        merch?['category']?.toString();
    final subCategory =
        json['sub_category']?.toString() ?? merch?['sub_category']?.toString();
    final isWeighable =
        json['is_weighable'] == true || packaging?['is_weighable'] == true;
    final unitType =
        json['unit_type']?.toString() ?? packaging?['unit_type']?.toString();
    final rawUnitVal = json['unit_value'] ?? packaging?['unit_value'];
    final unitValue = rawUnitVal is num ? rawUnitVal : null;

    return ProductModel(
      skuId: json['sku_id']?.toString() ?? '',
      barcode: rawBarcode,
      nameFr: json['name_fr']?.toString() ?? '',
      nameAr: json['name_ar']?.toString(),
      searchKeywordsDarja: keywords,
      brand: json['brand']?.toString(),
      category: category,
      subCategory: subCategory,
      aisleCode: aisleCode,
      aisleNameFr: aisleNameFr,
      aisleNameAr: aisleNameAr,
      isWeighable: isWeighable,
      unitType: unitType,
      unitValue: unitValue,
      estimatedPriceDzd: price,
      imageUrl: json['image_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'sku_id': skuId,
    if (barcode != null) 'barcode': barcode,
    'name_fr': nameFr,
    if (nameAr != null) 'name_ar': nameAr,
    'search_keywords_darja': searchKeywordsDarja,
    if (brand != null) 'brand': brand,
    if (category != null) 'category': category,
    if (subCategory != null) 'sub_category': subCategory,
    'is_weighable': isWeighable,
    if (unitType != null) 'unit_type': unitType,
    if (unitValue != null) 'unit_value': unitValue,
    if (estimatedPriceDzd != null) 'estimated_price_dzd': estimatedPriceDzd,
    if (imageUrl != null) 'image_url': imageUrl,
  };

  /// Libellé d'affichage principal (privilégie le français ou bilingue selon contexte).
  String get displayName {
    if (nameAr != null && nameAr!.isNotEmpty) {
      return '$nameFr • $nameAr';
    }
    return nameFr;
  }

  /// Prix formaté en dinars algériens (DZD).
  String get formattedPrice {
    if (estimatedPriceDzd != null && estimatedPriceDzd! > 0) {
      return '${estimatedPriceDzd!.toStringAsFixed(0)} DA';
    }
    return 'Prix en magasin';
  }
}
