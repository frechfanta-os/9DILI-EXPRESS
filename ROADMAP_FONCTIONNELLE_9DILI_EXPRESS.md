# ROADMAP PRODUIT & FONCTIONNELLE — 9DILI EXPRESS

**Projet** : 9DILI EXPRESS  
**Date d'audit & planification** : 16 Octobre 2026  
**Auditeur** : Lead Product Manager & Directeur Technique Mobile  
**Statut Global** : **PROPOSED — EN ATTENTE D'APPROBATION CLIENT**

---

## PARTIE 1 : MOYENS DE DÉPLACEMENT DES SHOPPERS (PHASE F)

Pour s'adapter à la réalité de la livraison de proximité en Algérie (densité urbaine d'Alger, Oran, Constantine, relief accidenté, embouteillages), le profil Shopper intègre 5 modes de déplacement configurables.

### 1.1 Matrice des 5 Modes de Déplacement

| Mode de Transport | Rayon Maximal Conseillé | Capacité d'Emport Indicative | Vitesse Moyenne Estimée | Types de Courses Compatibles | Contraintes Spécifiques en Algérie |
| :--- | :---: | :---: | :---: | :--- | :--- |
| **À pied** | **1,5 km** | Max 5 kg (1 à 2 sacs légers) | 4 à 5 km/h | Épicerie de quartier, pharmacie, pain, dépannage express. | Fatigue physique, inadapté aux reliefs escarpés (ex: El Biar, Telemly). |
| **Vélo** | **3,5 km** | Max 10 kg (Sac à dos coursier) | 12 à 15 km/h | Courses alimentaires moyennes, petits paquets. | Absence de pistes cyclables, pentes raides, circulation dense. |
| **Trottinette** | **3,0 km** | Max 8 kg (Sac à dos uniquement) | 15 à 18 km/h | Petits achats urbains, centre-ville plat. | État des trottoirs, autonomie batterie limitée, interdiction sur voies rapides. |
| **Moto / Scooter** | **10,0 km** | Max 20 kg (Top-case + sac) | 25 à 35 km/h | Courses complètes de supermarché, multi-sacs. | Port du casque obligatoire, intempéries hivernales. |
| **Voiture** | **25,0 km** | 60+ kg (Coffre complet) | 20 à 40 km/h *(selon bouchons)* | Packs d'eau (6x1.5L), sacs de semoule 25 kg, gros électroménager. | Stationnement difficile en centre-ville, coût du carburant. |

