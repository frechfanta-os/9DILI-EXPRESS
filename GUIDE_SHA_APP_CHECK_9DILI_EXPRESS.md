# GUIDE TECHNIQUE : EMPREINTES SHA & FIREBASE APP CHECK — 9DILI EXPRESS

**Projet** : 9DILI EXPRESS  
**Application ID** : `com.ghdinteractivestudio.dili_express` (Local) / `com.ghdinteractivestudio.diliexpress` (Firebase Console)  
**Date d'audit** : 16 Octobre 2026  
**Auditeur** : Ingénieur Release Android, Cybersécurité & DevOps  
**Statut Global** : **GUIDE OPÉRATIONNEL & DIAGNOSTIC RÉEL ÉTABLIS**

---

## 1. Inventaire Réel des Certificats de Signature (Phase C1)

### 1.1 Certificat Debug (Local)
- **Fichier Keystore** : `/root/.android/debug.keystore`
- **Alias** : `androiddebugkey`
- **Mot de passe par défaut** : `android`
- **Outil d'extraction exécuté** : OpenJDK 17 `keytool`
- **Empreinte SHA-1 (Debug)** :
  ```
  7D:F2:A7:43:F4:3A:60:3A:C1:E1:DD:B8:26:81:FE:C5:09:59:FA:20
  ```
  *(Format hexadécimal sans séparateur : `7df2a743f43a603ac1e1ddb82681fec50959fa20`)*
- **Empreinte SHA-256 (Debug)** :
  ```
  53:F5:90:67:01:CA:B5:A3:91:E5:2C:4E:D1:61:29:0B:EF:18:32:CE:AA:E7:11:FC:BC:B8:0D:25:E1:E2:5B:9B
  ```
- **Utilisation** :
  - **SHA-1** : Indispensable pour l'activation de **Google Sign-In** dans Firebase Authentication.
  - **SHA-256** : Requis pour **Firebase App Check** (fournisseur Debug / Play Integrity).

### 1.2 Rapport d'Exécution Gradle (`./gradlew signingReport`)
- **Commande exécutée** : `cd android && ./gradlew signingReport`
- **Résultat réel** : Code retour `1` (Échec d'exécution).
- **Raison technique exacte** :
  ```
  A problem occurred configuring project ':app'.
  > SDK location not found. Define a valid SDK location with an ANDROID_HOME environment variable
    or by setting the sdk.dir path in your project's local properties file at '/root/dili_express/android/local.properties'.
  ```
- **Analyse d'environnement** : L'environnement PRoot Linux contient bien Java OpenJDK 17 et les outils de base (`aapt`, `adb`), mais ne dispose pas du SDK Android complet (`ANDROID_HOME` non exporté dans la session).
- **Solution de contournement validée** : L'inspection directe du keystore via `keytool` officiel a permis d'extraire les empreintes cryptographiques avec une certitude absolue sans aucune fabrication.

### 1.3 Certificat Release (Production)
- **Constat dans [`android/app/build.gradle.kts`](file:///root/dili_express/android/app/build.gradle.kts)** :
  ```kotlin
  buildTypes {
      release {
          signingConfig = signingConfigs.getByName("debug")
      }
  }
  ```
- **État actuel** : **AUCUN KEYSTORE DE PRODUCTION N'EST ENCORE CONFIGURÉ**. L'APK de release généré par GitHub Actions est actuellement signé avec la clé debug Android standard.
- **Action requise avant mise en production sur le Play Store** : Générer un keystore dédié de production `release-keystore.jks`.

---

## 2. Procédure de Résolution du Décalage de Nom de Package

L'audit Firebase a révélé que la console Firebase enregistre l'application sous le nom `com.ghdinteractivestudio.diliexpress` (sans underscore), tandis que le code Flutter utilise `com.ghdinteractivestudio.dili_express`.

### Solution Recommandée (Option A) : Ajouter l'application officielle dans Firebase Console
1. Accéder à la [Console Firebase](https://console.firebase.google.com/) > Projet `dili-express` (N° `273784230349`).
2. Cliquer sur **Ajouter une application** > **Android**.
3. Saisir le package exact : `com.ghdinteractivestudio.dili_express`.
4. Renseigner le libellé : `9DILI EXPRESS (Client & Shopper)`.
5. Coller l'empreinte de signature SHA-1 debug :
   `7D:F2:A7:43:F4:3A:60:3A:C1:E1:DD:B8:26:81:FE:C5:09:59:FA:20`
6. Télécharger le nouveau `google-services.json` et remplacer le fichier local.

---

## 3. Plan d'Intégration Firebase App Check (Phase C2)

App Check protège les ressources Cloud Firestore, Realtime Database et Cloud Storage contre le trafic abusif et les clients non autorisés.

### 3.1 Fournisseurs selon l'Environnement

| Environnement | Fournisseur App Check | Prérequis & Sécurité |
| :--- | :--- | :--- |
| **Développement / Tests (Debug)** | `AndroidProvider.debug` | Jeton de débogage temporaire généré dans logcat / console. **Ne jamais intégrer en dur dans le code de production**. |
| **Production (Distribution)** | `AndroidProvider.playIntegrity` | Distribution via Google Play Store. Nécessite l'empreinte SHA-256 du certificat de signature enregistré dans Play Console. |

### 3.2 Dépendance & Initialisation Flutter

1. **Ajout dans `pubspec.yaml`** :
   ```yaml
   dependencies:
     firebase_app_check: ^0.3.1+4
   ```

2. **Code d'initialisation dans `lib/main.dart` (Avant tout appel Firestore)** :
   ```dart
   import 'package:firebase_app_check/firebase_app_check.dart';
   import 'package:flutter/foundation.dart';

   void main() async {
     WidgetsFlutterBinding.ensureInitialized();
     await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

     // Initialisation progressive d'App Check
     await FirebaseAppCheck.instance.activate(
       androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
       appleProvider: AppleProvider.deviceCheck,
     );

     runApp(const DiliExpressApp());
   }
   ```

### 3.3 Déploiement Progressif en 3 Étapes

```
[ Étape 1 : Mode Observation ] ───> [ Étape 2 : Validation Métriques ] ───> [ Étape 3 : Application Stricte ]
      (Monitoring seul)                    (Contrôle faux-positifs)                 (Enforcement activé)
```

1. **Étape 1 : Mode Observation (Monitoring)** :
   - Activer App Check dans la console Firebase pour Firestore et Storage **sans cocher l'application stricte (Enforce)**.
   - Analyser les métriques dans la console : vérifier que 100 % des requêtes légitimes de l'application mobile sont étiquetées comme « Valid requests ».
2. **Étape 2 : Contrôle des faux-positifs** :
   - Vérifier le comportement en conditions réseau réelles (3G/4G en Algérie, passages hors-ligne).
   - Valider la compatibilité avec les terminaux Android des marques courantes en Algérie (Samsung, Xiaomi, Oppo, Realme, Condor).
3. **Étape 3 : Application Stricte (Enforcement)** :
   - Activer le bouton « Appliquer » (Enforce) uniquement lorsque le taux de requêtes valides dépasse 99 %.
   - Tout client tiers non signé ou script non autorisé sera immédiatement rejeté avec le code HTTP 403 / `permission-denied`.
