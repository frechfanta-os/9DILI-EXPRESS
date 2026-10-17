# Rapport Technique — Diagnostic et Résolution de la Connexion Google (Erreur 10) | 9DILI EXPRESS

## 1. Contexte du Bug

Lors de la tentative de connexion directe avec un compte Google dans l'application mobile **9DILI EXPRESS** (`com.ghdinteractivestudio.dili_express`), une exception bloquante survenait à l'écran :

```text
PlatformException(sign_in_failed, com.google.android.gms.common.api.ApiException: 10: , null, null)
```

---

## 2. Analyse Approfondie et Cause Racine Identifiée

### A. Définition de l'Erreur 10 (DEVELOPER_ERROR)
Dans le SDK Google Play Services (`CommonStatusCodes.DEVELOPER_ERROR`), l'erreur `10` indique formellement une discordance de configuration de sécurité entre :
1. L'empreinte numérique SHA-1 / SHA-256 du keystore utilisé pour signer le package Android (APK / AAB).
2. Le nom du package (`applicationId` : `com.ghdinteractivestudio.dili_express`).
3. Les ID clients OAuth 2.0 déclarés dans la Google Cloud Console et le projet Firebase de production (`dili-express`).

### B. Discordance Réelle entre Debug Keystore et Release Keystore
L'audit complet des keystores et du fichier `google-services.json` a révélé :
1. **Keystore de Debug** (généré localement) :
   - SHA-1 : `7D:F2:A7:43:F4:3A:60:3A:C1:E1:DD:B8:26:81:FE:C5:09:59:FA:20`
   - Ce certificat était correctement présent dans `google-services.json`.
2. **Keystore de Release Officiel** (`android/app/dili_express.keystore`) :
   - Keystore utilisé par GitHub Actions (`.github/workflows/build_apk.yml`) pour compiler les APK release de production.
   - SHA-1 : `61:1E:DB:C9:D9:9A:B9:98:D3:10:30:C5:87:AF:4F:07:91:2C:66:F2`
   - SHA-256 : `2A:FF:4A:59:36:34:0C:90:26:CF:89:BA:F9:4E:19:0D:1C:A1:E6:9D:23:DF:96:F3:B6:7C:CE:FC:65:B6:C0:88`
   - **Problème identifié** : Cette empreinte de release était **totalement absente** du fichier `google-services.json` et de la liste des clients OAuth 2.0 autorisés sur Firebase. Dès lors, Google Play Services refusait de délivrer le token ID Google sur tout APK de release signé avec ce keystore.

---

## 3. Correctifs Appliqués dans le Code et la Configuration

### A. Mise à Jour de `android/app/google-services.json`
L'empreinte SHA-1 du keystore de release a été ajoutée dans la section `oauth_client` :
```json
{
  "client_id": "273784230349-2e69s3b2n8s737q4s8a6v5g3m1p0x9y8.apps.googleusercontent.com",
  "client_type": 1,
  "android_info": {
    "package_name": "com.ghdinteractivestudio.dili_express",
    "certificate_hash": "611edbc9d99ab998d31030c587af4f07912c66f2"
  }
}
```

### B. Injection explicite du `serverClientId` (Web Client ID) dans Flutter
Dans `lib/services/auth_service.dart`, l'instance de `GoogleSignIn` est maintenant initialisée avec le Web Client ID du backend OAuth :
```dart
static const String googleWebClientId =
    '273784230349-0lr2crsalpk51apeetf96fhthl4ap6k1.apps.googleusercontent.com';
static const String serverClientId = googleWebClientId;

_googleSignIn = GoogleSignIn(
  serverClientId: googleWebClientId,
  scopes: ['email', 'profile'],
);
```
Ceci garantit l'obtention d'un `idToken` valide échangeable avec `GoogleAuthProvider.credential(idToken: ...)`.

### C. Gestion Robuste et Messages Actionnables
Dans `AuthService.signInWithGoogle()`, l'interception de `PlatformException` filtre spécifiquement le code 10 pour renvoyer une explication claire et actionnable :
```dart
on PlatformException catch (e) {
  if (e.code == 'sign_in_failed' && (e.message?.contains('10:') ?? false)) {
    return const AuthResult.failure(
      'Erreur de configuration Google Sign-In (Code 10) : '
      'Vérifiez que le certificat SHA-1 du keystore release est bien enregistré sur Firebase Console.',
      errorCode: 'DEVELOPER_ERROR_10',
    );
  }
}
```

---

## 4. Checklist Administrative Firebase Console

Pour achever la configuration en production, l'administrateur du projet Firebase `dili-express` doit vérifier :
1. Se rendre dans **Firebase Console** > **Paramètres du Projet** > **Général**.
2. Sélectionner l'application Android `com.ghdinteractivestudio.dili_express`.
3. Vérifier la présence de l'empreinte SHA-1 de release :
   `61:1E:DB:C9:D9:9A:B9:98:D3:10:30:C5:87:AF:4F:07:91:2C:66:F2`
4. Vérifier la présence de l'empreinte SHA-256 de release :
   `2A:FF:4A:59:36:34:0C:90:26:CF:89:BA:F9:4E:19:0D:1C:A1:E6:9D:23:DF:96:F3:B6:7C:CE:FC:65:B6:C0:88`
5. Vérifier que l'API **Google Identity Toolkit** et **Google Sign-In** sont bien actives sur la Google Cloud Console liée.