### 1.2 Filtre Automatique d'Incompatibilité
- Si le client commande des articles volumineux ou lourds (ex: plus de 2 packs d'eau ou sac de semoule de 10 kg), l'algorithme du radar **masque automatiquement la course aux livreurs à pied, à vélo ou à trottinette** pour éviter les abandons et litiges.

### 1.3 Barème Transparent des Frais & Commissions Conseillées
- L'application propose un curseur de commission indicatif au client lors de la création de la liste :
  - **Base forfaitaire de proximité** : 200 à 300 DZD (couvre la disponibilité du livreur).
  - **Majoration kilométrique indicative** : +50 DZD par kilomètre au-delà de 2 km.
  - **Majoration de charge lourde** : +100 DZD pour les paniers supérieurs à 15 kg.
- **Principe fondamental** : La commission finale reste **négociable de gré à gré** via le système d'offres (`/bids`).

---

## PARTIE 2 : ROADMAP FONCTIONNELLE PRIORISÉE (PHASE G)

### 2.1 Matrice Priorisée des 17 Fonctionnalités Majeures

| Priorité | Fonctionnalité | Valeur Utilisateur | Dépendances | Coûts | Risques | Complexité | Critères d'Acceptation |
| :---: | :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| **P0** | **Alignement Package & SHA-1 Google** | Connexion Google Sign-In fluide en 1 clic. | Firebase Console | Gratuit | Blocage total de l'authentification si non corrigé. | **S** | Connexion Google fonctionnelle sans exception `ApiException: 10`. |
| **P0** | **Durcissement Règles Firestore & PIN** | Sécurisation des données privées et du code de remise. | `firestore.rules` | Gratuit | Vol de données, usurpation de rôle administrateur. | **M** | Rôle et rating non modifiables par l'utilisateur ; PIN isolé dans `/secrets/pin`. |
| **P0** | **Initialisation Dépôt Git & Sync Remote** | Sauvegarde et versionnage pérenne du projet sur GitHub. | `git` / GitHub | Gratuit | Perte de code en cas de crash machine locale. | **S** | Dépôt distant `9DILI-EXPRESS` contenant la branche `main` à jour. |
| **P1** | **Cartographie Libre `flutter_map`** | Visualisation géographique de la position du Shopper et de la boutique. | `flutter_map`, OpenStreetMap | Faible (tuiles) | Quotas serveurs publics si trafic élevé. | **M** | Affichage fluide de la carte OSM avec User-Agent conforme et cache local. |
| **P1** | **Notifications Push (FCM)** | Alertes instantanées pour nouvelles offres et statuts de livraison. | `firebase_messaging` | Gratuit | Permissions Android 13+ refusées par l'utilisateur. | **M** | Réception de notifications au changement de statut d'une course. |
| **P1** | **Catalogue Produits Algériens V1** | Saisie ultra-rapide des articles courants avec prix indicatifs en DZD. | Firestore, Assets JSON | Gratuit | Inexactitude des prix indicatifs par rapport aux épiceries. | **L** | 11 catégories bilingues français/arabe navigables avec recherche tolérante. |
| **P1** | **Téléversement Réel Ticket (Firebase Storage)** | Justificatif d'achat officiel requis avant départ en livraison. | `firebase_storage` | Quotas Storage | Photos floues ou fichiers trop lourds (> 10 Mo). | **M** | Photo compressée (JPEG < 2 Mo) stockée dans `/receipts/{id}` avec URL publique sécurisée. |
| **P2** | **Modes de Déplacement Shopper** | Choix du véhicule (pied, vélo, moto, voiture) et filtrage des courses. | `UserModel`, UI Profil | Gratuit | Shopper acceptant une course inadaptée à son véhicule. | **S** | Sélecteur dans le profil et masquage des paniers lourds aux piétons/cyclistes. |
| **P2** | **Système d'Évaluations Immuables (Ratings)** | Confiance mutuelle et notation (1 à 5 étoiles) après livraison. | Collection `ratings` | Gratuit | Avis vengeurs ou abusifs. | **M** | Note unique par course terminée, recalcul de la moyenne automatique. |
| **P2** | **Historique Détaillé & Reçus Dématérialisés** | Suivi des dépenses personnelles et archivage comptable. | Requêtes Firestore | Gratuit | Consommation excessive de lectures Firestore. | **M** | Onglet dédié affichant les courses passées avec facture détaillée (Ticket + Commission). |
| **P2** | **Support Bilingue & RTL (Français / Arabe)** | Accessibilité complète pour le public arabophone en Algérie. | `flutter_localizations` | Gratuit | Inversions visuelles non harmonisées en RTL. | **L** | Bascule instantanée FR/AR dans les paramètres avec mise en page RTL native. |
| **P3** | **Gestion des Litiges & Signalements** | Médiation en cas de contestation de prix ou non-livraison. | Collection `disputes` | Modération | Surcharge du support client. | **L** | Formulaire de litige avec blocage temporaire du versement de commission. |
| **P3** | **Mode Hors-Ligne Avancé (Offline Queue)** | Finalisation des courses en sous-sol ou zone blanche sans 4G. | SQLite / SharedPreferences | Gratuit | Conflits de synchronisation à la reconnexion. | **L** | File d'attente locale synchronisant les statuts dès le retour du réseau. |
| **P3** | **Firebase App Check avec Play Integrity** | Protection de l'API Firebase contre les robots et clones d'APK. | `firebase_app_check` | Gratuit | Blocage involontaire d'appareils rootés ou anciens. | **M** | Activation en mode observation puis bascule en application stricte. |
| **P3** | **Observabilité & Crash Reporting (Sentry)** | Détection en temps réel des exceptions silencieuses et crashs. | `sentry_flutter` | Gratuit (Tier free) | Données sensibles (PII) envoyées dans les logs. | **M** | Filtrage strict des logs avec masquage des adresses et numéros de téléphone. |
| **P4** | **Reconnaissance OCR du Ticket de Caisse** | Extraction automatique du montant total payé sur le reçu papier. | Google ML Kit / Tesseract | Gratuit | Échecs fréquents sur tickets manuscrits d'épicerie. | **XL** | Proposition semi-automatique du montant avec validation manuelle obligatoire. |
| **P4** | **Paiement Électronique National (Edahabia / CIB)** | Règlement dématérialisé de la commission sans manipulation d'espèces. | Passerelle SATIM / GIE Monétique | Commissions bancaires | Délais d'agrément bancaire en Algérie. | **XL** | Module de paiement sécurisé complémentaire au paiement espèces (Cash on Delivery). |

---

## 3. Synthèse des Écarts, Blocages et Plan d'Action Immédiat

### 3.1 Tableau des Écarts Majeurs (Existant vs Cible)

```
[ Code Actuel ] ───────────────────────────────────────────> [ Application Cible ]
• 0 commit sur remote GitHub                                • Dépôt GitHub synchronisé avec CI/CD
• Package local "dili_express" ≠ console "diliexpress"      • Package harmonisé & SHA-1 enregistré
• Clé PIN en clair dans le document de course               • Clé PIN isolée dans sous-collection sécurisée
• Rôle modifiable par l'utilisateur dans Firestore          • Rôles verrouillés contre toute élévation
• Carte GPS simulée sans tuiles réelles                     • Carte interactive OpenStreetMap (flutter_map)
• Articles saisis uniquement à la main                      • Catalogue algérien bilingue (11 catégories)
• Transport shopper indifférencié                           • 5 modes de transport avec filtrage d'emport
• Absence de Play Integrity / App Check                     • Backend protégé par Firebase App Check
```

### 3.2 Actions Prioritaires Immédiates (Sprint P0)
1. **Étape 1 (Git)** : Initialiser le dépôt local `/root/dili_express`, créer la branche `main` et pousser le code vers `https://github.com/frechfanta-os/9DILI-EXPRESS.git`.
2. **Étape 2 (Firebase Console)** :
   - Ajouter l'application Android avec le package exact `com.ghdinteractivestudio.dili_express` (ou basculer le code local vers `com.ghdinteractivestudio.diliexpress`).
   - Enregistrer l'empreinte SHA-1 debug : `7D:F2:A7:43:F4:3A:60:3A:C1:E1:DD:B8:26:81:FE:C5:09:59:FA:20`.
   - Télécharger et appliquer le véritable `google-services.json` généré pour le projet `273784230349`.
3. **Étape 3 (Sécurité)** : Remplacer `firestore.rules` par la version durcie isolant le PIN et verrouillant les rôles.

---

> [!CAUTION]
> ### ARRÊT OBLIGATOIRE DE CONFORMITÉ
> Conformément à la consigne formelle : **AUCUNE MODIFICATION FONCTIONNELLE, AUCUN DÉPLOIEMENT FIREBASE ET AUCUNE MODIFICATION DU CODE NE SERONT ENGAGÉS AVANT LA VALIDATION EXPLICITE DE CE RAPPORT GLOBAL PAR LE COMMANDITAIRE.**
