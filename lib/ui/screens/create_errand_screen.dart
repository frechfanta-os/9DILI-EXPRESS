import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/errand_model.dart';
import '../../models/errand_item_model.dart';
import '../../models/product_model.dart';
import '../../services/errand_service.dart';
import '../../services/product_catalog_service.dart';
import '../theme/app_theme.dart';

/// Écran complet de création de commande avec navigation par rayons,
/// recherche bilingue dans le catalogue national algérien (2 200+ produits) et gestion de panier.
class CreateErrandScreen extends StatefulWidget {
  final String clientId;
  final ErrandService errandService;
  final ProductCatalogService? catalogService;
  final String? initialAddress;
  final String? initialStoreName;

  const CreateErrandScreen({
    super.key,
    required this.clientId,
    required this.errandService,
    this.catalogService,
    this.initialAddress,
    this.initialStoreName,
  });

  @override
  State<CreateErrandScreen> createState() => _CreateErrandScreenState();
}

class _CreateErrandScreenState extends State<CreateErrandScreen> {
  late final ProductCatalogService _catalogService;

  late final TextEditingController _storeCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _searchCtrl;

  String? _selectedCategory; // null = Tous les rayons
  final Map<ProductModel, int> _cart = {};
  final List<ErrandItemModel> _customItems = [];

  bool _isLoading = true;
  String? _errorMessage;
  late final String _generatedPin;

