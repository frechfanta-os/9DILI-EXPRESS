import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/errand_model.dart';
import '../../models/errand_bid_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/errand_service.dart';
import '../../services/map_tracking_service.dart';
import '../../services/user_service.dart';
import '../../services/product_catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/map_markers.dart';
import '../widgets/client_shopper_toggle.dart';
import '../../services/user_mode_service.dart';
import '../../services/notification_service.dart';
import 'profile_screen.dart';
import 'shopping_mode_screen.dart';
import 'receipt_screen.dart';
import 'delivery_tracking_screen.dart';
import 'create_errand_screen.dart';
import 'client_radar_screen.dart';

/// Écran principal 9DILI EXPRESS (Stitch UI/UX V2).
/// Adapte l'expérience selon le rôle (Client vs Shopper).
class HomeScreen extends StatefulWidget {
  final AuthService authService;
  final UserService userService;
  final ErrandService errandService;
  final ProductCatalogService? catalogService;
  final NotificationService? notificationService;

  const HomeScreen({
    super.key,
    required this.authService,
    required this.userService,
    required this.errandService,
    this.catalogService,
    this.notificationService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;
  bool _shopperMapView = false;
  late AppMode _currentMode;
  String _detectedGpsAddress = 'Position GPS en détection...';
  GeoPoint? _currentGeoPoint;

  @override
  void initState() {
    super.initState();
    _currentMode = UserModeService.instance.currentMode;
    _initGpsLocation();
  }

  Future<void> _initGpsLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _detectedGpsAddress = 'Localisation désactivée — Activez le GPS 📍';
            _currentGeoPoint = null;
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
              _detectedGpsAddress = 'Autorisation GPS requise ⚠️';
              _currentGeoPoint = null;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _detectedGpsAddress = 'GPS bloqué — Paramètres système requis ⚙️';
            _currentGeoPoint = null;
          });
        }
        return;
      }

      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) {
        setState(() {
          _currentGeoPoint = GeoPoint(lastPos.latitude, lastPos.longitude);
          _detectedGpsAddress =
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
          _currentGeoPoint =
              GeoPoint(resolvedPos.latitude, resolvedPos.longitude);
          _detectedGpsAddress =
              'Position GPS certifiée (${resolvedPos.latitude.toStringAsFixed(5)}, ${resolvedPos.longitude.toStringAsFixed(5)})';
        });
      } else if (_currentGeoPoint == null && mounted) {
        setState(() {
          _detectedGpsAddress =
              'Signal GPS introuvable — Touchez pour actualiser 🔄';
        });
      }
    } catch (_) {
      if (mounted && _currentGeoPoint == null) {
        setState(() {
          _detectedGpsAddress =
              'Signal GPS introuvable — Touchez pour actualiser 🔄';
        });
      }
    }
  }

  void _handleModeChange(AppMode newMode, UserModel user) async {
    if (newMode == _currentMode) return;

    if (newMode == AppMode.shopper) {
      final prereq = UserModeService.instance.checkShopperPrerequisites(user);
      if (!prereq.isEligible) {
        _showShopperPrerequisitesModal(user, prereq);
        return;
      }
    }

    setState(() {
      _currentMode = newMode;
    });
    await UserModeService.instance.setMode(newMode);
  }

  void _showShopperPrerequisitesModal(
    UserModel user,
    ShopperPrerequisitesResult prereq,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.shopperOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.delivery_dining,
                    color: AppTheme.shopperOrange,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activer le Mode Shoppeur',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Conditions requises pour livrer des courses',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Pour garantir la fiabilité des livraisons et la communication avec les clients, veuillez compléter votre profil :',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),

            // Liste des prérequis
            _buildPrerequisiteItem(
              title: 'Nom complet',
              subtitle: user.fullName.isNotEmpty
                  ? user.fullName
                  : 'À renseigner',
              isValid: prereq.hasFullName,
            ),
            _buildPrerequisiteItem(
              title: 'Numéro de téléphone vérifié',
              subtitle: user.hasValidPhone
                  ? (user.phone ?? '')
                  : 'Obligatoire pour appeler le client avant livraison',
              isValid: prereq.hasValidPhone,
            ),
            _buildPrerequisiteItem(
              title: 'Moyen de déplacement',
              subtitle: 'Véhicule déclaré : ${user.transport.labelFr}',
              isValid: prereq.hasTransport,
            ),
            _buildPrerequisiteItem(
              title: 'Trésorerie en poche',
              subtitle:
                  'Solde actuel : ${user.availableCash.toStringAsFixed(0)} DA (pour avancer les achats)',
              isValid: true,
            ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Plus tard'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.shopperOrange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            authService: widget.authService,
                            userService: widget.userService,
                          ),
                        ),
                      );
                    },
                    child: const Text('Compléter mon profil ✍️'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrerequisiteItem({
    required String title,
    required String subtitle,
    required bool isValid,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.error_outline,
            color: isValid ? AppTheme.clientGreen : AppTheme.shopperOrange,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isValid ? AppTheme.textDark : AppTheme.shopperOrange,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMissingPhoneDialog({
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.phone_android, color: AppTheme.warningOrange),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    authService: widget.authService,
                    userService: widget.userService,
                  ),
                ),
              );
            },
            child: const Text('Compléter mon profil'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PARCOURS CLIENT : CRÉATION DE LISTE & CATALOGUE
  // ==========================================

  void _openCreateListDialog(UserModel user) {
    if (!user.hasValidPhone) {
      _showMissingPhoneDialog(
        title: 'Numéro de téléphone requis',
        message: 'Pour créer une course et être joignable par les shoppeurs, veuillez renseigner votre numéro de téléphone dans votre profil.',
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateErrandScreen(
          clientId: user.uid,
          errandService: widget.errandService,
          catalogService:
              widget.catalogService ?? ProductCatalogService.instance,
          initialAddress: _detectedGpsAddress,
          initialGeoPoint: _currentGeoPoint,
        ),
      ),
    );
  }

  void _confirmCancelErrand(ErrandModel errand, String clientId) {
    final isPending = errand.status == ErrandStatus.pending;
    final isAccepted = errand.status == ErrandStatus.accepted;

    if (!isPending && !isAccepted) {
      String explanation;
      if (errand.status == ErrandStatus.shopping) {
        explanation = 'Le shoppeur est actuellement en magasin pour effectuer vos achats. Pour toute annulation ou ajustement, veuillez le contacter directement par téléphone.';
      } else if (errand.status == ErrandStatus.delivering) {
        explanation = 'Le shoppeur est actuellement en route pour vous livrer. L\'annulation unilatérale n\'est plus possible à ce stade.';
      } else if (errand.status == ErrandStatus.completed) {
        explanation = 'Cette course est déjà clôturée et archivée.';
      } else {
        explanation = 'Cette course est déjà annulée.';
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.violetAccent),
              SizedBox(width: 8),
              Text('Information commande', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Text(explanation, style: const TextStyle(fontSize: 13)),
          actions: [
            if (errand.shopperPhone != null && errand.shopperPhone!.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _makeMandatoryCall(errand, 'Shoppeur', errand.shopperPhone);
                },
                icon: const Icon(Icons.phone, size: 16),
                label: const Text('Appeler le shoppeur'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Compris'),
            ),
          ],
        ),
      );
      return;
    }

    final title = isPending ? 'Retirer la commande ?' : 'Annuler la commande ?';
    final message = isPending
        ? 'Voulez-vous vraiment retirer cette commande ? Elle sera immédiatement supprimée du radar des shoppeurs.'
        : 'Un shoppeur a déjà été assigné à cette commande (${errand.shopperPhone ?? 'Shoppeur'}). L\'annulation à ce stade préviendra le shoppeur et libérera la course. Confirmer l\'annulation ?';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.errorRed),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Garder ma commande'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.errandService.cancelErrand(
                  errandId: errand.errandId,
                  clientId: clientId,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppTheme.accentGreen,
                      content: Text('Commande retirée et annulée avec succès.'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.errorRed,
                      content: Text('Échec de l\'annulation : $e'),
                    ),
                  );
                }
              }
            },
            child: const Text('Confirmer l\'annulation'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PARCOURS SHOPPER : OFFRES & CONFIRMATION
  // ==========================================

  void _openPlaceBidDialog(ErrandModel errand, UserModel shopper) {
    if (!shopper.hasValidPhone) {
      _showMissingPhoneDialog(
        title: 'Numéro de téléphone requis',
        message: 'Pour faire une offre sur une course, votre numéro de téléphone doit être renseigné sur votre profil.',
      );
      return;
    }

    final commissionCtrl = TextEditingController(text: '350');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Proposer une commission — ${errand.storeName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '💰 Trésorerie requise : ${errand.treasuryRequired.toStringAsFixed(0)} DA',
            ),
            Text('📍 Distance : ${errand.storeDistanceKm ?? 2.1} km'),
            const SizedBox(height: 16),
            TextField(
              controller: commissionCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Votre commission souhaitée (DA)',
                prefixIcon: Icon(Icons.delivery_dining),
              ),
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
            onPressed: () async {
              final comm = double.tryParse(commissionCtrl.text.trim()) ?? 350.0;
              final bid = ErrandBidModel(
                bidId: '',
                shopperId: shopper.uid,
                shopperName: shopper.fullName,
                shopperPhone: shopper.phone,
                shopperRating: shopper.rating,
                proposedCommission: comm,
                status: BidStatus.pending,
              );
              await widget.errandService.placeBid(errand.errandId, bid);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Envoyer mon offre'),
          ),
        ],
      ),
    );
  }

  // Règle stricte : L'appel est obligatoire avant la confirmation définitive avec attestation explicite
  Future<void> _makeMandatoryCall(
    ErrandModel errand,
    String partnerName,
    String? phone,
  ) async {
    final currentUid = widget.authService.currentUser?.uid ?? 'unknown_user';
    final isValidPhone = phone != null && UserModel.isValidPhone(phone);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.phone_in_talk,
                color: AppTheme.primaryOrange,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Échange Téléphonique',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dans 9DILI EXPRESS, un contact direct est obligatoire avant la validation afin d\'aligner les détails des achats et éviter tout malentendu.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.violetSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isValidPhone
                      ? AppTheme.violetAccent.withValues(alpha: 0.3)
                      : AppTheme.errorRed.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Interlocuteur : $partnerName',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isValidPhone
                        ? 'Numéro : $phone'
                        : (phone != null && phone.isNotEmpty
                              ? 'Numéro invalide : $phone'
                              : 'Numéro de téléphone non renseigné sur le profil.'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isValidPhone
                          ? AppTheme.textDark
                          : AppTheme.errorRed,
                    ),
                  ),
                  if (isValidPhone) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () async {
                        final uri = Uri.parse('tel:$phone');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                      icon: const Icon(Icons.call, size: 16),
                      label: Text(
                        'Composer : $phone',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    const Text(
                      '⚠️ Impossible d\'attester un appel sans numéro valide.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.errorRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Avez-vous bien convenu des articles et de la commission par téléphone ?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isValidPhone
                  ? AppTheme.accentGreen
                  : Colors.grey.shade400,
              foregroundColor: Colors.white,
            ),
            onPressed: isValidPhone
                ? () => Navigator.of(dialogCtx).pop(true)
                : null,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('J\'atteste l\'appel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.errandService.markCallCompleted(
        errandId: errand.errandId,
        confirmedByUserId: currentUid,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.accentGreen,
          content: Text(
            'Appel obligatoire avec $partnerName attesté ! Vous pouvez maintenant confirmer la course. 📞',
          ),
        ),
      );
    }
  }

  void _openBidsSheet(ErrandModel errand) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Offres des Shoppeurs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<ErrandBidModel>>(
              stream: widget.errandService.streamBids(errand.errandId),
              builder: (bidsCtx, snapshot) {
                final bids = snapshot.data ?? [];
                if (bids.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'En attente des offres des shoppeurs à proximité...',
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: bids.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (bidsListCtx, index) {
                    final bid = bids[index];
                    return Card(
                      color: AppTheme.violetSurface,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      bid.shopperName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.star,
                                          color: Colors.amber,
                                          size: 14,
                                        ),
                                        Text(
                                          ' ${bid.shopperRating.toStringAsFixed(1)}',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Text(
                                  '${bid.proposedCommission.toStringAsFixed(0)} DA',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primaryOrange,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              children: [
                                // Bouton Appeler obligatoire
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _makeMandatoryCall(
                                      errand,
                                      bid.shopperName,
                                      bid.shopperPhone,
                                    ),
                                    icon: const Icon(Icons.phone, size: 16),
                                    label: const Text(
                                      'Appeler',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Bouton Confirmer (Bloqué si appel non passé !)
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: errand.callCompleted
                                          ? AppTheme.accentGreen
                                          : Colors.grey.shade400,
                                    ),
                                    onPressed: () async {
                                      if (!errand.callCompleted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            backgroundColor: AppTheme.errorRed,
                                            content: Text(
                                              'Règle stricte : L\'appel avec le shoppeur est obligatoire avant confirmation !',
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      await widget.errandService.acceptBid(
                                        errandId: errand.errandId,
                                        bidId: bid.bidId,
                                        shopperId: bid.shopperId,
                                        shopperPhone: bid.shopperPhone,
                                        agreedCommission:
                                            bid.proposedCommission,
                                      );
                                      if (ctx.mounted) Navigator.pop(ctx);
                                    },
                                    child: Text(
                                      errand.callCompleted
                                          ? 'Confirmer'
                                          : 'Appel requis',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = widget.authService.currentUser;
    if (authUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<UserModel?>(
      stream: widget.userService.streamUser(authUser.uid),
      builder: (context, userSnap) {
        final userModel =
            userSnap.data ??
            UserModel(
              uid: authUser.uid,
              fullName: authUser.displayName ?? 'Utilisateur',
              email: authUser.email,
            );

        final isShopperMode = _currentMode == AppMode.shopper;
        final primaryColor = AppTheme.primaryFor(_currentMode);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/branding/9dili/9dili_icon_master.png',
                    width: 26,
                    height: 26,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.flash_on,
                        color: primaryColor,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '9DILI EXPRESS',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: 'Mon Profil',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        authService: widget.authService,
                        userService: widget.userService,
                      ),
                    ),
                  );
                },
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(58),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Center(
                  child: ClientShopperToggle(
                    currentMode: _currentMode,
                    onModeChanged: (mode) => _handleModeChange(mode, userModel),
                  ),
                ),
              ),
            ),
          ),
          body: isShopperMode
              ? _buildShopperRadarView(userModel)
              : _buildClientHomeView(userModel),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _navIndex,
            onDestinationSelected: (i) {
              if (i == 1) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      authService: widget.authService,
                      userService: widget.userService,
                    ),
                  ),
                );
              } else {
                setState(() => _navIndex = i);
              }
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.explore_outlined),
                selectedIcon: const Icon(Icons.explore),
                label: isShopperMode ? 'Radar Shopper' : 'Accueil Client',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profil',
              ),
            ],
          ),
          floatingActionButton: null,
        );
      },
    );
  }

  // ==========================================
  // SECTION 1 : VUE ACCUEIL CLIENT
  // ==========================================

  Widget _buildClientHomeView(UserModel user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Carte position GPS certifiée (anti-fraude, sans saisie manuelle)
          Card(
            color: AppTheme.violetSurface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.gps_fixed, color: AppTheme.accentGreen),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Position de livraison certifiée (GPS)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.violetAccent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _detectedGpsAddress,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.refresh,
                      color: AppTheme.violetAccent,
                    ),
                    tooltip: 'Actualiser ma position GPS',
                    onPressed: _initGpsLocation,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Accès direct au Radar Shoppers Client
          Card(
            elevation: 2,
            color: AppTheme.secondaryNavy,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.radar,
                      color: AppTheme.clientGreen,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Radar Shoppers en Direct 📡',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Visualisez les livreurs disponibles autour de vous en temps réel.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.clientGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ClientRadarScreen(
                            currentUser: user,
                            userService: widget.userService,
                            errandService: widget.errandService,
                            authService: widget.authService,
                            catalogService: widget.catalogService,
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Explorer',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Bouton principal « Créer ma liste » conservé
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.clientGreen,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () => _openCreateListDialog(user),
            icon: const Icon(Icons.edit_note, size: 24),
            label: const Text(
              'Créer ma liste 📝',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),

          // Titre Commandes Actives
          const Text(
            'Mes Commandes en cours',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          StreamBuilder<List<ErrandModel>>(
            stream: widget.errandService.streamClientErrands(user.uid),
            builder: (context, snapshot) {
              final errands = snapshot.data ?? [];

              if (errands.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.shopping_basket_outlined,
                          size: 60,
                          color: AppTheme.textMuted.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Aucune commande active',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Appuyez sur « Créer ma liste » pour lancer votre course !',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: errands.length,
                separatorBuilder: (_, index) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final errand = errands[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  errand.storeName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildStatusBadge(errand.status),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '📍 Livraison : ${errand.deliveryAddress}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const Divider(height: 20),

                          // Affichage séparé et transparent des montants
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildPriceRow(
                                  'Budget estimé achats :',
                                  '${errand.estimatedBudget.toStringAsFixed(0)} DA',
                                ),
                                const SizedBox(height: 4),
                                _buildPriceRow(
                                  'Commission négociée :',
                                  '+ ${errand.negotiatedCommission.toStringAsFixed(0)} DA',
                                  color: AppTheme.primaryOrange,
                                ),
                                if (errand.ticketAmount != null) ...[
                                  const SizedBox(height: 4),
                                  _buildPriceRow(
                                    'Montant réel du ticket :',
                                    '${errand.ticketAmount!.toStringAsFixed(2)} DA',
                                    isBold: true,
                                  ),
                                ],
                                const Divider(height: 14),
                                _buildPriceRow(
                                  'TOTAL FINAL :',
                                  '${errand.totalAmount.toStringAsFixed(2)} DA',
                                  isBold: true,
                                  color: AppTheme.textDark,
                                  fontSize: 15,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Progression de la commande
                          _buildProgressBar(errand.status),
                          const SizedBox(height: 14),

                          // Boutons d'accès direct Appeler, Message, Suivi GPS
                          Row(
                            children: [
                              if (errand.status == ErrandStatus.pending) ...[
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.violetAccent,
                                    ),
                                    onPressed: () => _openBidsSheet(errand),
                                    icon: const Icon(
                                      Icons.local_offer,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Voir les Offres',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.errorRed,
                                    side: const BorderSide(
                                      color: AppTheme.errorRed,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _confirmCancelErrand(errand, user.uid),
                                  icon: const Icon(
                                    Icons.cancel_outlined,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Retirer',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ] else if (errand.status ==
                                  ErrandStatus.cancelled) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.errorRed.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 16,
                                        color: AppTheme.errorRed,
                                      ),
                                      SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Commande retirée et annulée (hors radar).',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.errorRed,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                IconButton.filledTonal(
                                  onPressed: () => _makeMandatoryCall(
                                    errand,
                                    'Shoppeur',
                                    errand.shopperPhone,
                                  ),
                                  icon: const Icon(Icons.phone),
                                  tooltip: 'Appeler le shoppeur',
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Ouverture du chat 💬'),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.chat),
                                  tooltip: 'Envoyer un message',
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.clientGreen,
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              DeliveryTrackingScreen(
                                                errand: errand,
                                                errandService:
                                                    widget.errandService,
                                                isShopperView: false,
                                              ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.navigation,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Suivi GPS & PIN',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                if (errand.status == ErrandStatus.accepted ||
                                    errand.status == ErrandStatus.shopping) ...[
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.cancel_outlined,
                                      color: AppTheme.errorRed,
                                      size: 20,
                                    ),
                                    tooltip: 'Annuler la commande',
                                    onPressed: () =>
                                        _confirmCancelErrand(errand, user.uid),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SECTION 2 : VUE RADAR SHOPPER
  // ==========================================

  Widget _buildShopperRadarView(UserModel shopper) {
    return Column(
      children: [
        // Bandeau Radar & Trésorerie
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: shopper.isOnline
              ? AppTheme.accentGreen.withValues(alpha: 0.12)
              : const Color(0xFFF1F5F9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.radar,
                    color: shopper.isOnline
                        ? AppTheme.accentGreen
                        : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shopper.isOnline ? 'Radar Actif' : 'Radar Hors ligne',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: shopper.isOnline
                              ? AppTheme.accentGreen
                              : AppTheme.textMuted,
                        ),
                      ),
                      Text(
                        'En poche : ${shopper.availableCash.toStringAsFixed(0)} DA',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: shopper.isOnline,
                activeThumbColor: AppTheme.accentGreen,
                onChanged: (val) {
                  if (val && !shopper.hasValidPhone) {
                    _showMissingPhoneDialog(
                      title: 'Numéro de téléphone requis',
                      message: 'Pour passer en ligne et recevoir des alertes de courses sur le Radar, veuillez renseigner un numéro de téléphone valide sur votre profil.',
                    );
                    return;
                  }
                  widget.userService.setOnlineStatus(shopper.uid, val);
                },
              ),
            ],
          ),
        ),

        // Sélecteur Vue Carte / Vue Liste pour le Shopper
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_outlined, size: 16),
                        SizedBox(width: 6),
                        Text('Carte Radar 🗺️'),
                      ],
                    ),
                  ),
                  selected: _shopperMapView,
                  selectedColor: AppTheme.violetAccent,
                  labelStyle: TextStyle(
                    color: _shopperMapView ? Colors.white : AppTheme.textDark,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (v) => setState(() => _shopperMapView = true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.list_alt, size: 16),
                        SizedBox(width: 6),
                        Text('Liste Courses 📋'),
                      ],
                    ),
                  ),
                  selected: !_shopperMapView,
                  selectedColor: AppTheme.violetAccent,
                  labelStyle: TextStyle(
                    color: !_shopperMapView ? Colors.white : AppTheme.textDark,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (v) => setState(() => _shopperMapView = false),
                ),
              ),
            ],
          ),
        ),

        // Courses actives prises en charge par le shoppeur
        StreamBuilder<List<ErrandModel>>(
          stream: widget.errandService.streamShopperErrands(shopper.uid),
          builder: (context, activeSnap) {
            final activeList = (activeSnap.data ?? [])
                .where(
                  (e) =>
                      e.status != ErrandStatus.completed &&
                      e.status != ErrandStatus.cancelled,
                )
                .toList();
            if (activeList.isEmpty) return const SizedBox.shrink();

            return Container(
              color: AppTheme.violetSurface,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mes Courses en cours (Shopper) 🚴',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppTheme.violetAccent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...activeList.map((activeErrand) {
                    return Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    activeErrand.storeName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _buildStatusBadge(activeErrand.status),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '📍 ${activeErrand.deliveryAddress}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (activeErrand.status ==
                                    ErrandStatus.accepted)
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryOrange,
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ShoppingModeScreen(
                                            errand: activeErrand,
                                            errandService: widget.errandService,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.shopping_cart,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Mode En Magasin',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                if (activeErrand.status ==
                                    ErrandStatus.shopping) ...[
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.warningOrange,
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ReceiptScreen(
                                            errand: activeErrand,
                                            errandService: widget.errandService,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.receipt_long,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Ticket de Caisse 🧾',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                                if (activeErrand.status ==
                                    ErrandStatus.delivering)
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.accentGreen,
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              DeliveryTrackingScreen(
                                                errand: activeErrand,
                                                errandService:
                                                    widget.errandService,
                                                isShopperView: true,
                                              ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.pin, size: 16),
                                    label: const Text(
                                      'Valider Remise & PIN',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),

        // Courses en attente (Radar)
        Expanded(
          child: StreamBuilder<List<ErrandModel>>(
            stream: widget.errandService.streamPendingErrands(),
            builder: (context, snapshot) {
              final errands = snapshot.data ?? [];

              if (errands.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.radar,
                        size: 64,
                        color: AppTheme.textMuted.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Aucune course disponible sur le radar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Restez en ligne pour recevoir les alertes des clients.',
                      ),
                    ],
                  ),
                );
              }

              // Affichage Cartographique interactif du Radar Shopper
              if (_shopperMapView) {
                final shopperPos = shopper.location != null
                    ? LatLng(
                        shopper.location!.latitude,
                        shopper.location!.longitude,
                      )
                    : const LatLng(36.7538, 3.0588);

                return Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCenter: shopperPos,
                        initialZoom: 13.5,
                      ),
                      children: [
                        MapTrackingService.buildOsmTileLayer(),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: shopperPos,
                              radius:
                                  (shopper.searchRadiusKm > 0
                                      ? shopper.searchRadiusKm
                                      : 5.0) *
                                  1000,
                              useRadiusInMeter: true,
                              color: AppTheme.accentGreen.withValues(
                                alpha: 0.08,
                              ),
                              borderColor: AppTheme.accentGreen.withValues(
                                alpha: 0.4,
                              ),
                              borderStrokeWidth: 1.5,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: shopperPos,
                              width: 44,
                              height: 44,
                              child: const ShopperMarkerWidget(size: 40),
                            ),
                            ...errands.map((errand) {
                              final ePos = errand.deliveryGeoPoint != null
                                  ? LatLng(
                                      errand.deliveryGeoPoint!.latitude,
                                      errand.deliveryGeoPoint!.longitude,
                                    )
                                  : LatLng(
                                      shopperPos.latitude + 0.005,
                                      shopperPos.longitude + 0.005,
                                    );

                              return Marker(
                                point: ePos,
                                width: 44,
                                height: 44,
                                child: GestureDetector(
                                  onTap: () =>
                                      _openPlaceBidDialog(errand, shopper),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryOrange,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.shopping_bag,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          '${errands.length} course(s) disponible(s) sur la carte',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: errands.length,
                separatorBuilder: (_, index) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final errand = errands[index];
                  final hasEnoughCash =
                      shopper.availableCash >= errand.treasuryRequired;

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  errand.storeName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.violetSurface,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${errand.storeDistanceKm ?? 1.5} km',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.violetAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('📍 Adresse : ${errand.deliveryAddress}'),
                          const SizedBox(height: 10),

                          // Trésorerie requise & Budget
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: hasEnoughCash
                                  ? AppTheme.accentGreen.withValues(alpha: 0.08)
                                  : AppTheme.errorRed.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.account_balance_wallet,
                                      size: 18,
                                      color: hasEnoughCash
                                          ? AppTheme.accentGreen
                                          : AppTheme.errorRed,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Trésorerie : ${errand.treasuryRequired.toStringAsFixed(0)} DA',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: hasEnoughCash
                                            ? AppTheme.accentGreen
                                            : AppTheme.errorRed,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (hasEnoughCash
                                                ? AppTheme.accentGreen
                                                : AppTheme.errorRed)
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    hasEnoughCash
                                        ? 'Fonds OK ✅'
                                        : 'Fonds insuffisants ⚠️',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: hasEnoughCash
                                          ? AppTheme.accentGreen
                                          : AppTheme.errorRed,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Boutons distincts : Faire une offre, Appeler le client, etc.
                          Row(
                            children: [
                              IconButton.filledTonal(
                                onPressed: () => _makeMandatoryCall(
                                  errand,
                                  'Client',
                                  errand.clientPhone,
                                ),
                                icon: const Icon(Icons.phone),
                                tooltip:
                                    'Appeler le client (Étape obligatoire)',
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryOrange,
                                  ),
                                  onPressed: () =>
                                      _openPlaceBidDialog(errand, shopper),
                                  icon: const Icon(Icons.local_offer, size: 16),
                                  label: const Text('Faire une offre'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // HELPERS UI
  // ==========================================

  Widget _buildPriceRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
    double fontSize = 13,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: fontSize, color: AppTheme.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? AppTheme.textDark,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(String status) {
    double progress = 0.2;
    if (status == ErrandStatus.accepted) progress = 0.4;
    if (status == ErrandStatus.shopping) progress = 0.6;
    if (status == ErrandStatus.delivering) progress = 0.8;
    if (status == ErrandStatus.completed) progress = 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFFE2E8F0),
            color: progress == 1.0
                ? AppTheme.accentGreen
                : AppTheme.primaryOrange,
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case ErrandStatus.pending:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        label = 'En attente d\'offres';
        break;
      case ErrandStatus.accepted:
        bg = AppTheme.violetSurface;
        fg = AppTheme.violetAccent;
        label = 'Course acceptée';
        break;
      case ErrandStatus.shopping:
        bg = Colors.purple.shade100;
        fg = Colors.purple.shade900;
        label = 'Achats en magasin';
        break;
      case ErrandStatus.delivering:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        label = 'En livraison';
        break;
      case ErrandStatus.completed:
        bg = AppTheme.accentGreen.withValues(alpha: 0.15);
        fg = AppTheme.accentGreen;
        label = 'Terminée';
        break;
      case ErrandStatus.cancelled:
        bg = AppTheme.errorRed.withValues(alpha: 0.15);
        fg = AppTheme.errorRed;
        label = 'Annulée';
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
