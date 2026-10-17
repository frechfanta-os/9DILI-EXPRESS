# RAPPORT TECHNIQUE & FONCTIONNEL — PRODUITS PERSONNALISÉS PAR PHOTO OU SAISIE LIBRE
**Application :** 9DILI EXPRESS  
**Package Android :** `com.ghdinteractivestudio.dili_express`  
**Environnement :** Flutter 3.29.3 / Dart 3.7.1, Android 16, Ubuntu PRoot, ImagePicker  
**Date :** 17 Octobre 2026  
**Auteur :** Antigravity Senior Engineering  

---

## 1. Objectif & Cadre Fonctionnel

Dans le commerce de proximité et la livraison de courses en Algérie, de nombreux produits spécifiques (pains artisanaux, herbes fraîches, pâtisseries traditionnelles, épices au poids, pièces spécifiques de boucherie ou marques très locales) ne figurent pas systématiquement dans un catalogue pré-établi.

Ce module permet au Client d'ajouter librement n'importe quel produit à sa course selon deux modes complémentaires :
1. **Ajout par photographie directe ou galerie** (`📷 Photographier un produit`).
2. **Ajout par saisie manuelle libre** (`+ Produit personnalisé`).

Ces articles sont intégrés au panier au même titre que les produits catalogués, puis transmis au Shoppeur avec tous les détails visuels et descriptifs nécessaires pour effectuer l'achat sans ambiguïté.

---

## 2. Choix d'Architecture & Décisions Techniques

### 2.1. Évolution du Modèle de Données (`ErrandItemModel`)
- **Fichier :** `lib/models/errand_item_model.dart`
- Le modèle a été étendu de manière rétro-compatible avec les attributs suivants :
  - `isCustom` (`bool`, défaut `false`) : identifie formellement si l'article provient d'une saisie libre / photo.
  - `photoUrl` (`String?`) : chemin du fichier local capturé ou URL distante de l'image.
  - `brand` (`String?`) : marque spécifiée par le client ou détails d'achat (ex: "boulangerie du coin", "artisanat").
  - `estimatedPrice` (`double?`) : budget unitaire estimé en Dinars Algériens (DZD).
- Méthodes `toMap()`, `fromMap()`, `copyWith()` et `toString()` mises à jour avec protection contre les valeurs nulles.

### 2.2. Prise de Vue & Sélection Galerie (`image_picker`)
- **Sources prises en charge :** Caméra (`ImageSource.camera`) et Galerie (`ImageSource.gallery`).
- **Optimisation et compression des images :**
  - Résolution maximale contrainte à `maxWidth: 1024`, `maxHeight: 1024`.
  - Compression JPEG fixée à `imageQuality: 80` pour préserver la netteté tout en minimisant la consommation mémoire et bande passante mobile.
  - Contrôle strict de la taille du fichier : refus immédiat si le fichier dépasse 5 Mo.
- **Transparence algorithmique (Zéro faux semblant IA) :**
  - Aucune fausse reconnaissance d'image par « pseudo-IA » n'a été ajoutée.
  - Une bannière explicative indique clairement au client : *« Votre photo servira de référence visuelle directe au shoppeur pour trouver exactement le bon produit en magasin. »*
  - Le client garde la main complète pour renseigner le libellé, la quantité, l'unité de mesure, la marque et son estimation de prix.

---

## 3. Parcours Utilisateur & Expérience Graphique

### 3.1. Boutons d'Action Rapide Côté Client (`CreateErrandScreen`)
- **Points d'accès :**
  1. En haut de l'écran, dans l'AppBar (`Actions`) : icônes caméra et ajout rapide.
  2. Sous la barre de recherche fixe, une barre d'actions mise en avant avec deux boutons :
     - `📷 Photographier` (fond vert clair, icône appareil photo).
     - `+ Produit personnalisé` (fond ambré clair, icône plus).