  @override
  void initState() {
    super.initState();
    _catalogService = widget.catalogService ?? ProductCatalogService.instance;
    _isLoading = !_catalogService.isLoaded;
    _storeCtrl = TextEditingController(
      text: widget.initialStoreName ?? 'Supermarché / Supérette locale',
    );
    _addressCtrl = TextEditingController(
      text: widget.initialAddress ?? 'Cité 1000 Logts, Bât 12, Hydra, Alger',
    );
    _searchCtrl = TextEditingController();
    _generatedPin = _generateCryptographicPin();

    _searchCtrl.addListener(() {
      setState(() {});
    });

    if (_isLoading) {
      _initCatalog();
    }
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _addressCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _generateCryptographicPin() {
    final rng = Random.secure();
    return (1000 + rng.nextInt(9000)).toString();
  }

  Future<void> _initCatalog() async {
    if (_catalogService.isLoaded) {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _catalogService.loadCatalog();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Impossible de charger le catalogue de produits : $e';
        });
      }
    }
  }

  int get _totalCartCount {
    int total = _customItems.length;
    for (final count in _cart.values) {
      total += count;
    }
    return total;
  }

  double get _estimatedTotalBudget {
    double sum = 0.0;
    for (final entry in _cart.entries) {
      final p = entry.key;
      final qty = entry.value;
      final unitPrice = p.estimatedPriceDzd ?? 150.0;
      sum += (unitPrice * qty);
    }
    for (final custom in _customItems) {
      sum += (custom.quantity * 200.0);
    }
    return sum > 0 ? sum : 2500.0;
  }

  void _addToCart(ProductModel product) {
    setState(() {
      final current = _cart[product] ?? 0;
      _cart[product] = current + 1;
    });
  }

  void _removeFromCart(ProductModel product) {
    setState(() {
      final current = _cart[product] ?? 0;
      if (current <= 1) {
        _cart.remove(product);
      } else {
        _cart[product] = current - 1;
      }
    });
  }

  void _openAddCustomItemDialog() {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    String unit = ErrandItemUnit.piece;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.edit_note, color: AppTheme.primaryOrange),
              SizedBox(width: 8),
              Text('Article sur mesure ✍️', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ajoutez un article introuvable dans le catalogue (ex: pain artisanal, produit à la coupe...) :',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom de l\'article *',
                  hintText: 'Ex: 2 Baguettes traditionnelles',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantité'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue: unit,
                      decoration: const InputDecoration(labelText: 'Unité'),
                      items: const [
                        DropdownMenuItem(
                          value: ErrandItemUnit.piece,
                          child: Text('x (Pièce)'),
                        ),
                        DropdownMenuItem(
                          value: ErrandItemUnit.kilogram,
                          child: Text('kg (Poids)'),
                        ),
                        DropdownMenuItem(
                          value: ErrandItemUnit.liter,
                          child: Text('L (Volume)'),
                        ),
                        DropdownMenuItem(
                          value: ErrandItemUnit.pack,
                          child: Text('Pack'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => unit = val);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
              ),
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final qty = double.tryParse(qtyCtrl.text.trim()) ?? 1.0;

                setState(() {
                  _customItems.add(
                    ErrandItemModel(
                      itemId: '',
                      name: name,
                      quantity: qty,
                      unit: unit,
                      notes: 'Article hors catalogue client',
                    ),
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }

  void _openCartModal() {
    final budgetCtrl = TextEditingController(
      text: _estimatedTotalBudget.toStringAsFixed(0),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (innerCtx, setSheetState) {
          final itemsCount = _totalCartCount;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(innerCtx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.shopping_bag_outlined,
                            color: AppTheme.primaryOrange,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Mon Panier ($itemsCount articles)',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  if (_cart.isEmpty && _customItems.isEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Votre panier est vide.\nSélectionnez des articles dans le catalogue.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Articles du catalogue
                    ..._cart.entries.map((entry) {
                      final product = entry.key;
                      final qty = entry.value;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          title: Text(
                            product.nameFr,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${product.formattedPrice} • ${product.isWeighable ? 'kg' : (product.unitType ?? 'x')}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: AppTheme.textMuted,
                                onPressed: () {
                                  _removeFromCart(product);
                                  setSheetState(() {});
                                },
                              ),
                              Text(
                                '$qty',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                color: AppTheme.primaryOrange,
                                onPressed: () {
                                  _addToCart(product);
                                  setSheetState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    // Articles sur mesure
                    ..._customItems.map((custom) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: AppTheme.violetSurface,
                        child: ListTile(
                          title: Text(
                            custom.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Article sur mesure • ${custom.quantity.toStringAsFixed(0)} ${custom.unit}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            color: AppTheme.errorRed,
                            onPressed: () {
                              setState(() {
                                _customItems.remove(custom);
                              });
                              setSheetState(() {});
                            },
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 16),

                    // Détails livraison et commerce
                    TextField(
                      controller: _storeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Commerce / Magasin ciblé *',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Adresse de livraison exacte *',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: budgetCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Budget estimé des achats (DA)',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Code PIN de sécurité
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.violetSurface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.security, color: AppTheme.violetAccent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Code PIN de livraison : $_generatedPin\n(À communiquer au shoppeur après remise des articles et du ticket)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryOrange,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        final storeName = _storeCtrl.text.trim();
                        final address = _addressCtrl.text.trim();
                        if (storeName.isEmpty || address.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppTheme.errorRed,
                              content: Text('Veuillez renseigner le magasin et l\'adresse.'),
                            ),
                          );
                          return;
                        }

                        final budget = double.tryParse(budgetCtrl.text.trim()) ??
                            _estimatedTotalBudget;

                        // Conversion des articles du panier
                        final items = <ErrandItemModel>[];
                        for (final entry in _cart.entries) {
                          final p = entry.key;
                          final qty = entry.value;
                          items.add(
                            ErrandItemModel(
                              itemId: '',
                              name: p.displayName,
                              quantity: qty.toDouble(),
                              unit: p.isWeighable ? 'kg' : (p.unitType ?? 'x'),
                              notes: p.brand != null ? 'Marque : ${p.brand}' : '',
                            ),
                          );
                        }
                        items.addAll(_customItems);

                        final newErrand = ErrandModel(
                          errandId: '',
                          clientId: widget.clientId,
                          storeName: storeName,
                          deliveryAddress: address,
                          estimatedBudget: budget,
                          securePin: _generatedPin,
                          storeDistanceKm: 1.8,
                          etaMinutes: 20,
                          status: ErrandStatus.pending,
                        );

                        await widget.errandService.createErrand(
                          newErrand,
                          items: items,
                        );

                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppTheme.accentGreen,
                              content: Text(
                                'Commande créée et diffusée sur le Radar avec succès ! 🚀',
                              ),
                            ),
                          );
                          Navigator.pop(context);
                        }
                      },
                      child: Text(
                        'Publier ma liste ($itemsCount articles) sur le Radar 🚀',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commander mes courses 🛒'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Ajouter un article hors catalogue',
            onPressed: _openAddCustomItemDialog,
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                tooltip: 'Voir mon panier',
                onPressed: _openCartModal,
              ),
              if (_totalCartCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.errorRed,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_totalCartCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _totalCartCount > 0
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_totalCartCount article${_totalCartCount > 1 ? 's' : ''} au panier',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          Text(
                            '~ ${_estimatedTotalBudget.toStringAsFixed(0)} DA',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primaryOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryOrange,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _openCartModal,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text(
                        'Voir mon panier',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryOrange),
            SizedBox(height: 16),
            Text(
              'Chargement du catalogue national algérien...\n(2 200+ articles)',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 54, color: AppTheme.errorRed),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textDark),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _initCatalog,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final query = _searchCtrl.text.trim();
    final products = _catalogService.search(
      query,
      categoryFilter: _selectedCategory,
      limit: 120,
    );

    return Column(
      children: [
        // 1. Barre de recherche avec support Darja / Français / Arabe / Code-barres
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Rechercher (ex: batata, lait, maqrouna, 613...)',
              prefixIcon: const Icon(Icons.search, color: AppTheme.primaryOrange),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _searchCtrl.clear(),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // 2. Sélecteur horizontal des Rayons / Catégories
        _buildCategoriesBar(),

        // 3. Indicateur de rayon sélectionné & total trouvé
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedCategory ?? 'Tous les rayons',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.textDark,
                ),
              ),
              Text(
                '${products.length} produit${products.length > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),

        // 4. Liste / Grille des Produits
        Expanded(
          child: products.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: products.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final qtyInCart = _cart[product] ?? 0;

                    return _buildProductCard(product, qtyInCart);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCategoriesBar() {
    final categories = _catalogService.categories;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Option « Tous les rayons »
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text('Tous les rayons'),
              selected: _selectedCategory == null,
              selectedColor: AppTheme.primaryOrange,
              labelStyle: TextStyle(
                color: _selectedCategory == null ? Colors.white : AppTheme.textDark,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              onSelected: (_) {
                setState(() => _selectedCategory = null);
              },
            ),
          ),

          // Puces pour chaque rayon du catalogue
          ...categories.map((cat) {
            final isSelected = _selectedCategory == cat;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(cat),
                selected: isSelected,
                selectedColor: AppTheme.primaryOrange,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textDark,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
                onSelected: (selected) {
                  setState(() {
                    _selectedCategory = selected ? cat : null;
                  });
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProductCard(ProductModel product, int qtyInCart) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: qtyInCart > 0
              ? AppTheme.primaryOrange.withValues(alpha: 0.6)
              : const Color(0xFFE2E8F0),
          width: qtyInCart > 0 ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Icône de catégorie / unité
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.violetSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  product.isWeighable ? Icons.scale : Icons.shopping_basket,
                  color: AppTheme.violetAccent,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Détails du produit
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.nameFr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (product.nameAr != null && product.nameAr!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      product.nameAr!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          product.formattedPrice,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentGreen,
                          ),
                        ),
                      ),
                      if (product.brand != null &&
                          product.brand!.isNotEmpty &&
                          product.brand != 'N/A') ...[
                        const SizedBox(width: 8),
                        Text(
                          product.brand!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Contrôles Panier (+ / -)
            if (qtyInCart == 0)
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.violetSurface,
                  foregroundColor: AppTheme.primaryOrange,
                ),
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'Ajouter au panier',
                onPressed: () => _addToCart(product),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    color: AppTheme.textMuted,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _removeFromCart(product),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$qtyInCart',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    color: AppTheme.primaryOrange,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _addToCart(product),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 56,
              color: AppTheme.textMuted.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Aucun article trouvé dans ce rayon',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Essayez un autre mot-clé ou ajoutez un article sur mesure.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
              ),
              onPressed: _openAddCustomItemDialog,
              icon: const Icon(Icons.edit_note),
              label: const Text('Ajouter un article sur mesure ✍️'),
            ),
          ],
        ),
      ),
    );
  }
}
