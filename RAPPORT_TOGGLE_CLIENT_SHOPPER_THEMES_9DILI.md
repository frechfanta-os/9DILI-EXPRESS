# RAPPORT TECHNIQUE & FONCTIONNEL — TOGGLE CLIENT / SHOPPER & THÈMES DYNAMIQUES
**Application :** 9DILI EXPRESS  
**Package Android :** `com.ghdinteractivestudio.dili_express`  
**Environnement :** Flutter 3.29.3 / Dart 3.7.1, Android 16, Ubuntu PRoot, Firebase Firestore, SharedPreferences  
**Date :** 17 Octobre 2026  
**Auteur :** Antigravity Senior Engineering  

---

## 1. Objectif & Vue d'Ensemble

L'objectif de cette mission consistait à fiabiliser et corriger le sélecteur (Toggle) **Client / Shopper** et le système de thèmes partagé dans l'application **9DILI EXPRESS** :

1. **Compte et inscription uniques :** Un seul compte utilisateur Firebase Auth (`uid`) et un profil Firestore unique (`/users/{uid}`). Le changement de mode n'engendre aucune nouvelle inscription, aucune duplication de données, aucune déconnexion et aucune perte de données (téléphone, solde trésorerie, note, courses en cours).
2. **Sélecteur Toggle haute fidélité :** Implémentation conforme au design officiel fourni (`Screenshot_2026-10-17-13-46-33-35.JPG`), ancré en haut de l'écran d'accueil (`HomeScreen`), animé de façon fluide (250 ms) avec retour haptique.
3. **Thème Client (Vert Émeraude `#10B981`) :** Activé en Mode Client, teinte les boutons principaux, les accents, les badges et la navigation sans dénaturer les couleurs sémantiques (alertes, erreurs, avertissements).
4. **Thème Shopper (Orange Vif `#FF6D00`) :** Activé en Mode Shopper, teinte les boutons d'action (offres, acceptation), les accents du radar et la navigation.
5. **Contrôle strict des prérequis Shopper :** Un utilisateur ne peut pas basculer en Mode Shopper sans satisfaire les critères d'éligibilité (profil avec nom complet, numéro de téléphone valide et vérifié, moyen de déplacement). En cas de prérequis manquants, une modale pédagogique détaille la procédure et oriente vers le profil.
6. **Persistance de la préférence :** La préférence de mode est sauvegardée localement dans `SharedPreferences` (`preferred_app_mode`) et restaurée fidèlement à chaque réouverture de l'application.

---

## 2. Architecture Technique & Implémentation

```mermaid
flowchart TD
    subgraph SingleAccount["Compte Unique & Authentification"]
        FirebaseAuth["Firebase Auth (uid unique)"]
        FirestoreUser["Firestore /users/{uid}"]
    end

    subgraph StateAndTheme["Gestion d'État & Thèmes"]
        UserModeService["UserModeService (Singleton + ValueNotifier)"]
        SharedPrefs["SharedPreferences ('preferred_app_mode')"]
        AppTheme["AppTheme (themeFor(mode))"]
        AppWidget["DiliExpressApp (MaterialApp dynamique)"]
    end

    subgraph UIComponents["Interface Utilisateur"]
        HomeScreen["HomeScreen"]
        Toggle["ClientShopperToggle (Top AppBar)"]
        ClientView["Vue Client (Vert #10B981 - Catalogue & Commandes)"]
        ShopperView["Vue Shopper (Orange #FF6D00 - Radar & Livraisons)"]
        PrereqModal["Modale Prérequis Shoppeur"]
    end

    FirebaseAuth --> FirestoreUser
    FirestoreUser --> HomeScreen
    SharedPrefs <--> UserModeService
    UserModeService --> AppTheme
    AppTheme --> AppWidget
    HomeScreen --> Toggle
    Toggle -->|Tap Client| UserModeService
    Toggle -->|Tap Shopper (Vérif prérequis)| UserModeService
    Toggle -.->|Prérequis manquants| PrereqModal
    UserModeService -->|Notifie Mode| HomeScreen
    HomeScreen -->|isClient| ClientView
    HomeScreen -->|isShopper| ShopperView
```

