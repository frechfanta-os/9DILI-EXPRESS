# 9DILI EXPRESS — RAPPORT DE SÉCURISATION FIREBASE SPARK (SANS STORAGE)

**Date d'exécution** : 16 Octobre 2026  
**Projet Firebase** : `dili-express` (N° `273784230349`)  
**Package Android** : `com.ghdinteractivestudio.dili_express`  
**Plan Tarifaire** : Firebase Spark Gratuit ($0.00 / mois permanent)  
**Environnement** : Flutter Android, Termux/Ubuntu PRoot, Firebase Emulator Suite, OpenJDK 21  

---

## 1. Synthèse Exécutive & Conformité Spark

L'architecture backend de l'application **9DILI EXPRESS** a été intégralement auditée, sécurisée et adaptée aux contraintes strictes du **forfait gratuit Firebase Spark** ($0/mois) sans aucun recours à des Cloud Functions, Cloud Run ou serveurs privés.

### Principes Directeurs Réalisés :
1. **Éradication Totale de Firebase Storage** : Suppression de la dépendance `firebase_storage`, suppression de `storage.rules`, exclusion du bucket dans `firebase.json` et `firebase_options.dart`. Aucun stockage cloud de photos n'est requis ni simulé par encodage Base64 frauduleux.
2. **Preuve Métier des Justificatifs de Caisse** : Le déblocage de l'étape « En route » (`delivering`) repose désormais sur la validation conjointe d'un montant exact (`ticketAmount > 0`), d'une référence officielle de ticket de caisse (`ticketRef` ≥ 3 caractères), et de l'engagement de remise en mains propres du ticket papier original lors de l'échange bilatéral sécurisé par code PIN.
3. **Déploiement Effectif de Firebase Realtime Database** : Instance par défaut créée avec succès en Europe de l'Ouest (`europe-west1`) sous l'identifiant `dili-express-default-rtdb` et règles de sécurité temps réel déployées en production.
4. **Optimisation des Quotas Temps Réel** : Suivi GPS restreint aux courses actives avec limitation de fréquence (intervalle minimum de 8 secondes / 10 mètres), présence automatique avec `onDisconnect()` et purge immédiate à la fin de la mission.
5. **Couverture de Tests Intégrale** : 100% des tests validés (48/48 tests Flutter, 10/10 scénarios Firestore, 6/6 scénarios RTDB).

---

## 2. Tableau Statutaire des Composants Firebase

| Composant | Statut Réel | Déploiement / Configuration | Résultat Validation |
| :--- | :---: | :--- | :---: |
| **Cloud Firestore** | **PASS** | Déployé en production (`firestore.rules`) | 10/10 scénarios validés |
| **Realtime Database** | **PASS** | Instance créée (`europe-west1`) & règles déployées | 6/6 scénarios validés |
| **Firebase Auth** | **PASS** | Google Sign-In (OAuth Client 1 configuré avec SHA-1/256) | Actif & fonctionnel |
| **Firebase App Check** | **PASS** | Intégré (DebugProvider dev / PlayIntegrity release) | Actif dans le code |
| **Firebase Storage** | **REMOVED** | Dépendances et règles supprimées, bucket non provisionné | 0 B / 0 appel |
| **Cloud Functions / Run** | **EXCLUDED** | Aucune fonction serveur requise | 0 coût |

---

## 3. Matrice de Sécurité & Validation par Émulateur

### A. Scénarios Cloud Firestore (10/10 PASS)
Exécutés via `scripts/test_rules_runner.mjs` sur l'émulateur Firestore (port 8080) :
- `[PASS]` **Scénario 1** : Création et lecture conforme du profil par son propriétaire.
- `[PASS]` **Scénario 2** : Blocage formel de l'auto-attribution du rôle `admin`.
- `[PASS]` **Scénario 3** : Rejet de la modification directe du solde (`availableCash`).
- `[PASS]` **Scénario 4** : Confidentialité stricte du code PIN secret dans `/secrets/pin` (Shopper interdit).
- `[PASS]` **Scénario 5** : Rejet de toute lecture/écriture par un tiers non autorisé (403 Forbidden).
- `[PASS]` **Scénario 6** : Blocage du détournement de mission ou altération de `clientId`.
- `[PASS]` **Scénario 7** : Refus de passage à l'état `delivering` sans ticket de caisse et montant valide.
- `[PASS]` **Scénario 8** : Protection contre l'altération de la note (`rating`).
- `[PASS]` **Scénario 9** : Rejet systématique des requêtes non authentifiées.
- `[PASS]` **Scénario 10** : Consultation légitime du PIN par le client et lecture publique du catalogue.

