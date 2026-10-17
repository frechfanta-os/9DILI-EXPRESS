import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';
import 'user_service.dart';

/// Résultat d'une opération d'authentification pour gérer facilement succès et erreurs.
class AuthResult {
  final bool isSuccess;
  final User? user;
  final String? errorMessage;
  final String? errorCode;

  const AuthResult.success(this.user)
    : isSuccess = true,
      errorMessage = null,
      errorCode = null;

  const AuthResult.failure(this.errorMessage, {this.errorCode})
    : isSuccess = false,
      user = null;
}

/// Service d'authentification 9DILI EXPRESS.
/// Règles absolues :
/// - Deux méthodes de connexion : Email/Mot de passe et Google Sign-In.
/// - Récupération de compte par réinitialisation de mot de passe.
/// - Le numéro de téléphone n'est JAMAIS obligatoire (inscription, connexion, profil).
/// - Aucune vérification SMS obligatoire.
class AuthService {
  static const String googleWebClientId =
      '273784230349-0lr2crsalpk51apeetf96fhthl4ap6k1.apps.googleusercontent.com';
  static const String serverClientId = googleWebClientId;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final UserService? userService;

  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    this.userService,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _googleSignIn =
           googleSignIn ??
           GoogleSignIn(
             serverClientId: googleWebClientId,
             scopes: ['email', 'profile'],
           );

  /// Utilisateur actuellement connecté.
  User? get currentUser => _auth.currentUser;

