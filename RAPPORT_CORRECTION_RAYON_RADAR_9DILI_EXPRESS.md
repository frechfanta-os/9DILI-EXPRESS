# RAPPORT DE CORRECTION DU RAYON MAXIMAL — RADAR 9DILI EXPRESS

**Projet :** 9DILI EXPRESS (Flutter Android · Cloudflare Workers · Firebase `dili-express`)  
**Branche Git :** `main` | **Commit de référence :** `36e5c3d`  
**Date de réalisation :** 16-17 Octobre 2026  
**Statut après maintenance :** **CORRECTION VALIDÉE ET TESTÉE LOCALEMENT**  

---

## 1. Diagnostic et Cause du Dépassement Initial

L'audit technique avait identifié deux causes précises expliquant pourquoi la quatrième vague du radar de commandes atteignait 11.0 km au lieu du plafond contractuel de 10.0 km :

1. **Configuration erronée (`src/radar_config.js`) :**  
   La constante `MAX_RADIUS_KM` était définie à `15.0` au lieu de `10.0`.
2. **Formule linéaire non bornée (`src/radar_service.js`) :**  
   Le calcul pour la vague $N$ était effectué via :
   $$\text{rayon} = \text{INITIAL\_RADIUS\_KM} + (N - 1) \times \text{RADIUS\_INCREMENT\_KM}$$
   Pour la vague 4 ($N = 4$) :
   $$2.0 + (4 - 1) \times 3.0 = 2.0 + 9.0 = 11.0\text{ km}$$
   Étant donné que $11.0\text{ km} < 15.0\text{ km}$, la valeur $11.0\text{ km}$ était retenue, sollicitant des commissionnaires jusqu'à 11 km à vol d'oiseau (soit 15 à 18 km par voie routière).

---

## 2. Fichiers Modifiés et Implémentation du Plafond

### 2.1. `workers/notifications_dispatcher/src/radar_config.js`
- `MAX_RADIUS_KM` corrigé à `10.0` (plafond absolu strict).
- `RADIUS_INCREMENT_KM: 3.0` conservé.
- `GPS_FRESHNESS_THRESHOLD_MS: 120 * 1000` (120 secondes) conservé.
- `MAX_SHOPPERS_PER_WAVE: 10` conservé.

### 2.2. `workers/notifications_dispatcher/src/radar_service.js`
1. **Création de la fonction dédiée `calculateWaveRadius(waveNumber)` :**
   ```javascript
   export function calculateWaveRadius(waveNumber) {
     if (waveNumber <= 1) return RADAR_CONFIG.INITIAL_RADIUS_KM;
     const theoretical = RADAR_CONFIG.INITIAL_RADIUS_KM + (waveNumber - 1) * RADAR_CONFIG.RADIUS_INCREMENT_KM;
     return Math.min(theoretical, RADAR_CONFIG.MAX_RADIUS_KM);
   }
   ```
2. **Plafonnement strict absolu dans `filterAndRankShoppers` :**
   ```javascript
   const requestedRadius = options.radiusKm !== undefined ? options.radiusKm : RADAR_CONFIG.INITIAL_RADIUS_KM;
   const radiusKm = Math.min(requestedRadius, RADAR_CONFIG.MAX_RADIUS_KM);
   ```
   Même si un appelant externe ou une interface mobile transmettait un rayon arbitraire (ex: 15 km ou 20 km), le Worker le ramène impérativement à 10.0 km.
3. **Application dans `dispatchRadarWave` et `advanceRadarWave` :**
   - Vague 1 : 2.0 km
   - Vague 2 : 5.0 km
   - Vague 3 : 8.0 km
   - Vague 4 : 10.0 km (strictement plafonné, $11.0\text{ km} \to \mathbf{10.0\text{ km}}$).

---

## 3. Progression Vérifiée des Vagues