### B. Scénarios Realtime Database (6/6 PASS)
Exécutés via `scripts/test_rtdb_rules.mjs` sur l'émulateur RTDB (port 9000, namespace `dili-express-default-rtdb`) :
- `[PASS]` **Scénario 1** : Refus catégorique des accès anonymes (règles racine `.read: false`, `.write: false`).
- `[PASS]` **Scénario 2** : Mise à jour conforme de la présence par le Shopper (`isOnline`, `lastSeen`).
- `[PASS]` **Scénario 3** : Rejet de la falsification de la présence d'un autre utilisateur.
- `[PASS]` **Scénario 4** : Interdiction absolue d'injecter des données métier (`role`, `availableCash`, `rating`, `admin`, `balance`) dans RTDB.
- `[PASS]` **Scénario 5** : Rejet strict des coordonnées GPS hors bornes (Latitude ∉ [-90, 90] ou Longitude ∉ [-180, 180]).
- `[PASS]` **Scénario 6** : Suivi de course active dans `/active_errands/{errandId}` restreint exclusivement au Client et au Shopper assigné.

---

## 4. Architecture de Justificatif sans Stockage Cloud

Pour concilier l'absence de Firebase Storage (forfait Spark) et la traçabilité des dépenses, le flux a été repensé selon une logique métier stricte :

1. **Interdiction de `ticketAmount` Isolé** :
   Un simple montant saisi ne permet en aucun cas de passer au statut `delivering`.
2. **Référence de Caisse Officielle (`ticketRef`)** :
   Le shopper doit saisir le numéro de ticket de caisse ou de facture magasin (≥ 3 caractères, ex: `TCK-2026-08492`).
3. **Aperçu Visuel Local (Optionnel)** :
   Une prise de vue locale peut être affichée dans l'interface pour contrôle immédiat avant le départ, sans nécessiter de téléversement distant ni de stockage permanent.
4. **Remise Physique et Quitus PIN** :
   Le ticket de caisse papier original est remis en mains propres au client lors de la livraison. La remise du ticket fait partie intégrante de la validation du code PIN à 4 chiffres.
5. **Formule Financière Immuable** :
   `Total à payer = Montant du ticket + Commission négociée`.

---

## 5. Modèle de Consommation & Quotas Forfait Spark

| Ressource Firebase | Quota Gratuit Spark | Consommation Estimée (par course) | Capacité Maximale Quotidienne |
| :--- | :--- | :--- | :--- |
| **Firestore Écritures** | 20 000 / jour | ~10 écritures / course complète | **~2 000 courses / jour** |
| **Firestore Lectures** | 50 000 / jour | ~25 à 30 lectures / course | **~1 600 à 2 000 courses / jour** |
| **Firestore Stockage** | 1 Go total | ~1 Ko par document de course | **> 500 000 courses archivées** |
| **RTDB Connexions** | 100 simultanées | 2 connexions par course active | **50 courses simultanées en direct** |
| **RTDB Bande Passante** | 10 Go / mois | ~17 Ko par livraison de 15 min | **> 500 000 livraisons / mois** |
| **Firebase Auth** | Illimité (Google / Email) | 1 session par utilisateur | **Illimité (hors quota 10 SMS/j)** |
| **Firebase Storage** | 0 Mo utilisé | 0 Ko (Désactivé) | **Aucun risque de dépassement** |

### Point de Rupture & Recommandations :
- **Point de rupture principal** : Le plafond de **100 connexions simultanées** sur Realtime Database. Dès que plus de 50 clients et 50 shoppers consultent la carte à la même seconde, les connexions excédentaires sont mises en file d'attente.
- **Mesure préventive implémentée** : Fermeture systématique des écoutes (`onValue.cancel()`) dès la sortie de l'écran de suivi et appel de `cleanUpActiveErrand()` à l'encaissement du PIN.

---

## 6. Bilan des Tests Automatisés

- **`flutter analyze`** : `No issues found! (ran in 11.7s)` — 0 avertissement, 0 erreur.
- **`flutter test`** : **48 / 48 tests validés** (dont 6 tests dédiés aux règles Spark & RTDB).
- **Règles Firestore** : Déployées en ligne avec succès sur `dili-express`.
- **Règles Realtime Database** : Déployées en ligne avec succès sur `dili-express-default-rtdb`.
