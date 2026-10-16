import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/catalog_category_model.dart';
import '../models/catalog_product_model.dart';
import '../models/errand_item_model.dart';

/// Service du catalogue de produits algériens 9DILI EXPRESS.
/// Fonctionne en mode hybride : données Firestore en temps réel + catalogue local embarqué ultra-rapide hors-ligne.
class CatalogService {
  final FirebaseFirestore? _firestore;

  CatalogService([this._firestore]);

  CollectionReference<Map<String, dynamic>>? get _categoriesRef =>
      _firestore?.collection('catalog_categories');

  CollectionReference<Map<String, dynamic>>? get _productsRef =>
      _firestore?.collection('catalog_products');

  // ==========================================
  // 1. LES 11 CATÉGORIES OFFICIELLES
  // ==========================================
  static const List<CatalogCategoryModel> defaultCategories = [
    CatalogCategoryModel(
      categoryId: 'fruits_legumes',
      nameFr: 'Fruits & Légumes',
      nameAr: 'خضر وفواكه',
      iconName: 'eco',
      sortOrder: 1,
    ),
    CatalogCategoryModel(
      categoryId: 'epicerie',
      nameFr: 'Épicerie & Féculents',
      nameAr: 'بقوليات وعجائن',
      iconName: 'kitchen',
      sortOrder: 2,
    ),
    CatalogCategoryModel(
      categoryId: 'lait_frais',
      nameFr: 'Lait & Produits Frais',
      nameAr: 'حليب ومشتقاته',
      iconName: 'local_drink',
      sortOrder: 3,
    ),
    CatalogCategoryModel(
      categoryId: 'pain_boulangerie',
      nameFr: 'Pain & Boulangerie',
      nameAr: 'خبز ومخبوزات',
      iconName: 'bakery_dining',
      sortOrder: 4,
    ),
    CatalogCategoryModel(
      categoryId: 'viandes_poissons',
      nameFr: 'Viandes, Volailles & Poissons',
      nameAr: 'لحوم، دواجن وأسماك',
      iconName: 'restaurant',
      sortOrder: 5,
    ),
    CatalogCategoryModel(
      categoryId: 'boissons',
      nameFr: 'Boissons & Eaux',
      nameAr: 'مشروبات ومياه',
      iconName: 'local_cafe',
      sortOrder: 6,
    ),
    CatalogCategoryModel(
      categoryId: 'hygiene',
      nameFr: 'Hygiène Personnelle',
      nameAr: 'عناية ونظافة شخصية',
      iconName: 'clean_hands',
      sortOrder: 7,
    ),
    CatalogCategoryModel(
      categoryId: 'entretien',
      nameFr: 'Entretien & Nettoyage',
      nameAr: 'مواد التنظيف',
      iconName: 'cleaning_services',
      sortOrder: 8,
    ),
    CatalogCategoryModel(
      categoryId: 'bebe',
      nameFr: 'Bébé & Puériculture',
      nameAr: 'لوازم الأطفال الرضع',
      iconName: 'child_care',
      sortOrder: 9,
    ),
    CatalogCategoryModel(
      categoryId: 'papeterie',
      nameFr: 'Papeterie & Dépannage',
      nameAr: 'أدوات مكتبية ومستلزمات',
      iconName: 'menu_book',
      sortOrder: 10,
    ),
    CatalogCategoryModel(
      categoryId: 'terroir_saisonnier',
      nameFr: 'Produits du Terroir',
      nameAr: 'منتجات تقليدية وموسمية',
      iconName: 'spa',
      sortOrder: 11,
    ),
  ];