  /// Stream des changements d'état d'authentification.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Inscription avec Email et Mot de passe.
  /// Note : [phone] est strictement facultatif et ne doit jamais bloquer l'inscription.
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    String role = 'client',
    String? phone, // Strictement optionnel
  }) async {
    try {
      final trimmedEmail = email.trim();
      final trimmedPassword = password.trim();

      if (trimmedEmail.isEmpty) {
        return const AuthResult.failure(
          'Veuillez renseigner une adresse email valide.',
          errorCode: 'invalid-email',
        );
      }
      if (trimmedPassword.length < 6) {
        return const AuthResult.failure(
          'Le mot de passe doit comporter au moins 6 caractères.',
          errorCode: 'weak-password',
        );
      }
      if (fullName.trim().isEmpty) {
        return const AuthResult.failure(
          'Veuillez renseigner votre nom complet.',
          errorCode: 'empty-name',
        );
      }

      final credential = await _auth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: trimmedPassword,
      );

      final user = credential.user;
      if (user != null) {
        // Mettre à jour le displayName Firebase Auth
        await user.updateDisplayName(fullName.trim());

        // Synchroniser dans Firestore users si UserService disponible
        final uService = userService;
        if (uService != null) {
          final trimmedPhone = phone?.trim();
          final newUser = UserModel(
            uid: user.uid,
            fullName: fullName.trim(),
            email: trimmedEmail,
            phone: (trimmedPhone != null && trimmedPhone.isNotEmpty)
                ? trimmedPhone
                : null,
            role: role,
            isOnline: true,
            availableCash: 0.0,
            rating: 5.0,
          );
          await uService.saveUser(newUser);
        }
        return AuthResult.success(user);
      }
      return const AuthResult.failure(
        'Erreur lors de la création du compte.',
        errorCode: 'user-null',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapFirebaseError(e), errorCode: e.code);
    } catch (e) {
      return AuthResult.failure('Une erreur inattendue est survenue: $e');
    }
  }

  /// Connexion avec Email et Mot de passe.
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final trimmedEmail = email.trim();
      final trimmedPassword = password.trim();

      if (trimmedEmail.isEmpty) {
        return const AuthResult.failure(
          'Veuillez renseigner votre adresse email.',
          errorCode: 'empty-email',
        );
      }
      if (trimmedPassword.isEmpty) {
        return const AuthResult.failure(
          'Veuillez renseigner votre mot de passe.',
          errorCode: 'empty-password',
        );
      }

      final credential = await _auth.signInWithEmailAndPassword(
        email: trimmedEmail,
        password: trimmedPassword,
      );

      final user = credential.user;
      final uService = userService;
      if (user != null && uService != null) {
        await uService.setOnlineStatus(user.uid, true);
      }
      return AuthResult.success(user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapFirebaseError(e), errorCode: e.code);
    } catch (e) {
      return AuthResult.failure('Connexion impossible: $e');
    }
  }

  /// Connexion rapide avec Google Sign-In.
  /// Ne demande jamais de numéro de téléphone ni de SMS.
  Future<AuthResult> signInWithGoogle({String defaultRole = 'client'}) async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // L'utilisateur a annulé le flux Google
        return const AuthResult.failure(
          'Connexion Google annulée.',
          errorCode: 'google-cancelled',
        );
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      final user = userCredential.user;
      final uService = userService;
      if (user != null && uService != null) {
        // Vérifier si le profil existe déjà pour préserver les comptes et rôles
        final existing = await uService.getUser(user.uid);
        if (existing == null) {
          final newUser = UserModel(
            uid: user.uid,
            fullName:
                user.displayName ??
                googleUser.displayName ??
                'Utilisateur 9DILI',
            email: user.email ?? googleUser.email,
            phone: null, // Téléphone non obligatoire
            role: defaultRole,
            isOnline: true,
            availableCash: 0.0,
            rating: 5.0,
          );
          await uService.saveUser(newUser);
        } else {
          await uService.setOnlineStatus(user.uid, true);
        }
      }

      return AuthResult.success(user);
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_failed' &&
          (e.message?.contains('10') == true || e.toString().contains('10:'))) {
        return const AuthResult.failure(
          'Échec Google Sign-In (DEVELOPER_ERROR code 10) : L\'empreinte SHA-1 du certificat de signature de l\'APK doit être enregistrée dans la console Firebase (SHA-1: 61:1E:DB:C9:D9:9A:B9:98:D3:10:30:C5:87:AF:4F:07:91:2C:66:F2).',
          errorCode: 'developer-error-10',
        );
      }
      return AuthResult.failure(
        'Erreur de la plateforme Google Sign-In : ${e.message ?? e.code}',
        errorCode: e.code,
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapFirebaseError(e), errorCode: e.code);
    } catch (e) {
      return AuthResult.failure('Erreur Google Sign-In: $e');
    }
  }

  /// Récupération de compte : Envoi de l'email de réinitialisation du mot de passe.
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      return const AuthResult.failure(
        'Veuillez renseigner une adresse email valide.',
        errorCode: 'invalid-email',
      );
    }

    try {
      await _auth.sendPasswordResetEmail(email: trimmed);
      return const AuthResult.success(null);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapFirebaseError(e), errorCode: e.code);
    } catch (e) {
      return AuthResult.failure('Impossible d\'envoyer l\'email: $e');
    }
  }

  /// Déconnexion sécurisée.
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    final uService = userService;
    if (uid != null && uService != null) {
      try {
        await uService.setOnlineStatus(uid, false);
      } catch (_) {
        // En cas de perte de connexion, ignorer pour permettre le signOut local
      }
    }
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Mise à jour du profil utilisateur (nom et téléphone optionnel).
  /// Le téléphone n'est JAMAIS obligatoire.
  Future<AuthResult> updateProfile({
    String? fullName,
    String? phone, // Peut être null ou chaîne vide
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return const AuthResult.failure(
        'Aucun utilisateur connecté.',
        errorCode: 'unauthenticated',
      );
    }

    try {
      if (fullName != null && fullName.trim().isNotEmpty) {
        await user.updateDisplayName(fullName.trim());
      }

      final uService = userService;
      if (uService != null) {
        final existing = await uService.getUser(user.uid);
        if (existing != null) {
          final trimmedName = fullName?.trim();
          final trimmedPhone = phone?.trim();
          final updated = existing.copyWith(
            fullName: (trimmedName != null && trimmedName.isNotEmpty)
                ? trimmedName
                : existing.fullName,
            phone: phone != null
                ? ((trimmedPhone != null && trimmedPhone.isNotEmpty)
                      ? trimmedPhone
                      : null)
                : existing.phone,
          );
          await uService.saveUser(updated);
        }
      }
      return AuthResult.success(user);
    } catch (e) {
      return AuthResult.failure('Impossible de mettre à jour le profil: $e');
    }
  }

  /// Traduction conviviale des codes d'erreurs Firebase Auth.
  static String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Aucun compte associé à cette adresse email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Mot de passe ou identifiant incorrect.';
      case 'email-already-in-use':
        return 'Cette adresse email est déjà utilisée par un autre compte.';
      case 'invalid-email':
        return 'Format d\'adresse email invalide.';
      case 'weak-password':
        return 'Le mot de passe choisi est trop simple (minimum 6 caractères).';
      case 'user-disabled':
        return 'Ce compte a été suspendu.';
      case 'network-request-failed':
        return 'Erreur de connexion réseau. Veuillez vérifier votre connexion.';
      case 'operation-not-allowed':
        return 'Cette méthode de connexion n\'est pas activée sur Firebase Console.';
      default:
        return e.message ?? 'Une erreur d\'authentification est survenue.';
    }
  }
}
