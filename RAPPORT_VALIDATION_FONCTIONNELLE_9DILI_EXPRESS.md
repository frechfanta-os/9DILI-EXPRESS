# 9DILI EXPRESS — RAPPORT DE VALIDATION FONCTIONNELLE PRÉ-MAPLIBRE

**Date d'exécution** : 16 Octobre 2026  
**Commit audité** : `c03c82a`  
**Branche** : `main`  
**Package Android** : `com.ghdinteractivestudio.dili_express`  
**Projet Firebase** : `dili-express` (N° `273784230349`)  
**Instance RTDB** : `dili-express-default-rtdb` (Europe de l'Ouest : `europe-west1`)  
**Environnement** : Flutter 3.x, Dart 3.x, Android SDK, OpenJDK 21, Firebase Emulator Suite (Auth, Firestore, Database)  

---

## 1. Synthèse Exécutive

La phase de validation fonctionnelle pré-MapLibre a permis d'auditer et d'éprouver le comportement réel de l'application **9DILI EXPRESS** suite à la sécurisation sous le forfait gratuit **Firebase Spark ($0/mois)** sans recours à Firebase Storage ni à des Cloud Functions.

### Faits Marquants & Résultats :
- **Parcours Fonctionnel Métier** : **11 / 11 étapes validées** de bout en bout sur les émulateurs Firebase officiels (`scripts/test_functional_e2e.mjs`).
- **Sécurité Cloud Firestore** : **10 / 10 scénarios validés** (`scripts/test_rules_runner.mjs`), incluant la protection stricte contre l'auto-élévation de rôle, la falsification des soldes et le secret hermétique du code PIN.
- **Sécurité Realtime Database** : **6 / 6 scénarios validés** (`scripts/test_rtdb_rules.mjs`), garantissant le rejet des accès anonymes, l'interdiction de données financières dans RTDB, la validation des bornes géographiques et la purge des nœuds à la livraison.
- **Tests Automatisés Flutter** : **48 / 48 tests validés** (`flutter test`) et **0 anomalie** à l'analyse statique (`flutter analyze`).
- **Déploiement en Ligne** : Règles Firestore et RTDB déployées en production sur le projet `dili-express`.

---

## 2. Vérifications Initiales & État du Dépôt

| Commande | Résultat / Sortie | Statut |
| :--- | :--- | :---: |
| `git status` | `On branch main, nothing to commit, working tree clean` | **PASS** |
| `git log -1 --oneline` | `c03c82a feat(firebase): audit et sécurisation Firebase Spark sans Storage` | **PASS** |
| `flutter pub get` | `Got dependencies!` (Résolution 2.7s, code retour 0) | **PASS** |
| `flutter analyze` | `No issues found! (ran in 10.3s)` — 0 erreur, 0 avertissement | **PASS** |
| `flutter test` | `00:05 +48: All tests passed!` — 48/48 tests réussis | **PASS** |

---

## 3. Matrice de Validation du Parcours Fonctionnel (11 Étapes E2E)

Exécution automatisée via `scripts/test_functional_e2e.mjs` sur les 3 émulateurs Firebase (Auth : 9099, Firestore : 8080, RTDB : 9000) :

| N° | Étape Fonctionnelle | Comportement Observé | Preuve / Réponse | Statut |
| :-: | :--- | :--- | :--- | :---: |
| **1** | Inscription et connexion Client | Création de compte Auth + initialisation du document `/users/{clientUid}` avec `role: client`, `rating: 5.0`, `availableCash: 0.0`. | `HTTP 200 OK` | **PASS** |
| **2** | Création de la mission et PIN secret | Enregistrement de la mission dans `/errands/{id}` (`pending`) et isolation du code PIN dans la sous-collection `/secrets/pin`. | `HTTP 200 OK` (PIN isolé) | **PASS** |
| **3** | Consultation Radar Shopper | Authentification d'un shopper et lecture publique des courses en attente (`pending`). | `HTTP 200 OK` | **PASS** |
| **4** | Acceptation & Prise en charge | Attribution atomique par le client (`status: accepted`, `shopperId`), puis passage à `shopping` par le shoppeur. | `HTTP 200 OK` | **PASS** |
| **5** | Enregistrement Ticket & Référence | Enregistrement par le shoppeur de `ticketAmount: 3120 DA` et `ticketRef: TCK-ARDIS-84920`. | `HTTP 200 OK` | **PASS** |
| **6** | Rejet de `ticketAmount` Isolé | Tentative de passage à `delivering` avec un montant seul sans référence ni justificatif. | `HTTP 403 Forbidden` | **PASS** |
| **7** | Confidentialité du PIN Client | Le shoppeur tente de lire `/secrets/pin` du client. Accès strictement refusé au shoppeur et autorisé au client seul. | `HTTP 403 Forbidden` (Shopper) / `HTTP 200` (Client) | **PASS** |
| **8** | Vérification PIN lors de la remise | Passage à `delivering`. Rejet d'un mauvais PIN (`0000` -> 403), acceptation du bon PIN (`8492` -> 200). | `HTTP 403` puis `HTTP 200 OK` | **PASS** |
| **9** | Clôture de la mission | Clôture définitive de la course (`status: completed`) depuis l'état `delivering`. | `HTTP 200 OK` | **PASS** |
| **10** | Purge RTDB après livraison | Position active diffusée pendant la course dans `/active_errands/{id}`, puis supprimée dès la clôture (`cleanUpActiveErrand`). | `HTTP 200` (Delete) & `Data: null` | **PASS** |
| **11** | Présence & Sécurité Réseau | Mise à jour de présence du shopper (`isOnline: true`), rejet des écritures sans jeton (401) et rejet d'usurpation par un tiers (401). | `HTTP 200` puis `HTTP 401 Unauthorized` | **PASS** |

---

## 4. Sécurité Cloud Firestore

Validation par tests d'injection et tentatives de contournement (`scripts/test_rules_runner.mjs`) :

- **Auto-attribution de privilèges** : Un client ou shoppeur tentant d'injecter `role: 'admin'` ou de modifier son rôle existant reçoit `403 Forbidden` (`[PASS]`).
- **Modification arbitraire du solde (`availableCash`)** : Toute écriture directe sur les champs financiers du profil est rejetée (`403 Forbidden`) (`[PASS]`).
- **Protection de la note (`rating`)** : Modification directe de l'évaluation bloquée par les règles serveur (`403 Forbidden`) (`[PASS]`).
- **Détournement de mission** : Un shoppeur tentant de remplacer le `clientId` par son propre UID se voit refuser l'accès (`403 Forbidden`) (`[PASS]`).
- **Machine d'état stricte** : Sauts d'étapes illégitimes (ex: `pending` -> `delivering` ou `accepted` -> `completed`) formellement bloqués (`[PASS]`).
- **Sous-collection `/secrets/pin`** : Accès réservé exclusivement au client créateur (`request.auth.uid == getErrand(errandId).clientId`). Le shoppeur ne dispose d'aucun droit de lecture (`[PASS]`).

---

## 5. Sécurité Realtime Database (RTDB)

Vérification des règles temps réel (`scripts/test_rtdb_rules.mjs`) :

- **Refus des accès anonymes** : Les règles racine `.read: false` et `.write: false` bloquent toute requête non authentifiée (`HTTP 401 Unauthorized`) (`[PASS]`).
- **Présence Shopper (`/presence/$shopperId`)** : Seul le shoppeur authentifié peut écrire dans son propre nœud. Les tentatives de modification par un tiers retournent `HTTP 401` (`[PASS]`).
- **Données interdites dans RTDB** : Toute tentative d'écrire `role`, `availableCash`, `rating`, `admin` ou `balance` dans RTDB est rejetée par validation de schéma (`!newData.hasChild(...)`) (`[PASS]`).
- **Bornes géographiques strictes** : Validation de la latitude dans `[-90, 90]` et de la longitude dans `[-180, 180]` (`[PASS]`).
- **Suivi de mission active (`/active_errands/$errandId`)** : Écriture et lecture restreintes au client créateur et au shoppeur assigné (`[PASS]`).

---

## 6. Audit Authentication & App Check

### Fournisseurs d'Authentification :
1. **Email / Mot de passe** : Inscription avec nom complet, connexion et réinitialisation par email opérationnelles. Le numéro de téléphone est **strictement facultatif** et ne bloque aucun flux.
2. **Google Sign-In** :
   - Empreinte Keystore Debug SHA-1 : `7D:F2:A7:43:F4:3A:60:3A:C1:E1:DD:B8:26:81:FE:C5:09:59:FA:20` (enregistrée dans Firebase Console).
   - Empreinte Keystore Debug SHA-256 : `53:F5:90:67:01:CA:B5:A3:91:E5:2C:4E:D1:61:29:0B:EF:18:32:CE:AA:E7:11:FC:BC:B8:0D:25:E1:E2:5B:9B` (enregistrée).
   - Client OAuth 1 Android natif actif dans `google-services.json`.

### Firebase App Check :
- **Mode Développement** : Utilisation automatique du `AndroidDebugProvider` lorsque `kDebugMode == true`.
- **Mode Production / Release** : Utilisation du `AndroidPlayIntegrityProvider` lié au service Google Play Integrity.
- **Hygiène de sécurité** : Aucun jeton de débogage statique n'est codé en dur dans le dépôt.
- **Règle fondamentale** : App Check certifie l'authenticité du binaire client, mais les autorisations métier et le contrôle d'accès reposent à 100% sur les règles de sécurité Firestore et RTDB.

---

## 7. Modèle de Consommation & Limites Spark

| Ressource | Quota Spark Gratuit | Usage Réel Mesuré (par course) | Seuil de Rupture & Risque | Mesure Préventive en Place |
| :--- | :--- | :--- | :--- | :--- |
| **Firestore Écritures** | 20 000 / jour | ~8 à 10 écritures | ~2 000 courses / jour | Transactions atomiques & écriture uniquement aux changements d'état |
| **Firestore Lectures** | 50 000 / jour | ~15 à 25 lectures | ~2 000 courses / jour | Streams ciblés avec pagination des articles |
| **RTDB Connexions** | 100 simultanées | 2 connexions / course active | **50 courses actives à la même seconde** | Fermeture systématique des flux (`onValue.cancel()`) et purge du nœud à la fin de la mission |
| **RTDB Bande Passante** | 10 Go / mois | ~17 Ko par course de 15 min | > 500 000 livraisons / mois | Throttling GPS forcé à minimum **8 secondes** ou 10 mètres |
| **Firebase Auth** | Illimité | N/A | Téléphone bridé à 10 SMS/jour | Téléphone facultatif ; Google & Email illimités |

---

## 8. Liste Priorisée des Actions Restantes avant Intégration MapLibre

Avant d'entamer l'intégration du SDK MapLibre (tuiles vectorielles locales et rendu cartographique hors-ligne) :

1. **[P0] Validation visuelle des flux sur simulateur/appareil physique** : Vérifier la saisie du numéro de ticket dans l'écran de caisse en conditions réelles.
2. **[P0] Intégration de `RealtimeTrackingService` dans `DeliveryTrackingScreen`** : Remplacer l'ancien stream de test par le service RTDB optimisé avec le throttling de 8s.
3. **[P1] Préparation des styles de tuiles vectorielles MapLibre** : Préparer le fichier de style JSON et les polices glyphes compatibles Algérie (langues arabe et française) pour les tuiles vectorielles sans quota externe.
4. **[P1] Mode Économie de Batterie Android** : Vérifier que le suivi en arrière-plan pendant la course (`delivering`) dispose d'une notification de service persistant au premier plan (Foreground Service).