- **Formulaire de saisie modale (`_openPhotoProductFormDialog` & `_openAddCustomItemDialog`) :**
  - Prévisualisation instantanée de la photo avec possibilité de la modifier ou de la supprimer.
  - Champs obligatoires : Libellé du produit, Quantité (avec boutons `+` / `-`).
  - Champs optionnels : Unité (`pièce`, `kg`, `litre`, `paquet`, `boîte`), Marque / Précisions d'achat, Budget estimé par unité (DZD).
  - Validation interactive avec gestion des erreurs de saisie.

### 3.2. Intégration Unifiée dans le Panier
- Le compteur global d'articles (`_totalCartCount`) agrège fidèlement les quantités des produits catalogués et des articles personnalisés.
- Le budget global estimé (`_estimatedCartBudget`) intègre automatiquement les prix unitaires estimés des articles sur mesure.
- Dans le récapitulatif du panier :
  - Badge discret `Sur mesure ✍️`.
  - Miniature de la photo (si renseignée).
  - Possibilité de modifier la quantité ou de supprimer l'article en un clic.

### 3.3. Affichage Côté Shoppeur (`ShoppingModeScreen`)
- Durant la phase de course par le shoppeur :
  - Chaque article sur mesure arbore une pastille bien visible : `Produit personnalisé ✍️`.
  - Affichage de la marque / détails saisis (`Marque : ...`).
  - Affichage d'une vignette photo haute visibilité.
  - **Visionneuse d'image plein écran interactive (`_showImageDialog`) :**
    - Un simple tap sur la vignette ouvre une boîte de dialogue avec zoom tactile (`InteractiveViewer`).
    - Prise en charge transparente des URLs distantes (HTTP/HTTPS) et des chemins de fichiers locaux (`File`), avec image de secours en cas d'indisponibilité.

---

## 4. Tests Automatisés & Validation

La suite de tests unitaires et widget dans `test/catalog_cart_and_custom_products_test.dart` valide spécifiquement :

1. **Ajout d'un produit personnalisé par saisie manuelle :**
   - Renseignement du nom "Pain traditionnel Khobz Eddar", quantité 2, unité "pièce", marque "Boulangerie locale".
   - Vérification de l'incrémentation du panier (2 articles) et de la présence de la ligne dans la commande.
2. **Suppression d'un article personnalisé depuis le panier modal :**
   - Retrait de l'article via l'icône de suppression.
   - Recalcul immédiat du panier redevenant vide (0 article).
3. **Affichage côté shoppeur (`ShoppingModeScreen`) :**
   - Vérification de la présence du badge `Produit personnalisé ✍️`, de la marque et de la visionneuse photo interactive.
4. **Vérification globale :**
   - `flutter test` : **109 / 109 tests validés (100% de réussite)**.
   - `flutter analyze` : **0 avertissement, 0 erreur de typage ou de lint**.

---

## 5. Synthèse des Fichiers Clés

| Fichier | Nature des Modifications |
|---|---|
| [`lib/models/errand_item_model.dart`](file:///root/dili_express/lib/models/errand_item_model.dart) | Enrichissement des propriétés `isCustom`, `photoUrl`, `brand`, `estimatedPrice` et sérialisation JSON Firestore. |
| [`lib/ui/screens/create_errand_screen.dart`](file:///root/dili_express/lib/ui/screens/create_errand_screen.dart) | Sélecteur caméra/galerie, compression d'image, dialogues de formulaire sur mesure, intégration panier. |
| [`lib/ui/screens/shopping_mode_screen.dart`](file:///root/dili_express/lib/ui/screens/shopping_mode_screen.dart) | Badge visuel `Produit personnalisé ✍️`, affichage des détails/marques et visionneuse photo zoomable. |
| [`test/catalog_cart_and_custom_products_test.dart`](file:///root/dili_express/test/catalog_cart_and_custom_products_test.dart) | Tests de non-régression et de parcours complets pour les articles libres et photos. |
