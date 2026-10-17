import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../models/errand_model.dart';
import '../../models/errand_item_model.dart';
import '../../models/product_model.dart';
import '../../services/errand_service.dart';
import '../../services/map_tracking_service.dart';
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
  final GeoPoint? initialGeoPoint;

  const CreateErrandScreen({
    super.key,
    required this.clientId,
    required this.errandService,
    this.catalogService,
    this.initialAddress,
    this.initialStoreName,
    this.initialGeoPoint,
  });

  @override
  State<CreateErrandScreen> createState() => _CreateErrandScreenState();
}

class _CreateErrandScreenState extends State<CreateErrandScreen> {
  late final ProductCatalogService _catalogService;

  late final TextEditingController _storeCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _searchCtrl;

  GeoPoint? _deliveryGeoPoint;
  bool _isFetchingGps = false;

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
    _deliveryGeoPoint = widget.initialGeoPoint;
    _storeCtrl = TextEditingController(text: widget.initialStoreName ?? '');
    if (widget.initialGeoPoint != null) {
      _addressCtrl = TextEditingController(
        text:
            'Position GPS certifiée (${widget.initialGeoPoint!.latitude.toStringAsFixed(5)}, ${widget.initialGeoPoint!.longitude.toStringAsFixed(5)})',
      );
    } else if (widget.initialAddress != null &&
        widget.initialAddress!.isNotEmpty &&
        !widget.initialAddress!.contains('détection') &&
        !widget.initialAddress!.contains('Hydra') &&
        !widget.initialAddress!.contains('Algérie') &&
        !widget.initialAddress!.contains('introuvable') &&
        !widget.initialAddress!.contains('requise') &&
        !widget.initialAddress!.contains('désactivée')) {
      _addressCtrl = TextEditingController(text: widget.initialAddress);
    } else {
      _addressCtrl = TextEditingController(
        text: 'Acquisition du signal GPS...',
      );
      _autoFetchInitialGps();
    }
    _searchCtrl = TextEditingController();
    _generatedPin = _generateCryptographicPin();

    _searchCtrl.addListener(() {
      setState(() {});
    });