| Vague | Calcul Théorique ($2 + (N-1) \times 3$) | Plafond Appliqué (`MAX_RADIUS_KM`) | Rayon Effectif Retenu |
| :---: | :---: | :---: | :---: |
| **Vague 1** | $2.0\text{ km}$ | $10.0\text{ km}$ | **2.0 km** |
| **Vague 2** | $5.0\text{ km}$ | $10.0\text{ km}$ | **5.0 km** |
| **Vague 3** | $8.0\text{ km}$ | $10.0\text{ km}$ | **8.0 km** |
| **Vague 4** | $11.0\text{ km}$ | $10.0\text{ km}$ | **10.0 km** |
| **Vague $\ge 5$** (si forcée) | $> 11.0\text{ km}$ | $10.0\text{ km}$ | **10.0 km** |

---

## 4. Tests de Frontière et Validation Mathématique

Les tests de frontière ont été réalisés avec les coordonnées du magasin de référence (`STORE_ALGIERS` : lat `36.7600`, lon `3.0550`) et vérifiés avec la formule exacte Haversine :

| Cas de Test | Distance Exacte Haversine | Règle de Décision | Résultat Réel Constaté | Statut |
| :--- | :---: | :---: | :---: | :---: |
| **Candidat juste en dessous** | **9.95 km** | $\le 10.0\text{ km}$ | **Sélectionné en Vague 4** | **PASS** |
| **Candidat frontière exacte** | **10.00 km** | $\le 10.0\text{ km}$ (inclusif) | **Sélectionné en Vague 4** | **PASS** |
| **Candidat au-delà du seuil** | **10.10 km** | $> 10.0\text{ km}$ | **Strictement Exclu de la Vague 4** | **PASS** |
| **Tentative externe à 15 km** | 10.10 km avec `radiusKm: 15.0` | Plafonné à $10.0\text{ km}$ | **Strictement Exclu (Plafond Worker actif)** | **PASS** |

### Maintien des Filtres d'Éligibilité dans le Rayon :
Le test 35 vérifie qu'un candidat situé à 9.95 km reste rejeté si :
- Sa position GPS date de plus de 120 secondes (testé à 130s $\to$ rejeté).
- Son statut est hors ligne (`isOnline: false` $\to$ rejeté).
- Il a une mission active (`activeErrandId: 'busy'` $\to$ rejeté).
- Son rôle est client (`role: 'client'` $\to$ rejeté).
- Il figure dans la liste d'exclusion (`excludedUids` $\to$ rejeté).

---

## 5. Résultats d'Exécution des Tests Réels

### Suite Node.js / Worker (`npm test`) :
```
✔ 31. Progression exacte des 4 vagues (2.0 km, 5.0 km, 8.0 km, 10.0 km) via calculateWaveRadius (0.11ms)
✔ 32. Plafonnement strict à 10.0 km côté Worker même si un paramètre externe demande 11, 15 ou 20 km (0.28ms)
✔ 33. Tests de frontière : candidat à 9.95 km (< 10 km) et à 10.00 km (= 10 km) éligibles en Vague 4 (0.17ms)
✔ 34. Tests de frontière : candidat à 10.10 km (> 10 km) obligatoirement exclu de la Vague 4 (0.08ms)
✔ 35. Maintien strict de tous les filtres d'éligibilité pour les candidats dans les 10 km (0.11ms)

Total suite Worker : 74 tests passés sur 74 (100% en 510 ms).
```

### Suite Flutter (`flutter test` & `flutter analyze`) :
- `flutter test` : **77 / 77 tests passés** (100% en 7 s).
- `flutter analyze` : **No issues found!** (en 21.0 s).

---

## 6. Risques Résiduels et Mesures de Maîtrise

1. **Distance à vol d'oiseau vs Distance routière réelle :**
   - *Constat :* 10 km à vol d'oiseau peuvent représenter 13 à 16 km sur le réseau routier d'Alger selon la topographie.
   - *Maîtrise :* Le modèle garantit que le rayon ne dépassera plus jamais 10 km à vol d'oiseau. À terme, une intégration OSRM ou GraphHopper pourra affiner les temps de trajet réels.
2. **Distribution des commissionnaires :**
   - Si aucun commissionnaire n'est présent dans les 10 km, le radar passe à l'état `exhausted` sans solliciter de commissionnaires lointains qui n'auraient pas pu honorer la commande dans les délais impartis.