  // ==========================================
  // 2. RÉFÉRENTIEL INITIAL DE PRODUITS ALGÉRIENS EMBARQUÉS
  // ==========================================
  static final List<CatalogProductModel> defaultProducts = [
    // 1. Fruits & Légumes
    const CatalogProductModel(
      productId: 'fl_01',
      categoryId: 'fruits_legumes',
      nameFr: 'Pommes de terre (Batata)',
      nameAr: 'بطاطا جزائرية',
      unit: 'kg',
      defaultQuantity: 2.0,
      indicativePrice: 75.0,
      aliases: ['batata', 'pomme de terre', 'بطاطا'],
    ),
    const CatalogProductModel(
      productId: 'fl_02',
      categoryId: 'fruits_legumes',
      nameFr: 'Tomates fraîches',
      nameAr: 'طماطم طازجة',
      unit: 'kg',
      defaultQuantity: 1.0,
      indicativePrice: 90.0,
      aliases: ['tomate', 'tmatem', 'طماطم'],
    ),
    const CatalogProductModel(
      productId: 'fl_03',
      categoryId: 'fruits_legumes',
      nameFr: 'Oignons rouges/blancs',
      nameAr: 'بصل',
      unit: 'kg',
      defaultQuantity: 1.0,
      indicativePrice: 65.0,
      aliases: ['bcel', 'oignon', 'بصل'],
    ),
    const CatalogProductModel(
      productId: 'fl_04',
      categoryId: 'fruits_legumes',
      nameFr: 'Dattes Deglet Nour de Biskra',
      nameAr: 'تمر دقلة نور بسكرة',
      unit: 'kg',
      defaultQuantity: 1.0,
      indicativePrice: 650.0,
      aliases: ['dattes', 'deglet nour', 'tmar', 'دقلة نور', 'تمر'],
    ),

    // 2. Épicerie & Féculents
    const CatalogProductModel(
      productId: 'ep_01',
      categoryId: 'epicerie',
      nameFr: 'Huile de table Fleurial 5L',
      nameAr: 'زيت المائدة فلوريال 5 لتر',
      brand: 'Cevital',
      unit: 'bouteille',
      defaultQuantity: 1.0,
      indicativePrice: 650.0,
      barcode: '6130101001012',
      aliases: ['huile', 'fleurial', 'zit', 'cevital', 'زيت'],
    ),
    const CatalogProductModel(
      productId: 'ep_02',
      categoryId: 'epicerie',
      nameFr: 'Couscous Moyen Sim 1kg',
      nameAr: 'كسكس متوسط سيم 1 كلغ',
      brand: 'Sim',
      unit: 'paquet',
      defaultQuantity: 1.0,
      indicativePrice: 120.0,
      barcode: '6130202002023',
      aliases: ['couscous', 'seksou', 'sim', 'طعام', 'كسكس'],
    ),
    const CatalogProductModel(
      productId: 'ep_03',
      categoryId: 'epicerie',
      nameFr: 'Semoule Moyenne Benamor 5kg',
      nameAr: 'سميد بن عمر 5 كلغ',
      brand: 'Amor Benamor',
      unit: 'sachet',
      defaultQuantity: 1.0,
      indicativePrice: 280.0,
      barcode: '6130303003034',
      aliases: ['semoule', 'smid', 'benamor', 'سميد'],
    ),
    const CatalogProductModel(
      productId: 'ep_04',
      categoryId: 'epicerie',
      nameFr: 'Pâtes Spaghettis Extrême 500g',
      nameAr: 'سباغيتي اكستريم 500غ',
      brand: 'Safina',
      unit: 'paquet',
      defaultQuantity: 2.0,
      indicativePrice: 65.0,
      aliases: ['pates', 'spaghetti', 'safina', 'عجائن'],
    ),

    // 3. Lait & Produits Frais
    const CatalogProductModel(
      productId: 'lf_01',
      categoryId: 'lait_frais',
      nameFr: 'Lait Pasteurisée en Sachet 1L',
      nameAr: 'حليب مبستر كيس 1 لتر',
      brand: 'National',
      unit: 'sachet',
      defaultQuantity: 2.0,
      indicativePrice: 25.0,
      aliases: ['hlib chekara', 'lait sachet', 'حليب الشكارة'],
    ),
    const CatalogProductModel(
      productId: 'lf_02',
      categoryId: 'lait_frais',
      nameFr: 'Lait Candia Silhouette Demi-Écrémé 1L',
      nameAr: 'حليب كانديا نصف دسم 1 لتر',
      brand: 'Candia / Tchin-Lait',
      unit: 'brique',
      defaultQuantity: 2.0,
      indicativePrice: 125.0,
      barcode: '6130404004045',
      aliases: ['candia', 'lait brique', 'hlib', 'كانديا'],
    ),
    const CatalogProductModel(
      productId: 'lf_03',
      categoryId: 'lait_frais',
      nameFr: 'Pack Yaourt Soummam Panaché x8',
      nameAr: 'ياغورت صومام مشكل 8 قطع',
      brand: 'Soummam',
      unit: 'pack',
      defaultQuantity: 1.0,
      indicativePrice: 240.0,
      barcode: '6130505005056',
      aliases: ['yaourt', 'soummam', 'danone', 'صومام', 'ياغورت'],
    ),
    const CatalogProductModel(
      productId: 'lf_04',
      categoryId: 'lait_frais',
      nameFr: 'Fromage Fondu Tartino 16 Portions',
      nameAr: 'جبن تارتينو 16 قطعة',
      brand: 'Fromagerie des Belges',
      unit: 'boîte',
      defaultQuantity: 1.0,
      indicativePrice: 210.0,
      aliases: ['fromage', 'tartino', 'berbere', 'فرماج', 'جبن'],
    ),

    // 4. Pain & Boulangerie
    const CatalogProductModel(
      productId: 'pb_01',
      categoryId: 'pain_boulangerie',
      nameFr: 'Baguette de Pain Ordinaire',
      nameAr: 'خبز باقية عادي',
      unit: 'pièce',
      defaultQuantity: 3.0,
      indicativePrice: 10.0,
      aliases: ['pain', 'baguette', 'khobz', 'خبز'],
    ),
    const CatalogProductModel(
      productId: 'pb_02',
      categoryId: 'pain_boulangerie',
      nameFr: 'Khobz Matlouh Traditionnel',
      nameAr: 'خبز مطلوع تقليدي',
      unit: 'pièce',
      defaultQuantity: 2.0,
      indicativePrice: 40.0,
      aliases: ['matlouh', 'kesra', 'مطلوع', 'كسرة'],
    ),

    // 5. Viandes & Poissons
    const CatalogProductModel(
      productId: 'vp_01',
      categoryId: 'viandes_poissons',
      nameFr: 'Poulet Frais Entier Vidé (kg)',
      nameAr: 'دجاج طازج مذبوح (كلغ)',
      unit: 'kg',
      defaultQuantity: 1.8,
      indicativePrice: 420.0,
      aliases: ['poulet', 'djedj', 'دجاج'],
    ),
    const CatalogProductModel(
      productId: 'vp_02',
      categoryId: 'viandes_poissons',
      nameFr: 'Viande de Bœuf Hachée fraîche (kg)',
      nameAr: 'لحم بقري مفروم طازج (كلغ)',
      unit: 'kg',
      defaultQuantity: 0.5,
      indicativePrice: 2200.0,
      aliases: ['viande hachee', 'kfta', 'لحم مفروم'],
    ),

    // 6. Boissons & Eaux
    const CatalogProductModel(
      productId: 'bs_01',
      categoryId: 'boissons',
      nameFr: 'Eau Minérale Ifri 1.5L (Pack de 6)',
      nameAr: 'ماء معدني إيفري 1.5 لتر (حزمة 6)',
      brand: 'Ifri',
      unit: 'pack',
      defaultQuantity: 1.0,
      indicativePrice: 210.0,
      barcode: '6130606006067',
      aliases: ['eau', 'ifri', 'ma', 'lalla khedidja', 'ماء إيفري'],
    ),
    const CatalogProductModel(
      productId: 'bs_02',
      categoryId: 'boissons',
      nameFr: 'Soda Hamoud Boualem Selecto 1L',
      nameAr: 'مشروب سيلكتو حمود بوعلام 1 لتر',
      brand: 'Hamoud Boualem',
      unit: 'bouteille',
      defaultQuantity: 1.0,
      indicativePrice: 95.0,
      barcode: '6130707007078',
      aliases: ['hamoud', 'selecto', 'slim', 'gazouz', 'حمود بوعلام', 'سيلكتو'],
    ),

    // 7. Hygiène & Soins
    const CatalogProductModel(
      productId: 'hy_01',
      categoryId: 'hygiene',
      nameFr: 'Savon Traditionnel Le Taous 125g',
      nameAr: 'صابون الطاووس الطبيعي 125غ',
      brand: 'Le Taous',
      unit: 'pièce',
      defaultQuantity: 2.0,
      indicativePrice: 85.0,
      aliases: ['savon', 'taous', 'saboun', 'صابون الطاووس'],
    ),

    // 8. Entretien & Nettoyage
    const CatalogProductModel(
      productId: 'en_01',
      categoryId: 'entretien',
      nameFr: 'Eau de Javel Maxis 1L',
      nameAr: 'ماء جافيل ماكسيس 1 لتر',
      brand: 'Maxis',
      unit: 'bouteille',
      defaultQuantity: 1.0,
      indicativePrice: 110.0,
      aliases: ['javel', 'maxis', 'bref', 'جافيل'],
    ),

    // 9. Bébé & Puériculture
    const CatalogProductModel(
      productId: 'bb_01',
      categoryId: 'bebe',
      nameFr: 'Couches Bébé Dalaa Taille 4 (Packs 44)',
      nameAr: 'حفاضات رضع دلعة مقاس 4 (44 حبة)',
      brand: 'Dalaa',
      unit: 'paquet',
      defaultQuantity: 1.0,
      indicativePrice: 850.0,
      barcode: '6130808008089',
      aliases: ['couches', 'dalaa', 'bebe', 'canbebe', 'حفاضات دلعة'],
    ),

    // 10. Terroir & Saisonnier
    const CatalogProductModel(
      productId: 'tr_01',
      categoryId: 'terroir_saisonnier',
      nameFr: 'Huile d\'Olive Vierge de Kabylie 1L',
      nameAr: 'زيت زيتون بكر منطقة القبائل 1 لتر',
      brand: 'Terroir Artisanal',
      unit: 'bouteille',
      defaultQuantity: 1.0,
      indicativePrice: 950.0,
      aliases: ['huile d\'olive', 'zit zitoun', 'زيت زيتون'],
    ),
  ];