    if (_isLoading) {
      _initCatalog();
    }
  }

  Future<void> _autoFetchInitialGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _addressCtrl.text = 'Localisation désactivée — Activez le GPS 📍';
            _deliveryGeoPoint = null;
          });
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _addressCtrl.text = 'Autorisation GPS requise ⚠️';
              _deliveryGeoPoint = null;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _addressCtrl.text = 'GPS bloqué — Paramètres système requis ⚙️';
            _deliveryGeoPoint = null;
          });
        }
        return;
      }

      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) {
        setState(() {
          _deliveryGeoPoint = GeoPoint(lastPos.latitude, lastPos.longitude);
          _addressCtrl.text =
              'Position GPS certifiée (${lastPos.latitude.toStringAsFixed(5)}, ${lastPos.longitude.toStringAsFixed(5)})';
        });
      }

      Position? freshPos;
      try {
        freshPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        try {
          freshPos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 5),
            ),
          );
        } catch (_) {}
      }

      if (freshPos != null && mounted) {
        final resolvedPos = freshPos;
        setState(() {
          _deliveryGeoPoint =
              GeoPoint(resolvedPos.latitude, resolvedPos.longitude);
          _addressCtrl.text =
              'Position GPS certifiée (${resolvedPos.latitude.toStringAsFixed(5)}, ${resolvedPos.longitude.toStringAsFixed(5)})';
        });
      } else if (_deliveryGeoPoint == null && mounted) {
        setState(() {
          _addressCtrl.text =
              'Signal GPS introuvable — Touchez pour réessayer 🔄';
        });
      }
    } catch (_) {
      if (mounted && _deliveryGeoPoint == null) {
        setState(() {
          _addressCtrl.text =
              'Signal GPS introuvable — Touchez pour réessayer 🔄';
        });
      }
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
          _errorMessage = 'Impossible de charger le catalogue de produits : $e';
        });
      }
    }
  }

  int get _totalCartCount {
    int total = 0;
    for (final custom in _customItems) {
      total += custom.quantity.round();
    }
    for (final count in _cart.values) {
      total += count;
    }
    return total;
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

  void _removeEntirelyFromCart(ProductModel product) {
    setState(() {
      _cart.remove(product);
    });
  }

  void _removeCustomItem(ErrandItemModel item) {
    setState(() {
      _customItems.remove(item);
    });
  }

  void _updateCustomItemQty(ErrandItemModel item, double newQty) {
    setState(() {
      final idx = _customItems.indexOf(item);
      if (idx != -1) {
        if (newQty <= 0) {
          _customItems.removeAt(idx);
        } else {
          _customItems[idx] = item.copyWith(quantity: newQty);
        }
      }
    });
  }

  // ==========================================
  // AJOUT DE PRODUIT PAR PHOTOGRAPHIE
  // ==========================================

  void _openPhotoChoiceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.photo_camera, color: AppTheme.primaryOrange),
                  SizedBox(width: 10),
                  Text(
                    'Photographier un produit 📷',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Prenez une photo nette du produit ou choisissez-en une depuis votre galerie.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.violetSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: AppTheme.violetAccent,
                  ),
                ),
                title: const Text('Prendre une photo'),
                subtitle: const Text('Ouvrir l\'appareil photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProductPhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.violetSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.photo_library,
                    color: AppTheme.violetAccent,
                  ),
                ),
                title: const Text('Choisir depuis la galerie'),
                subtitle: const Text('Sélecteur d\'images Android'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProductPhoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickProductPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image == null) return;

      final file = File(image.path);
      if (await file.exists()) {
        final length = await file.length();
        if (length > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppTheme.errorRed,
                content: Text(
                  'L\'image est trop volumineuse (> 5 Mo). Veuillez choisir une autre photo.',
                ),
              ),
            );
          }
          return;
        }
      }

      if (!mounted) return;
      _openPhotoProductFormDialog(image.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.errorRed,
            content: Text('Impossible d\'accéder à la photo : $e'),
          ),
        );
      }
    }
  }

  void _openPhotoProductFormDialog(String initialImagePath) {
    String currentImagePath = initialImagePath;
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final detailsCtrl = TextEditingController();
    String unit = ErrandItemUnit.piece;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.camera_alt, color: AppTheme.primaryOrange),
              SizedBox(width: 8),
              Text('Article avec photo 📷', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(currentImagePath),
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 120,
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.image, size: 40, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final img = await picker.pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 1024,
                          maxHeight: 1024,
                          imageQuality: 80,
                        );
                        if (img != null) {
                          setDialogState(() => currentImagePath = img.path);
                        }
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text(
                        'Changer de photo',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nom du produit *',
                    hintText: 'Ex: Café soluble 200g',
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
                        decoration: const InputDecoration(
                          labelText: 'Quantité *',
                        ),
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
                            value: 'g',
                            child: Text('g (Grammes)'),
                          ),
                          DropdownMenuItem(
                            value: ErrandItemUnit.liter,
                            child: Text('L (Volume)'),
                          ),
                          DropdownMenuItem(
                            value: 'mL',
                            child: Text('mL (Volume)'),
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
                const SizedBox(height: 10),
                TextField(
                  controller: detailsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Marque, format, détails (Facultatif)',
                    hintText: 'Ex: Bocal en verre, marque Nescafé',
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
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
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppTheme.errorRed,
                      content: Text('Veuillez renseigner le nom du produit.'),
                    ),
                  );
                  return;
                }
                final qty = double.tryParse(qtyCtrl.text.trim()) ?? 1.0;
                final details = detailsCtrl.text.trim();

                setState(() {
                  _customItems.add(
                    ErrandItemModel(
                      itemId: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      quantity: qty > 0 ? qty : 1.0,
                      unit: unit,
                      notes: details,
                      isCustom: true,
                      photoUrl: currentImagePath,
                      status: ErrandItemStatus.pending,
                    ),
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text('Ajouter au panier'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // AJOUT DE PRODUIT PAR SAISIE MANUELLE
  // ==========================================

  void _openAddCustomItemDialog() {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final detailsCtrl = TextEditingController();
    final budgetCtrl = TextEditingController();
    String unit = ErrandItemUnit.piece;
    String? optionalPhotoPath;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.edit_note, color: AppTheme.primaryOrange),
              SizedBox(width: 8),
              Text('Article personnalisé ✍️', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        decoration: const InputDecoration(
                          labelText: 'Quantité *',
                        ),
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
                            value: 'g',
                            child: Text('g (Grammes)'),
                          ),
                          DropdownMenuItem(
                            value: ErrandItemUnit.liter,
                            child: Text('L (Volume)'),
                          ),
                          DropdownMenuItem(
                            value: 'mL',
                            child: Text('mL (Volume)'),
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
                const SizedBox(height: 10),
                TextField(
                  controller: detailsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Marque ou description (Facultatif)',
                    hintText: 'Ex: Bien cuites, marque spécifique',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: budgetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Budget estimé en DA (Facultatif)',
                    hintText: 'Ex: 40',
                  ),
                ),
                const SizedBox(height: 10),
                if (optionalPhotoPath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(optionalPhotoPath!),
                      height: 100,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                OutlinedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final img = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1024,
                      maxHeight: 1024,
                      imageQuality: 80,
                    );
                    if (img != null) {
                      setDialogState(() => optionalPhotoPath = img.path);
                    }
                  },
                  icon: const Icon(Icons.add_a_photo, size: 16),
                  label: Text(
                    optionalPhotoPath != null
                        ? 'Changer la photo'
                        : 'Joindre une photo (Optionnel)',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
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
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppTheme.errorRed,
                      content: Text('Veuillez renseigner le nom du produit.'),
                    ),
                  );
                  return;
                }
                final qty = double.tryParse(qtyCtrl.text.trim()) ?? 1.0;
                final budget = double.tryParse(budgetCtrl.text.trim());

                setState(() {
                  _customItems.add(
                    ErrandItemModel(
                      itemId: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      quantity: qty > 0 ? qty : 1.0,
                      unit: unit,
                      notes: detailsCtrl.text.trim(),
                      isCustom: true,
                      photoUrl: optionalPhotoPath,
                      estimatedPrice: budget,
                      status: ErrandItemStatus.pending,
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

  Future<void> _fetchCurrentGps(StateSetter setSheetState) async {
    setSheetState(() => _isFetchingGps = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.errorRed,
              content: Text(
                'Veuillez activer la localisation GPS sur votre appareil.',
              ),
            ),
          );
        }
        setSheetState(() => _isFetchingGps = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppTheme.errorRed,
                content: Text('Autorisation de géolocalisation refusée.'),
              ),
            );
          }
          setSheetState(() => _isFetchingGps = false);
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      setState(() {
        _deliveryGeoPoint = GeoPoint(pos.latitude, pos.longitude);
        _addressCtrl.text =
            'Position GPS certifiée (${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})';
      });
      setSheetState(() {
        _isFetchingGps = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppTheme.accentGreen,
            content: Text('Position GPS actuelle enregistrée avec succès ! 📍'),
          ),
        );
      }
    } catch (e) {
      setSheetState(() => _isFetchingGps = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.errorRed,
            content: Text('Erreur lors de la capture GPS : $e'),
          ),
        );
      }
    }
  }

  Future<void> _pickPointOnMap(
    BuildContext ctx,
    StateSetter setSheetState,
  ) async {
    LatLng selected = _deliveryGeoPoint != null
        ? LatLng(_deliveryGeoPoint!.latitude, _deliveryGeoPoint!.longitude)
        : const LatLng(36.7538, 3.0588);

    final result = await showDialog<LatLng>(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (innerCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Pointer l\'adresse de livraison 📍',
              style: TextStyle(fontSize: 16),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 350,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: selected,
                    initialZoom: 14.0,
                    onTap: (tapPosition, point) {
                      setDialogState(() {
                        selected = point;
                      });
                    },
                  ),
                  children: [
                    MapTrackingService.buildOsmTileLayer(),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: selected,
                          width: 44,
                          height: 44,
                          child: const Icon(
                            Icons.location_pin,
                            color: AppTheme.errorRed,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentGreen,
                ),
                onPressed: () => Navigator.pop(dialogCtx, selected),
                child: const Text('Confirmer ce point 📍'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      setState(() {
        _deliveryGeoPoint = GeoPoint(result.latitude, result.longitude);
        _addressCtrl.text =
            'Position GPS pointée (${result.latitude.toStringAsFixed(5)}, ${result.longitude.toStringAsFixed(5)})';
      });
      setSheetState(() {});
    }
  }

  void _openCartModal() {
    final ceilingBudgetCtrl = TextEditingController();
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
                                tooltip: 'Diminuer la quantité',
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
                                tooltip: 'Augmenter la quantité',
                                onPressed: () {
                                  _addToCart(product);
                                  setSheetState(() {});
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                color: AppTheme.errorRed,
                                tooltip: 'Retirer du panier',
                                onPressed: () {
                                  _removeEntirelyFromCart(product);
                                  setSheetState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    // Articles sur mesure & photos
                    ..._customItems.map((custom) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: AppTheme.violetSurface,
                        child: ListTile(
                          leading:
                              custom.photoUrl != null &&
                                  custom.photoUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: custom.photoUrl!.startsWith('http')
                                      ? Image.network(
                                          custom.photoUrl!,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => const Icon(
                                            Icons.broken_image,
                                            size: 28,
                                          ),
                                        )
                                      : Image.file(
                                          File(custom.photoUrl!),
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => const Icon(
                                            Icons.broken_image,
                                            size: 28,
                                          ),
                                        ),
                                )
                              : Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.edit_note,
                                    color: AppTheme.violetAccent,
                                  ),
                                ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  custom.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryOrange.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Sur mesure',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryOrange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${custom.quantity.toStringAsFixed(custom.quantity % 1 == 0 ? 0 : 1)} ${custom.unit}${custom.notes.isNotEmpty ? ' • ${custom.notes}' : ''}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: AppTheme.textMuted,
                                onPressed: () {
                                  _updateCustomItemQty(
                                    custom,
                                    custom.quantity - 1,
                                  );
                                  setSheetState(() {});
                                },
                              ),
                              Text(
                                custom.quantity.toStringAsFixed(
                                  custom.quantity % 1 == 0 ? 0 : 1,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                color: AppTheme.primaryOrange,
                                onPressed: () {
                                  _updateCustomItemQty(
                                    custom,
                                    custom.quantity + 1,
                                  );
                                  setSheetState(() {});
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                color: AppTheme.errorRed,
                                tooltip: 'Supprimer',
                                onPressed: () {
                                  _removeCustomItem(custom);
                                  setSheetState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 16),

                    // Détails livraison et commerce
                    TextField(
                      controller: _storeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Commerce / Magasin ciblé (Optionnel)',
                        hintText: 'Ex: Supérette El Baraka ou vide pour commerce de proximité',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressCtrl,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Adresse de livraison certifiée par GPS *',
                        prefixIcon: const Icon(
                          Icons.verified_user,
                          color: AppTheme.accentGreen,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.my_location,
                            color: AppTheme.primaryOrange,
                          ),
                          tooltip: 'Actualiser ma position GPS',
                          onPressed: () => _fetchCurrentGps(setSheetState),
                        ),
                        helperText:
                            'Position verrouillée par GPS contre la fraude',
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Carte Coordonnées GPS Obligatoires
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _deliveryGeoPoint != null
                            ? AppTheme.accentGreen.withValues(alpha: 0.08)
                            : AppTheme.warningOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _deliveryGeoPoint != null
                              ? AppTheme.accentGreen.withValues(alpha: 0.4)
                              : AppTheme.warningOrange.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _deliveryGeoPoint != null
                                    ? Icons.check_circle
                                    : Icons.warning_amber_rounded,
                                color: _deliveryGeoPoint != null
                                    ? AppTheme.accentGreen
                                    : AppTheme.warningOrange,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _deliveryGeoPoint != null
                                      ? 'Position GPS validée 📍'
                                      : 'Position GPS obligatoire pour le Radar *',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _deliveryGeoPoint != null
                                        ? AppTheme.accentGreen
                                        : AppTheme.warningOrange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_deliveryGeoPoint != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Lat: ${_deliveryGeoPoint!.latitude.toStringAsFixed(5)}, Lon: ${_deliveryGeoPoint!.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: _isFetchingGps
                                      ? null
                                      : () => _fetchCurrentGps(setSheetState),
                                  icon: _isFetchingGps
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.my_location, size: 16),
                                  label: const Text(
                                    'Ma position GPS',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _pickPointOnMap(sheetCtx, setSheetState),
                                  icon: const Icon(Icons.map, size: 16),
                                  label: const Text(
                                    'Pointer sur carte',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Plafond de budget facultatif (approximatif ou exact)
                    TextField(
                      controller: ceilingBudgetCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText:
                            'Plafond de budget des achats (DA, Facultatif)',
                        hintText: 'Ex: 3000 (Approximatif ou exact)',
                        helperText: 'Fixez un plafond maximum indicatif pour votre commande',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
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
                          const Icon(
                            Icons.security,
                            color: AppTheme.violetAccent,
                          ),
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
                        final rawStore = _storeCtrl.text.trim();
                        final storeName = rawStore.isNotEmpty
                            ? rawStore
                            : 'Commerce de proximité / Supérette locale';
                        String address = _addressCtrl.text.trim();

                        if (_deliveryGeoPoint != null &&
                            (address.isEmpty ||
                                address.contains('détection'))) {
                          address =
                              'Position GPS certifiée (${_deliveryGeoPoint!.latitude.toStringAsFixed(5)}, ${_deliveryGeoPoint!.longitude.toStringAsFixed(5)})';
                          _addressCtrl.text = address;
                        }

                        if (address.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppTheme.errorRed,
                              content: Text(
                                'Veuillez renseigner votre adresse de livraison.',
                              ),
                            ),
                          );
                          return;
                        }

                        if (_deliveryGeoPoint == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppTheme.errorRed,
                              content: Text(
                                'Règle stricte : Les coordonnées GPS de livraison sont obligatoires pour diffuser votre course sur le Radar.',
                              ),
                            ),
                          );
                          return;
                        }

                        final budget =
                            double.tryParse(ceilingBudgetCtrl.text.trim()) ??
                            0.0;

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
                              notes: p.brand != null
                                  ? 'Marque : ${p.brand}'
                                  : '',
                            ),
                          );
                        }
                        items.addAll(_customItems);

                        final newErrand = ErrandModel(
                          errandId: '',
                          clientId: widget.clientId,
                          storeName: storeName,
                          deliveryAddress: address,
                          deliveryGeoPoint: _deliveryGeoPoint,
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
            icon: const Icon(Icons.photo_camera_outlined),
            tooltip: 'Photographier un produit',
            onPressed: _openPhotoChoiceSheet,
          ),
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
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                          const Text(
                            'Liste prête 🛒',
                            style: TextStyle(
                              fontSize: 16,
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
              const Icon(
                Icons.error_outline,
                size: 54,
                color: AppTheme.errorRed,
              ),
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
              prefixIcon: const Icon(
                Icons.search,
                color: AppTheme.primaryOrange,
              ),
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

        // Boutons d'action rapides : Photographier & Produit personnalisé
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    foregroundColor: AppTheme.primaryOrange,
                    side: const BorderSide(color: AppTheme.primaryOrange),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _openPhotoChoiceSheet,
                  icon: const Icon(Icons.photo_camera, size: 16),
                  label: const Text(
                    '📷 Photographier',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    foregroundColor: AppTheme.violetAccent,
                    side: const BorderSide(color: AppTheme.violetAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _openAddCustomItemDialog,
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text(
                    '+ Produit personnalisé',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                color: _selectedCategory == null
                    ? Colors.white
                    : AppTheme.textDark,
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
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: AppTheme.errorRed,
                    tooltip: 'Désélectionner',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: () => _removeEntirelyFromCart(product),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    color: AppTheme.textMuted,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
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
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
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