### 2.1. Service de Mode Utilisateur (`UserModeService`)
- **Fichier :** [`lib/services/user_mode_service.dart`](file:///root/dili_express/lib/services/user_mode_service.dart)
- **Rôle :** Coordonner le mode actif (`AppMode.client` vs `AppMode.shopper`), notifier l'arborescence des widgets via `ValueNotifier<AppMode>`, persister la préférence dans `SharedPreferences` et valider les prérequis d'accès au mode Shopper.
- **Méthodes clés :**
  - `init()` : Restaure la préférence sauvegardée ('client' ou 'shopper').
  - `setMode(AppMode mode)` : Met à jour le `modeNotifier` et écrit dans `SharedPreferences`.
  - `checkShopperPrerequisites(UserModel user)` : Analyse l'éligibilité selon 3 piliers :
    1. Nom complet non vide (`hasFullName`).
    2. Numéro de téléphone valide (`hasValidPhone`, format algérien ou international >= 9 chiffres).
    3. Moyen de transport configuré (`hasTransport`).

### 2.2. Système de Thèmes Dynamique (`AppTheme`)
- **Fichier :** [`lib/ui/theme/app_theme.dart`](file:///root/dili_express/lib/ui/theme/app_theme.dart)
- **Charte chromatique :**
  - `clientGreen` = `Color(0xFF10B981)` (Vert Émeraude officiel).
  - `shopperOrange` = `Color(0xFFFF6D00)` (Orange Vif officiel).
  - Couleurs sémantiques préservées : `errorRed` (`0xFFEF4444`), `warningOrange` (`0xFFF59E0B`).
- **Génération dynamique :**
  `AppTheme.themeFor(AppMode mode)` génère un `ThemeData` complet (Material 3, `colorScheme.primary`, `floatingActionButtonTheme`, `navigationBarTheme`, `elevatedButtonTheme`, `inputDecorationTheme`) aligné sur la couleur du mode actif.

### 2.3. Réactivité Globale de l'Application (`DiliExpressApp`)
- **Fichier :** [`lib/main.dart`](file:///root/dili_express/lib/main.dart)
- `MaterialApp` est enveloppé dans un `ValueListenableBuilder<AppMode>` écoutant `UserModeService.instance.modeNotifier`.
- Le basculement de thème et de navigation s'effectue instantanément, sans clignotement, sans écran blanc et sans déconnexion.

### 2.4. Sélecteur Haute Fidélité (`ClientShopperToggle`)
- **Fichier :** [`lib/ui/widgets/client_shopper_toggle.dart`](file:///root/dili_express/lib/ui/widgets/client_shopper_toggle.dart)
- **Fidélité au design :**
  - **Mode Client :**
    - Conteneur capsule arrondi (rayon 24 dp), fond vert `#10B981`.
    - Curseur blanc glissant positionné à gauche sur « Client ».
    - Pastille verte ronde `•` à côté du libellé gras vert `Client`.
    - Texte blanc épuré `Shopper` sur la droite.
  - **Mode Shopper :**
    - Conteneur capsule arrondi, fond orange `#FF6D00`.
    - Curseur blanc glissant positionné à droite sur « Shopper ».
    - Texte blanc épuré `Client` sur la gauche.
    - Pastille orange ronde `•` à côté du libellé gras orange `Shopper`.
  - **Animation tactile :** `AnimatedAlign` (250 ms, courbe `easeInOutCubic`) et retour haptique `HapticFeedback.lightImpact()`.

### 2.5. Intégration dans l'Accueil (`HomeScreen`)
- **Fichier :** [`lib/ui/screens/home_screen.dart`](file:///root/dili_express/lib/ui/screens/home_screen.dart)
- **Positionnement fixe :** Le sélecteur est inséré dans `appBar.bottom` sous forme de `PreferredSize` (hauteur 58 dp), garantissant une visibilité permanente au sommet de l'écran, au-dessus des flux de défilement.
- **Bascule de vue conditionnelle :**
  - `_currentMode == AppMode.client` affiche `_buildClientHomeView(userModel)` avec le bouton d'action flottant « Créer ma liste » et les commandes client.
  - `_currentMode == AppMode.shopper` affiche `_buildShopperRadarView(userModel)` avec le statut en ligne, la trésorerie en poche et le radar des courses.
- **Dialogue Pédagogique Prérequis :**
  Si un client clique sur « Shopper » alors que son numéro de téléphone ou son profil n'est pas complété, la feuille modale `_showShopperPrerequisitesModal` s'affiche avec la checklist des points à renseigner et un bouton direct *« Compléter mon profil ✍️ »* vers `ProfileScreen`.

---

## 3. Matrice de Validation des Exigences

| # | Exigence du Cahier des Charges | Solution Implémentée | Statut |
|---|---|---|:---:|
| 1 | **Inscription et compte uniques** | Un seul compte Firebase Auth et profil `/users/{uid}`, conservation intégrale de l'identité, du téléphone et de l'historique. | **CONFORME** |
| 2 | **Toggle Client / Shopper** | Ancré au sommet de l'écran d'accueil, deux états distincts, retour haptique et animation fluide conforme à la maquette. | **CONFORME** |
| 3 | **Thème Client — Vert `#10B981`** | Boutons principaux, navigation, pastilles et accents verts en mode Client, préservation des alertes sémantiques. | **CONFORME** |
| 4 | **Thème Shopper — Orange `#FF6D00`** | Boutons d'offre, radar et navigation oranges en mode Shopper sans mutation de trésorerie ni de commande. | **CONFORME** |
| 5 | **Architecture visuelle centralisée** | Système partagé dans `AppTheme.themeFor(mode)` consommé par `MaterialApp` et `Theme.of(context)`. | **CONFORME** |
| 6 | **Sécurité et données métier** | Mode d'interface strict : aucune règle Firebase ni autorisation backend contournée. Vérification téléphone et trésorerie. | **CONFORME** |
| 7 | **Blocage si prérequis non satisfaits** | Modale pédagogique avec checklist et bouton direct vers le profil en cas de téléphone manquant. | **CONFORME** |
| 8 | **Persistance au redémarrage** | Sauvegarde et restauration automatique de `preferred_app_mode` dans `SharedPreferences`. | **CONFORME** |
| 9 | **Zéro régression** | Catalogue, panier, annulation, radar et tracking 100% opérationnels. | **CONFORME** |

---

## 4. Résultats des Tests et Analyse Statique

### 4.1. Tests Spécifiques Toggle et Thèmes (`test/user_mode_toggle_and_themes_test.dart`)
14 tests unitaires et widget couvrant l'intégralité du cycle de vie :
- `1. Inscription Unique & Conservation du Compte et du Profil` : **PASS**
- `2. Système de Thèmes Partagé (Client Vert #10B981 / Shopper Orange #FF6D00)` : **PASS** (4 tests)
- `3. Persistance du Mode Préféré (SharedPreferences)` : **PASS** (3 tests)
- `4. Contrôle Strict des Prérequis Shopper` : **PASS** (3 tests)
- `5. Conservation des Commandes et Absence d'Effets de Bord` : **PASS**
- `6. Widget Test : ClientShopperToggle` (Rendu Client & Rendu Shopper) : **PASS** (2 tests)

### 4.2. Bilan Global du Projet
- **`flutter test` :** **123 / 123 tests réussis avec succès (100% de réussite)**.
- **`flutter analyze` :** **0 problème détecté (No issues found!)**.

---

## 5. Fichiers Modifiés et Créés

| Fichier | Nature de l'Intervention |
|---|---|
| [`lib/services/user_mode_service.dart`](file:///root/dili_express/lib/services/user_mode_service.dart) | **Nouveau service :** Gestion réactive du mode d'interface, persistance SharedPreferences et validation prérequis. |
| [`lib/ui/widgets/client_shopper_toggle.dart`](file:///root/dili_express/lib/ui/widgets/client_shopper_toggle.dart) | **Nouveau widget :** Sélecteur toggle animé fidèle à la capture d'écran fournie. |
| [`lib/ui/theme/app_theme.dart`](file:///root/dili_express/lib/ui/theme/app_theme.dart) | Intégration de l'enum `AppMode`, des palettes `clientGreen` et `shopperOrange`, et de la méthode `themeFor(mode)`. |
| [`lib/main.dart`](file:///root/dili_express/lib/main.dart) | Enveloppement de `MaterialApp` dans un `ValueListenableBuilder` sur le mode actif. |
| [`lib/ui/screens/home_screen.dart`](file:///root/dili_express/lib/ui/screens/home_screen.dart) | Intégration du toggle dans l'AppBar, écoute de `_currentMode`, modale prérequis et bascule dynamique des thèmes. |
| [`lib/ui/screens/profile_screen.dart`](file:///root/dili_express/lib/ui/screens/profile_screen.dart) | Badge de mode dynamique, accès universel aux paramètres de livraison (véhicule, trésorerie, téléphone). |
| [`test/user_mode_toggle_and_themes_test.dart`](file:///root/dili_express/test/user_mode_toggle_and_themes_test.dart) | Suite automatisée de 14 tests pour le toggle, la persistance, les thèmes et les prérequis. |
