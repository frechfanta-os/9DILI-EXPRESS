import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import '../theme/app_theme.dart';

/// Écran d'authentification 9DILI EXPRESS (Stitch UI/UX V2).
/// Intègre :
/// 1. Connexion / Inscription par Email & Mot de passe
/// 2. Connexion 1-clic avec Google Sign-In
/// 3. Récupération de compte (Mot de passe oublié)
/// 4. Aucune obligation de numéro de téléphone (champ optionnel et sans SMS)
class AuthScreen extends StatefulWidget {
  final AuthService authService;

  const AuthScreen({super.key, required this.authService});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    AuthResult result;
    if (_isLogin) {
      result = await widget.authService.signInWithEmail(
        email: email,
        password: password,
      );
    } else {
      result = await widget.authService.signUpWithEmail(
        email: email,
        password: password,
        fullName: _fullNameController.text.trim(),
        role: 'client',
        phone: _phoneController.text.trim(),
      );
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (!result.isSuccess) {
          _errorMessage = result.errorMessage;
        }
      });
    }
  }

  Future<void> _submitGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final result = await widget.authService.signInWithGoogle(
      defaultRole: 'client',
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (!result.isSuccess) {
          _errorMessage = result.errorMessage;
        }
      });
    }
  }

  void _showForgotPasswordDialog() {
    final resetEmailCtrl = TextEditingController(text: _emailController.text);
    bool isResetting = false;
    String? resetError;
    String? resetSuccess;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Récupération de compte'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Entrez votre adresse email pour recevoir un lien de réinitialisation sécurisé.',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 14),
              if (resetError != null) ...[
                Text(
                  resetError!,
                  style: const TextStyle(
                    color: AppTheme.errorRed,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (resetSuccess != null) ...[
                Text(
                  resetSuccess!,
                  style: const TextStyle(
                    color: AppTheme.accentGreen,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: resetEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Adresse Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Fermer'),
            ),
            ElevatedButton(
              onPressed: isResetting
                  ? null
                  : () async {
                      setDialogState(() {
                        isResetting = true;
                        resetError = null;
                        resetSuccess = null;
                      });
                      final res = await widget.authService
                          .sendPasswordResetEmail(resetEmailCtrl.text.trim());
                      setDialogState(() {
                        isResetting = false;
                        if (res.isSuccess) {
                          resetSuccess =
                              'Email de réinitialisation envoyé avec succès !';
                        } else {
                          resetError = res.errorMessage;
                        }
                      });
                    },
              child: isResetting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Envoyer le lien'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo / Header officiel 9DILI EXPRESS
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/branding/9dili/9dili_icon_master.png',
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryOrange.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.delivery_dining,
                                  size: 48,
                                  color: AppTheme.primaryOrange,
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '9DILI EXPRESS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isLogin
                        ? 'Connectez-vous pour accéder à vos courses'
                        : 'Créez votre compte en quelques secondes',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Message d'erreur
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.errorRed.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppTheme.errorRed,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppTheme.errorRed,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Message de succès
                  if (_successMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.accentGreen.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: AppTheme.accentGreen,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: const TextStyle(
                                color: AppTheme.accentGreen,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Bouton Google Sign-In rapide
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _submitGoogleSignIn,
                    icon: const Icon(
                      Icons.account_circle,
                      color: AppTheme.primaryOrange,
                      size: 22,
                    ),
                    label: const Text('Continuer avec Google'),
                  ),
                  const SizedBox(height: 20),

                  // Séparateur
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OU AVEC EMAIL',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Formulaire Email/Password
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_isLogin) ...[
                          // Nom complet
                          TextFormField(
                            controller: _fullNameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Nom complet *',
                              hintText: 'Nom et prénom',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Veuillez saisir votre nom complet';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Champ Numéro de téléphone (OBLIGATOIRE, sans observation)
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Numéro de téléphone *',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Veuillez saisir votre numéro de téléphone';
                              }
                              if (!UserModel.isValidPhone(val.trim())) {
                                return 'Numéro de téléphone invalide (au moins 9 chiffres)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Email
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Adresse Email *',
                            hintText: 'exemple@domaine.com',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Veuillez saisir votre adresse email';
                            }
                            if (!val.contains('@') || !val.contains('.')) {
                              return 'Format d\'email non valide';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Mot de passe
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Mot de passe *',
                            hintText: 'Minimum 6 caractères',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) {
                              return 'Veuillez saisir votre mot de passe';
                            }
                            if (val.length < 6) {
                              return 'Au moins 6 caractères requis';
                            }
                            return null;
                          },
                        ),

                        // Mot de passe oublié (en mode connexion)
                        if (_isLogin) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _showForgotPasswordDialog,
                              child: const Text(
                                'Mot de passe oublié ?',
                                style: TextStyle(
                                  color: AppTheme.primaryOrange,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ] else
                          const SizedBox(height: 20),

                        // Bouton principal d'action
                        ElevatedButton(
                          onPressed: _isLoading ? null : _submitEmailAuth,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isLogin
                                      ? 'Se connecter'
                                      : 'Créer mon compte',
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bascule Connexion / Inscription
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            setState(() {
                              _isLogin = !_isLogin;
                              _errorMessage = null;
                              _successMessage = null;
                            });
                          },
                    child: Text(
                      _isLogin
                          ? 'Pas encore de compte ? S\'inscrire'
                          : 'Vous avez déjà un compte ? Se connecter',
                      style: const TextStyle(
                        color: AppTheme.primaryOrange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