  /// Récupère l'ensemble des catégories (Firestore ou local).
  Future<List<CatalogCategoryModel>> getCategories() async {
    final ref = _categoriesRef;
    if (ref != null) {
      try {
        final snap = await ref.orderBy('sortOrder').get();
        if (snap.docs.isNotEmpty) {
          return snap.docs
              .map(
                (d) => CatalogCategoryModel.fromMap(d.data(), documentId: d.id),
              )
              .toList();
        }
      } catch (_) {
        // Fallback local en cas d'absence de réseau
      }
    }
    return defaultCategories;
  }

  /// Récupère la liste des produits (hybride Firestore avec repli local).
  Future<List<CatalogProductModel>> getProducts({String? categoryId}) async {
    final ref = _productsRef;
    if (ref != null) {
      try {
        Query<Map<String, dynamic>> query = ref.where(
          'isActive',
          isEqualTo: true,
        );
        if (categoryId != null &&
            categoryId.isNotEmpty &&
            categoryId != 'all') {
          query = query.where('categoryId', isEqualTo: categoryId);
        }
        final snap = await query.get();
        if (snap.docs.isNotEmpty) {
          return snap.docs
              .map(
                (d) => CatalogProductModel.fromMap(d.data(), documentId: d.id),
              )
              .toList();
        }
      } catch (_) {
        // Fallback local en cas d'absence de réseau
      }
    }
    return searchLocalProducts(categoryId: categoryId);
  }

  /// Recherche des produits par mots-clés et/ou filtre de catégorie.
  List<CatalogProductModel> searchLocalProducts({
    String query = '',
    String? categoryId,
  }) {
    var results = defaultProducts.where((p) => p.isActive);
    if (categoryId != null && categoryId.isNotEmpty && categoryId != 'all') {
      results = results.where((p) => p.categoryId == categoryId);
    }
    if (query.trim().isNotEmpty) {
      results = results.where((p) => p.matchesQuery(query));
    }
    return results.toList();
  }

  /// Convertit un produit sélectionné dans le catalogue vers un ErrandItemModel pour la commande.
  static ErrandItemModel toErrandItem(
    CatalogProductModel product, {
    double? quantity,
  }) {
    return ErrandItemModel(
      itemId: '', // Généré à l'enregistrement
      name: '${product.nameFr} (${product.nameAr})',
      quantity: quantity ?? product.defaultQuantity,
      unit: product.unit,
      notes: product.brand != null ? 'Marque souhaitée : ${product.brand}' : '',
      status: ErrandItemStatus.pending,
    );
  }
}
