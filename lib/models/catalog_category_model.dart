/// Catégorie du catalogue algérien 9DILI EXPRESS.
class CatalogCategoryModel {
  final String categoryId;
  final String nameFr;
  final String nameAr;
  final String iconName;
  final int sortOrder;
  final bool isActive;

  const CatalogCategoryModel({
    required this.categoryId,
    required this.nameFr,
    required this.nameAr,
    required this.iconName,
    required this.sortOrder,
    this.isActive = true,
  });

  factory CatalogCategoryModel.fromMap(Map<String, dynamic> map, {String? documentId}) {
    return CatalogCategoryModel(
      categoryId: documentId ?? map['categoryId'] ?? '',
      nameFr: map['nameFr'] ?? '',
      nameAr: map['nameAr'] ?? '',
      iconName: map['iconName'] ?? 'shopping_basket',
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      isActive: map['isActive'] is bool ? map['isActive'] as bool : true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'categoryId': categoryId,
      'nameFr': nameFr,
      'nameAr': nameAr,
      'iconName': iconName,
      'sortOrder': sortOrder,
      'isActive': isActive,
    };
  }
}
