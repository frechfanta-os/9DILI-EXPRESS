import 'package:flutter/material.dart';

import '../../models/errand_model.dart';
import '../../models/errand_bid_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/errand_service.dart';
import '../../services/user_service.dart';
import '../../services/product_catalog_service.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';
import 'shopping_mode_screen.dart';
import 'receipt_screen.dart';
import 'delivery_tracking_screen.dart';
import 'create_errand_screen.dart';

/// Écran principal 9DILI EXPRESS (Stitch UI/UX V2).
/// Adapte l'expérience selon le rôle (Client vs Shopper).
class HomeScreen extends StatefulWidget {
  final AuthService authService;
  final UserService userService;
  final ErrandService errandService;
  final ProductCatalogService? catalogService;

  const HomeScreen({
    super.key,
    required this.authService,
    required this.userService,
    required this.errandService,
    this.catalogService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  // ==========================================
  // PARCOURS CLIENT : CRÉATION DE LISTE & CATALOGUE
  // ==========================================

  void _openCreateListDialog(String clientId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateErrandScreen(
          clientId: clientId,
          errandService: widget.errandService,
          catalogService:
              widget.catalogService ?? ProductCatalogService.instance,
          initialAddress: 'Cité 1000 Logts, Bât 12, Hydra, Alger',
        ),
      ),
    );
  }

  // ==========================================
  // PARCOURS SHOPPER : OFFRES & CONFIRMATION
  // ==========================================

  void _openPlaceBidDialog(ErrandModel errand, UserModel shopper) {
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
            onPressed: () async {
              final comm = double.tryParse(commissionCtrl.text.trim()) ?? 350.0;
              final bid = ErrandBidModel(
                bidId: '',
                shopperId: shopper.uid,
                shopperName: shopper.fullName,
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
                  color: AppTheme.violetAccent.withValues(alpha: 0.3),
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
                    phone != null && phone.isNotEmpty
                        ? 'Numéro : $phone'
                        : 'Numéro de téléphone non renseigné sur le profil.',
                    style: TextStyle(
                      fontSize: 13,
                      color: phone != null && phone.isNotEmpty
                          ? AppTheme.textDark
                          : AppTheme.errorRed,
                    ),
                  ),
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
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
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
                                      errand.shopperPhone,
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

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.flash_on,
                    color: AppTheme.primaryOrange,
                    size: 20,
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
          ),
          body: userModel.isShopper
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
                label: userModel.isShopper ? 'Radar Shopper' : 'Accueil Client',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profil',
              ),
            ],
          ),
          floatingActionButton: !userModel.isShopper
              ? FloatingActionButton.extended(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  onPressed: () => _openCreateListDialog(userModel.uid),
                  icon: const Icon(Icons.add),
                  label: const Text('Créer ma liste'),
                )
              : null,
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
          // Carte adresse de livraison bien visible
          Card(
            color: AppTheme.violetSurface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: AppTheme.violetAccent),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Adresse de livraison active',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.violetAccent,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Cité 1000 Logts, Bât 12, Hydra, Alger',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text(
                      'Modifier',
                      style: TextStyle(color: AppTheme.violetAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bouton principal « Créer ma liste » conservé
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () => _openCreateListDialog(user.uid),
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
                                      backgroundColor: AppTheme.primaryOrange,
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
                  widget.userService.setOnlineStatus(shopper.uid, val);
                },
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
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
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
                                      'Trésorerie à avancer : ${errand.treasuryRequired.toStringAsFixed(0)} DA',
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
                                Text(
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
