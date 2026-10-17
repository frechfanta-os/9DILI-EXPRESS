import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../services/user_mode_service.dart';
import '../theme/app_theme.dart';

/// Écran de profil utilisateur 9DILI EXPRESS (Stitch UI/UX V2).
/// Permet la consultation et la mise à jour des informations personnelles.
/// Le numéro de téléphone n'est JAMAIS obligatoire lors de la mise à jour.
class ProfileScreen extends StatefulWidget {
  final AuthService authService;
  final UserService userService;

  const ProfileScreen({
    super.key,
    required this.authService,
    required this.userService,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _cashController;

  bool _isSaving = false;
  String? _feedbackMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    final user = widget.authService.currentUser;
    _nameController = TextEditingController(text: user?.displayName ?? '');
    _phoneController = TextEditingController();
    _cashController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cashController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile(UserModel currentUserModel) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _feedbackMessage = null;
    });

    final newName = _nameController.text.trim();
    final newPhone = _phoneController.text.trim();
    final cashParsed = double.tryParse(_cashController.text.trim());

    // 1. Mise à jour auth & user
    final authResult = await widget.authService.updateProfile(
      fullName: newName,
      phone: newPhone.isNotEmpty ? newPhone : null, // Optionnel
    );

    String? cashError;
    // 2. Mise à jour trésorerie (disponible pour tous les profils activant la livraison)
    if (cashParsed != null) {
      if (cashParsed < 0) {
        setState(() {
          _isSaving = false;
          _isError = true;
          _feedbackMessage =
              'Le montant de trésorerie ne peut pas être négatif.';
        });
        return;
      }
      try {
        await widget.userService.setAvailableCash(
          currentUserModel.uid,
          cashParsed,
        );
      } catch (e) {
        cashError = 'Erreur lors de la sauvegarde de la trésorerie : $e';
      }
    }

    if (mounted) {
      final isSuccess = authResult.isSuccess && cashError == null;
      setState(() {
        _isSaving = false;
        _isError = !isSuccess;
        _feedbackMessage = isSuccess
            ? 'Profil et trésorerie enregistrés avec succès !'
            : (cashError ??
                  authResult.errorMessage ??
                  'Erreur lors de la mise à jour.');
      });
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Déconnexion'),
        content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.authService.signOut();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = widget.authService.currentUser;
    if (authUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mon Profil')),
        body: const Center(child: Text('Aucun utilisateur connecté')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Profil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.errorRed),
            tooltip: 'Se déconnecter',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: StreamBuilder<UserModel?>(
        stream: widget.userService.streamUser(authUser.uid),
        builder: (context, snapshot) {
          final userModel =
              snapshot.data ??
              UserModel(
                uid: authUser.uid,
                fullName: authUser.displayName ?? 'Utilisateur',
                email: authUser.email,
              );

          // Initialisation paresseuse des champs
          if (_phoneController.text.isEmpty && userModel.phone != null) {
            _phoneController.text = userModel.phone!;
          }
          if (_cashController.text.isEmpty && userModel.availableCash > 0) {
            _cashController.text = userModel.availableCash.toStringAsFixed(2);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Carte Identité
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: AppTheme.primaryOrange.withValues(
                              alpha: 0.15,
                            ),
                            child: Text(
                              (userModel.fullName.isNotEmpty
                                      ? userModel.fullName[0]
                                      : 'U')
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryOrange,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            userModel.fullName.isNotEmpty
                                ? userModel.fullName
                                : 'Nom non renseigné',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userModel.email ?? authUser.email ?? '',
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryFor(
                                UserModeService.instance.currentMode,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              UserModeService.instance.isShopper
                                  ? '🚴 Mode Shoppeur'
                                  : '🛒 Mode Client',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryFor(
                                  UserModeService.instance.currentMode,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Message feedback
                  if (_feedbackMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isError
                            ? AppTheme.errorRed.withValues(alpha: 0.1)
                            : AppTheme.accentGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _feedbackMessage!,
                        style: TextStyle(
                          color: _isError
                              ? AppTheme.errorRed
                              : AppTheme.accentGreen,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Paramètres de livraison Shoppeur (Statut En ligne / Trésorerie / Véhicule)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Paramètres de livraison (Shoppeur)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (!userModel.hasValidPhone)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.shopperOrange.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Téléphone requis',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.shopperOrange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Divider(height: 20),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Disponible pour livrer'),
                            subtitle: Text(
                              userModel.isOnline
                                  ? 'En ligne (Radar actif)'
                                  : 'Hors ligne',
                              style: TextStyle(
                                color: userModel.isOnline
                                    ? AppTheme.accentGreen
                                    : AppTheme.textMuted,
                              ),
                            ),
                            value: userModel.isOnline,
                            activeThumbColor: AppTheme.accentGreen,
                            onChanged: (val) {
                              if (val && !userModel.hasValidPhone) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Veuillez renseigner un numéro de téléphone valide avant de passer en ligne.',
                                    ),
                                    backgroundColor: AppTheme.shopperOrange,
                                  ),
                                );
                                return;
                              }
                              widget.userService.setOnlineStatus(
                                userModel.uid,
                                val,
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _cashController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Trésorerie en poche (DA)',
                              hintText:
                                  'Montant disponible pour avancer les achats',
                              prefixIcon: Icon(
                                Icons.account_balance_wallet_outlined,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: userModel.transportType,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Moyen de déplacement',
                              prefixIcon: Icon(Icons.directions_bike),
                            ),
                            selectedItemBuilder: (BuildContext context) {
                              return const [
                                Text(
                                  '🚶 À pied',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '🚲 Vélo',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '🛴 Trottinette',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '🛵 Moto / Scooter',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '🚗 Voiture',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ];
                            },
                            items: const [
                              DropdownMenuItem(
                                value: 'walking',
                                child: Text(
                                  '🚶 À pied (Max 1.5 km - 5 kg)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'bicycle',
                                child: Text(
                                  '🚲 Vélo (Max 3.5 km - 10 kg)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'scooter',
                                child: Text(
                                  '🛴 Trottinette (Max 3 km - 8 kg)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'motorcycle',
                                child: Text(
                                  '🛵 Moto / Scooter (Max 10 km - 20 kg)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'car',
                                child: Text(
                                  '🚗 Voiture (Max 25 km - 80+ kg)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                widget.userService.updateTransportSettings(
                                  userModel.uid,
                                  transportType: val,
                                  searchRadiusKm: userModel.searchRadiusKm,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Édition des informations
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Informations personnelles',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Divider(height: 20),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nom complet *',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requis'
                                : null,
                          ),
                          const SizedBox(height: 14),

                          // Téléphone obligatoire pour commander et livrer
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Numéro de téléphone *',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Le numéro de téléphone est obligatoire.';
                              }
                              if (!UserModel.isValidPhone(v.trim())) {
                                return 'Veuillez saisir un numéro valide (au moins 9 chiffres).';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Bouton d'enregistrement
                  ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () => _updateProfile(userModel),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Enregistrer les modifications'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
