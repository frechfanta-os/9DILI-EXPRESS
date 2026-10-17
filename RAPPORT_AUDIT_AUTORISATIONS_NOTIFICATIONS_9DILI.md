# Rapport Technique — Audit des Autorisations Android et Réparation des Notifications | 9DILI EXPRESS

## 1. Contexte de l'Audit

Ce document présente l'audit complet du cycle de notifications de l'application **9DILI EXPRESS** (`com.ghdinteractivestudio.dili_express`), couvrant :
- Les permissions Android natives (Android 13 à 16).
- L'architecture Firebase Cloud Messaging (FCM).
- Le backend sécurisé de dispatching via le Cloudflare Worker.
- Les règles de sécurité Firestore pour les jetons d'appareils.

---

## 2. Constats et Vulnérabilités Identifiées

1. **Absence du Package `firebase_messaging`** :
   Le fichier `pubspec.yaml` ne contenait aucune dépendance pour Firebase Messaging, empêchant l'écoute native des messages push et la récupération du FCM Token.
2. **Permissions Android Manquantes** :
   Sur Android 13+ (API 33) et Android 16, la permission `POST_NOTIFICATIONS` doit impérativement être déclarée dans le manifeste ET demandée au runtime. Elle était absente du `AndroidManifest.xml`.
3. **Absence du Canal de Notification Déclaré** :
   Le Worker Cloudflare (`workers/notifications_dispatcher/src/fcm.js`) cible explicitement le canal `errand_updates_channel` avec son et vibration haute priorité. Sans déclaration native dans les métadonnées Android, les notifications étaient silencieuses ou ignorées sur les versions récentes d'Android.
4. **Visibilité du Dialer Téléphonique (Android 11+)** :
   L'intent `tel:` pour l'appel obligatoire n'était pas déclaré dans `<queries>`, bloquant les redirections vers l'application Téléphone sur Android 11+.

---

## 3. Correctifs Appliqués

### A. Manifeste Android (`android/app/src/main/AndroidManifest.xml`)
Déclaration formelle des permissions et filtres nécessaires :
```xml
<!-- Notifications push sur Android 13+ / 16 -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<!-- Caméra pour prise de vue des tickets de caisse -->
<uses-permission android:name="android.permission.CAMERA"/>

<!-- Canal par défaut pour FCM correspondant au Cloudflare Worker -->
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="errand_updates_channel" />

<!-- Filtres de visibilité pour les appels téléphoniques obligatoires -->
<queries>
    <intent>
        <action android:name="android.intent.action.DIAL" />
        <data android:scheme="tel" />
    </intent>
</queries>
```

### B. Service de Notifications Dédié (`lib/services/notification_service.dart`)
Création d'un service d'encapsulation complet :
- **Demande de permission explicite** (`requestPermission()`) au moment opportun.
- **Gestion multi-appareils** : Stockage du token FCM dans la sous-collection sécurisée `/users/{uid}/fcm_tokens/{tokenId}` avec métadonnées (`platform: android`, `updatedAt`, `createdAt`).
- **Écoute de rafraîchissement** : Mise à jour automatique en cas de renouvellement du token par Google.
- **Diffusion au premier plan** : Exposition d'un stream `onMessageReceived` pour afficher des bannières ou SnackBar in-app lorsque l'utilisateur est actif.

### C. Sécurisation des Règles Firestore (`firestore.rules`)
Autorisation accordée uniquement à l'utilisateur propriétaire pour enregistrer ou supprimer ses propres tokens :
```text
match /users/{userId}/fcm_tokens/{tokenId} {
  allow read, write: if isOwner(userId);
}
```

### D. Cohérence avec le Worker Cloudflare
Le fichier `workers/notifications_dispatcher/src/fcm.js` utilise l'API HTTP v1 de FCM (`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`) avec jeton JWT généré à la volée. Il envoie la charge utile avec :
```json
{
  "android": {
    "priority": "HIGH",
    "notification": {
      "channel_id": "errand_updates_channel",
      "notification_priority": "PRIORITY_HIGH",
      "default_sound": true
    }
  }
}
> [!IMPORTANT]
> **Rectificatif d'audit (Mission de réparation)** :
> L'affirmation antérieure « L'intégration Flutter et Cloudflare est désormais parfaitement alignée » était inexacte. Le service `NotificationService` n'était pas instancié dans `main.dart`, aucun appel HTTP vers le Worker (`/api/notify`) n'existait, et le canal natif `errand_updates_channel` n'était pas créé à l'exécution.
> La chaîne complète a été effectivement branchée et rendue opérationnelle : `NotificationDispatchService` (HTTP v1 Worker), injection au cycle de vie `authStateChanges`, création native du canal dans `MainActivity.kt` et dérivation déterministe des payloads.

