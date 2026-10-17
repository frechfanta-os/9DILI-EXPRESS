import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/errand_model.dart';
import '../models/errand_item_model.dart';
import '../models/errand_bid_model.dart';
import 'offline_pin_cache_service.dart';
import 'notification_dispatch_service.dart';

/// Statuts détaillés du contrôle de sécurité PIN.
enum PinValidationStatus {
  success,
  invalidPin,
  expired,
  locked,
  alreadyCompleted,
  invalidState,
  notFound,
}

/// Résultat d'une vérification de code PIN avec détails de sécurité.
class PinValidationResult {
  final PinValidationStatus status;
  final String message;
  final int remainingAttempts;

  const PinValidationResult._(
    this.status,
    this.message, {
    this.remainingAttempts = 0,
  });

  factory PinValidationResult.success() => const PinValidationResult._(
    PinValidationStatus.success,
    'Code PIN validé avec succès ! Remise confirmée.',
  );

  factory PinValidationResult.invalidPin(int remaining) =>
      PinValidationResult._(
        PinValidationStatus.invalidPin,
        'Code PIN incorrect. Tentatives restantes : $remaining',
        remainingAttempts: remaining,
      );

  factory PinValidationResult.locked() => const PinValidationResult._(
    PinValidationStatus.locked,
    'Sécurité activée : Trop de tentatives infructueuses. Code PIN verrouillé.',
  );

  factory PinValidationResult.expired() => const PinValidationResult._(
    PinValidationStatus.expired,
    'Le code PIN a expiré. Veuillez demander au client de régénérer son code.',
  );

  factory PinValidationResult.alreadyCompleted() => const PinValidationResult._(
    PinValidationStatus.alreadyCompleted,
    'Cette course a déjà été clôturée.',
  );

  factory PinValidationResult.invalidState(
    String currentStatus,
  ) => PinValidationResult._(
    PinValidationStatus.invalidState,
    'Impossible de clôturer : la course est au statut "$currentStatus" (doit être "delivering").',
  );

  factory PinValidationResult.notFound() => const PinValidationResult._(
    PinValidationStatus.notFound,
    'Course introuvable.',
  );

  bool get isSuccess => status == PinValidationStatus.success;
}

/// Service sécurisé des courses 9DILI EXPRESS avec contrôle d'intégrité, concurrence et anti-brute force.
class ErrandService {
  final FirebaseFirestore? _customFirestore;
  final OfflinePinCacheService _pinCacheService;
  final NotificationDispatchService? _dispatchService;

  ErrandService({
    FirebaseFirestore? firestore,
    OfflinePinCacheService? pinCacheService,
    NotificationDispatchService? notificationDispatchService,
  }) : _customFirestore = firestore,
       _pinCacheService = pinCacheService ?? OfflinePinCacheService(),
       _dispatchService = notificationDispatchService;

  NotificationDispatchService? get dispatchService => _dispatchService;

  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _errandsRef =>
      _firestore.collection('errands');

  CollectionReference<Map<String, dynamic>> _itemsRef(String errandId) =>
      _errandsRef.doc(errandId).collection('items');

  CollectionReference<Map<String, dynamic>> _bidsRef(String errandId) =>
      _errandsRef.doc(errandId).collection('bids');

  /// Génère un code PIN cryptographiquement sécurisé à 4 chiffres (Random.secure).
  static String generateCryptographicPin() {
    final rng = Random.secure();
    return (1000 + rng.nextInt(9000)).toString();
  }

  // ==========================================
  // 1. GESTION DES COURSES (ERRANDS)
  // ==========================================

  /// Crée une nouvelle course avec son code PIN cryptographique, expiration et articles initiaux.
  Future<String> createErrand(
    ErrandModel errand, {
    List<ErrandItemModel>? items,
  }) async {
    final docRef = errand.errandId.isNotEmpty
        ? _errandsRef.doc(errand.errandId)
        : _errandsRef.doc();

    final actualId = docRef.id;

    // PIN sécurisé généré avec Random.secure() si non fourni
    final pin = errand.securePin.isNotEmpty
        ? errand.securePin
        : generateCryptographicPin();

    // Expiration automatique à 30 minutes
    final expiresAt =
        errand.pinExpiresAt ?? DateTime.now().add(const Duration(minutes: 30));

    final errandToSave = errand.copyWith(
      errandId: actualId,
      securePin: pin,
      pinExpiresAt: expiresAt,
      pinFailedAttempts: 0,
      pinLocked: false,
    );

    // Sauvegarde atomique de la course principale
    await docRef.set(errandToSave.toMap());

    // Mise en cache locale du code PIN côté client créateur
    await _pinCacheService.savePin(actualId, pin);

    // Ajout des articles initiaux en sous-collection via batch
    if (items != null && items.isNotEmpty) {
      final batch = _firestore.batch();
      for (final item in items) {
        final itemDoc = item.itemId.isNotEmpty
            ? _itemsRef(actualId).doc(item.itemId)
            : _itemsRef(actualId).doc();
        batch.set(itemDoc, item.copyWith(itemId: itemDoc.id).toMap());
      }
      await batch.commit();
    }

    // Déclenchement non-bloquant de la notification et du radar intelligent
    if (_dispatchService != null) {
      _dispatchService.notify(
        errandId: actualId,
        eventType: 'new_errand_available',
      ).catchError((e) {
        debugPrint('ErrandService: new_errand_available notification error: $e');
        return false;
      });
      _dispatchService.dispatchRadar(errandId: actualId).catchError((e) {
        debugPrint('ErrandService: dispatchRadar non-blocking error: $e');
        return null;
      });
    }

    return actualId;
  }

  /// Récupère une course par son ID.
  Future<ErrandModel?> getErrand(String errandId) async {
    if (errandId.isEmpty) return null;
    final doc = await _errandsRef.doc(errandId).get();
    if (!doc.exists || doc.data() == null) return null;
    return ErrandModel.fromFirestore(doc);
  }

  /// Écoute en temps réel une course spécifique.
  Stream<ErrandModel?> streamErrand(String errandId) {
    if (errandId.isEmpty) return Stream.value(null);
    return _errandsRef.doc(errandId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return ErrandModel.fromFirestore(doc);
    });
  }

  /// Écoute les courses commandées par un client.
  Stream<List<ErrandModel>> streamClientErrands(String clientId) {
    return _errandsRef
        .where('clientId', isEqualTo: clientId)
        .snapshots()
        .map((s) => s.docs.map((d) => ErrandModel.fromFirestore(d)).toList());
  }

  /// Écoute les courses prises en charge par un shoppeur.
  Stream<List<ErrandModel>> streamShopperErrands(String shopperId) {
    return _errandsRef
        .where('shopperId', isEqualTo: shopperId)
        .snapshots()
        .map((s) => s.docs.map((d) => ErrandModel.fromFirestore(d)).toList());
  }

  /// Radar des courses disponibles (status 'pending') pour les shoppeurs.
  Stream<List<ErrandModel>> streamPendingErrands({double? maxBudget}) {
    return _errandsRef
        .where('status', isEqualTo: ErrandStatus.pending)
        .snapshots()
        .map((s) {
          var list = s.docs.map((d) => ErrandModel.fromFirestore(d)).toList();
          if (maxBudget != null && maxBudget > 0) {
            list = list.where((e) => e.estimatedBudget <= maxBudget).toList();
          }
          return list;
        });
  }

  /// Met à jour le statut d'une course avec validation de la machine d'état.
  Future<void> updateErrandStatus(String errandId, String newStatus) async {
    final current = await getErrand(errandId);
    if (current == null) {
      throw StateError("Course introuvable: $errandId");
    }
    if (!current.canTransitionTo(newStatus)) {
      throw StateError(
        "Transition illégale de '${current.status}' vers '$newStatus'.",
      );
    }
    await _errandsRef.doc(errandId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Met à jour la position GPS en direct du shoppeur sur la course.
  Future<void> updateShopperLocation(String errandId, GeoPoint location) async {
    await _errandsRef.doc(errandId).update({
      'shopperLocation': location,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Enregistre le montant exact et le justificatif probant (référence de caisse ou photo/URI).
  /// Conforme au plan Spark sans Storage : Ne requiert pas d'hébergement cloud d'image.
  Future<void> submitTicket({
    required String errandId,
    required double ticketAmount,
    String? ticketPhotoUrl,
    String? ticketRef,
  }) async {
    if (ticketAmount <= 0) {
      throw ArgumentError(
        "Le montant du ticket doit être strictement supérieur à zéro.",
      );
    }
    final hasValidRef = ticketRef != null && ticketRef.trim().length >= 3;
    final hasValidPhoto =
        ticketPhotoUrl != null && ticketPhotoUrl.trim().isNotEmpty;
    if (!hasValidRef && !hasValidPhoto) {
      throw ArgumentError(
        "Un justificatif probant (référence de caisse ou photo) est obligatoire.",
      );
    }

    final updateData = <String, dynamic>{
      'ticketAmount': ticketAmount,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (ticketPhotoUrl != null && ticketPhotoUrl.isNotEmpty) {
      updateData['ticketPhotoUrl'] = ticketPhotoUrl;
    }
    if (ticketRef != null && ticketRef.isNotEmpty) {
      updateData['ticketRef'] = ticketRef.trim();
    }

    await _errandsRef.doc(errandId).update(updateData);
  }

  /// Attestation explicite de l'appel téléphonique obligatoire avec horodatage et auteur.
  Future<void> markCallCompleted({
    required String errandId,
    required String confirmedByUserId,
  }) async {
    await _errandsRef.doc(errandId).update({
      'callCompleted': true,
      'callConfirmedAt': FieldValue.serverTimestamp(),
      'callConfirmedBy': confirmedByUserId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Confirme définitivement la course après appel attesté.
  Future<bool> confirmErrandAssignment(String errandId) async {
    final errand = await getErrand(errandId);
    if (errand == null) return false;
    if (!errand.callCompleted) {
      throw StateError(
        "L'appel entre le client et le shoppeur est obligatoire avant toute confirmation !",
      );
    }
    await _errandsRef.doc(errandId).update({
      'status': ErrandStatus.accepted,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (_dispatchService != null) {
      _dispatchService.notify(
        errandId: errandId,
        eventType: 'errand_accepted',
      ).catchError((e) {
        debugPrint('ErrandService: errand_accepted notification error: $e');
        return false;
      });
    }
    return true;
  }

  /// Démarre les achats en magasin (statut 'shopping').
  Future<void> startShopping(String errandId) async {
    await updateErrandStatus(errandId, ErrandStatus.shopping);
  }

  /// Passe au statut "delivering" (en route).
  /// Règle stricte : Le passage au statut « En route » doit être bloqué tant que le justificatif et le montant ne sont pas enregistrés et validés !
  Future<bool> startDelivering(String errandId) async {
    final errand = await getErrand(errandId);
    if (errand == null) return false;
    if (!errand.isReceiptValidated) {
      throw StateError(
        "Le justificatif de caisse et le montant exact doivent être validés avant le départ en livraison !",
      );
    }
    await updateErrandStatus(errandId, ErrandStatus.delivering);
    if (_dispatchService != null) {
      _dispatchService.notify(
        errandId: errandId,
        eventType: 'shopper_delivering',
      ).catchError((e) {
        debugPrint('ErrandService: shopper_delivering notification error: $e');
        return false;
      });
    }
    return true;
  }

  /// Valide la livraison à l'aide du code PIN à 4 chiffres avec contrôle anti-brute force et expiration.
  Future<PinValidationResult> completeErrandWithPin(
    String errandId,
    String inputPin,
  ) async {
    final errand = await getErrand(errandId);
    if (errand == null) {
      return PinValidationResult.notFound();
    }

    // 1. Protection contre les doubles clôtures (idempotence)
    if (errand.isCompleted) {
      return PinValidationResult.alreadyCompleted();
    }

    // 2. Vérification de la machine d'état : doit être en cours de livraison
    if (!errand.isDelivering) {
      return PinValidationResult.invalidState(errand.status);
    }

    // 3. Protection anti-brute force : verrouillage après 3 échecs
    if (errand.isPinLocked) {
      return PinValidationResult.locked();
    }

    // 4. Vérification d'expiration temporelle du code PIN
    if (errand.isPinExpired) {
      return PinValidationResult.expired();
    }

    // 5. Comparaison du PIN
    final cleanInput = inputPin.trim();
    final isValid =
        errand.securePin.trim() == cleanInput ||
        await _pinCacheService.verifyPin(errandId, cleanInput);

    if (isValid) {
      // Clôture définitive avec réinitialisation des tentatives
      await _errandsRef.doc(errandId).update({
        'status': ErrandStatus.completed,
        'pinFailedAttempts': 0,
        'pinLocked': false,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _pinCacheService.clearPin(errandId);
      if (_dispatchService != null) {
        _dispatchService.notify(
          errandId: errandId,
          eventType: 'errand_completed',
        ).catchError((e) {
          debugPrint('ErrandService: errand_completed notification error: $e');
          return false;
        });
      }
      return PinValidationResult.success();
    } else {
      // Incrémentation des tentatives échouées
      final newFailedCount = errand.pinFailedAttempts + 1;
      final isNowLocked = newFailedCount >= 3;

      await _errandsRef.doc(errandId).update({
        'pinFailedAttempts': newFailedCount,
        'pinLocked': isNowLocked,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (isNowLocked) {
        return PinValidationResult.locked();
      }
      return PinValidationResult.invalidPin(3 - newFailedCount);
    }
  }

  /// Notifie le client que le shopper est arrivé sur place au point de remise.
  Future<void> notifyShopperArrived(String errandId) async {
    try {
      await _dispatchService?.notify(
        errandId: errandId,
        eventType: 'shopper_arrived',
      );
    } catch (e) {
      debugPrint('ErrandService: shopper_arrived notification error: $e');
    }
  }

  // ==========================================
  // 2. SOUS-COLLECTION ARTICLES (/items)
  // ==========================================

  /// Ajoute un article à la course.
  Future<String> addItem(String errandId, ErrandItemModel item) async {
    final docRef = item.itemId.isNotEmpty
        ? _itemsRef(errandId).doc(item.itemId)
        : _itemsRef(errandId).doc();
    final actualId = docRef.id;
    await docRef.set(item.copyWith(itemId: actualId).toMap());
    return actualId;
  }

  /// Met à jour un article (statut: found, replaced, unavailable, etc.).
  Future<void> updateItem(String errandId, ErrandItemModel item) async {
    await _itemsRef(errandId).doc(item.itemId).update(item.toMap());
  }

  /// Supprime un article d'une course.
  Future<void> deleteItem(String errandId, String itemId) async {
    await _itemsRef(errandId).doc(itemId).delete();
  }

  /// Écoute en temps réel les articles d'une course.
  Stream<List<ErrandItemModel>> streamItems(String errandId) {
    return _itemsRef(errandId).snapshots().map(
      (s) => s.docs.map((d) => ErrandItemModel.fromFirestore(d)).toList(),
    );
  }

  // ==========================================
  // 3. SOUS-COLLECTION OFFRES (/bids) AVEC CONCURRENCE
  // ==========================================

  /// Propose une offre (bid) de commission pour une course en attente.
  Future<String> placeBid(String errandId, ErrandBidModel bid) async {
    final docRef = bid.bidId.isNotEmpty
        ? _bidsRef(errandId).doc(bid.bidId)
        : _bidsRef(errandId).doc();
    final actualId = docRef.id;
    await docRef.set(bid.copyWith(bidId: actualId).toMap());
    return actualId;
  }

  /// Accepte une offre avec protection contre les conditions de concurrence (Race conditions).
  /// Exécute une transaction atomique pour garantir qu'un seul shoppeur est affecté.
  Future<void> acceptBid({
    required String errandId,
    required String bidId,
    required String shopperId,
    required double agreedCommission,
    String? shopperPhone,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final errandDocRef = _errandsRef.doc(errandId);
      final errandSnap = await transaction.get(errandDocRef);

      if (!errandSnap.exists || errandSnap.data() == null) {
        throw StateError("Course introuvable: $errandId");
      }

      final errandData = errandSnap.data()!;
      final currentStatus = errandData['status'];
      final currentShopper = errandData['shopperId'];

      if (currentStatus != ErrandStatus.pending ||
          (currentShopper != null && currentShopper.toString().isNotEmpty)) {
        throw StateError(
          "Cette course a déjà été attribuée ou n'est plus en attente d'offres.",
        );
      }

      final callCompleted = errandData['callCompleted'] == true;
      if (!callCompleted) {
        throw StateError(
          "L'appel téléphonique préalable est obligatoire avant acceptation de l'offre !",
        );
      }

      // 1. Mettre à jour l'offre acceptée
      final acceptedBidRef = _bidsRef(errandId).doc(bidId);
      transaction.update(acceptedBidRef, {
        'status': BidStatus.accepted,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. Mettre à jour la course de façon atomique
      transaction.update(errandDocRef, {
        'shopperId': shopperId,
        if (shopperPhone != null && shopperPhone.isNotEmpty)
          'shopperPhone': shopperPhone,
        'negotiatedCommission': agreedCommission,
        'status': ErrandStatus.accepted,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    // 3. Rejeter les autres offres en tâche de fond
    final bidsSnapshot = await _bidsRef(errandId).get();
    final batch = _firestore.batch();
    for (final doc in bidsSnapshot.docs) {
      if (doc.id != bidId && doc.data()['status'] == BidStatus.pending) {
        batch.update(doc.reference, {
          'status': BidStatus.rejected,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();

    if (_dispatchService != null) {
      _dispatchService.notify(
        errandId: errandId,
        eventType: 'bid_accepted',
      ).catchError((e) {
        debugPrint('ErrandService: bid_accepted notification error: $e');
        return false;
      });
    }
  }

  /// Refuse une offre spécifique.
  Future<void> rejectBid(String errandId, String bidId) async {
    await _bidsRef(errandId).doc(bidId).update({
      'status': BidStatus.rejected,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Écoute en temps réel les offres associées à une course.
  Stream<List<ErrandBidModel>> streamBids(String errandId) {
    return _bidsRef(errandId).snapshots().map(
      (s) => s.docs.map((d) => ErrandBidModel.fromFirestore(d)).toList(),
    );
  }

  // ==========================================
  // 4. ATTRIBUTION ATOMIQUE DU RADAR & REFUS
  // ==========================================

  /// Attribution exclusive et atomique d'une course à un shoppeur via transaction Firestore.
  /// Garantit qu'un seul shoppeur parmi des requêtes concurrentes simultanées obtient la course.
  /// Rejette les concurrents avec StateError('already_assigned').
  /// Idempotent : Si le shoppeur appelant est déjà le gagnant, retourne true sans erreur.
  /// Garde de sécurité : Interdit expressément au créateur de s'auto-attribuer sa propre course.
  ///
  /// RÉCONCILIATION ARCHITECTURALE & RÈGLES DE SÉCURITÉ FIRESTORE :
  /// - En production, les règles de sécurité Firestore locales (`firestore.rules`)
  ///   restreignent les écritures aux seuls créateurs (`clientId == request.auth.uid`)
  ///   ou commissionnaires déjà assignés (`shopperId == request.auth.uid`).
  /// - Un commissionnaire tiers non assigné ne peut donc PAS s'auto-attribuer
  ///   directement une course via le SDK client Firestore (rejet `PERMISSION_DENIED`).
  /// - Pour les commissionnaires candidats du Radar, l'attribution autorisée passe
  ///   exclusivement par l'endpoint sécurisé du Worker Cloudflare `/api/radar/accept`,
  ///   qui authentifie le demandeur par jeton Firebase Auth et exécute la mutation
  ///   atomique sous privilège de compte de service avec précondition `updateTime`.
  /// - Cette méthode client `assignShopperAtomic` demeure le composant de référence
  ///   pour les attributions directes autorisées (ex: confirmation par le client créateur,
  ///   ou bancs de tests unitaires/locaux).
  Future<bool> assignShopperAtomic({
    required String errandId,
    required String shopperId,
    double? agreedCommission,
  }) async {
    final result = await _firestore.runTransaction<bool>((transaction) async {
      final docRef = _errandsRef.doc(errandId);
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError("Course introuvable: $errandId");
      }

      final data = snapshot.data()!;
      final currentClientId = data['clientId'];
      final currentShopper = data['shopperId'];
      final currentStatus = data['status'];

      // Garde stricte : Le créateur ne peut en aucun cas s'auto-attribuer sa propre course
      if (currentClientId != null && currentClientId == shopperId) {
        throw StateError(
          "cannot_assign_own_errand: Le créateur de la course ne peut pas s'auto-attribuer sa propre course.",
        );
      }

      // Idempotence confirmée : déjà attribuée à cet utilisateur
      if (currentShopper == shopperId) {
        return true;
      }

      // Concurrence : déjà prise par un tiers
      if (currentShopper != null && currentShopper.toString().isNotEmpty) {
        throw StateError(
          "already_assigned: Cette course a déjà été attribuée à un autre shoppeur.",
        );
      }

      // Machine d'état : doit être pending
      if (currentStatus != ErrandStatus.pending) {
        throw StateError(
          "errand_not_available: La course est au statut '$currentStatus' et ne peut plus être acceptée.",
        );
      }

      final updateData = <String, dynamic>{
        'shopperId': shopperId,
        'status': ErrandStatus.accepted,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (agreedCommission != null) {
        updateData['negotiatedCommission'] = agreedCommission;
      }

      transaction.update(docRef, updateData);
      return true;
    });

    if (result && _dispatchService != null) {
      _dispatchService.notify(
        errandId: errandId,
        eventType: 'errand_accepted',
      ).catchError((e) {
        debugPrint('ErrandService: errand_accepted notification error: $e');
        return false;
      });
    }

    return result;
  }

  /// Enregistre le refus individuel d'un shoppeur pour une course.
  /// Exclut le shoppeur des vagues ultérieures sans modifier la course pour les autres.
  Future<void> declineErrand({
    required String errandId,
    required String shopperId,
  }) async {
    await _errandsRef.doc(errandId).update({
      'declinedShoppers': FieldValue.arrayUnion([shopperId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================
  // 5. ANNULATION ATOMIQUE CÔTÉ CLIENT
  // ==========================================

  /// Annulation atomique d'une course côté client.
  /// Seul le client propriétaire peut annuler sa propre course.
  /// Seuls les statuts autorisés (pending, accepted) peuvent être annulés.
  /// Empêche toute condition de concurrence avec l'attribution d'un shoppeur via transaction Firestore.
  Future<void> cancelErrand({
    required String errandId,
    required String clientId,
    String? reason,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final docRef = _errandsRef.doc(errandId);
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw StateError("Course introuvable: $errandId");
      }

      final data = snapshot.data()!;
      final errandClientId = data['clientId'];
      final currentStatus = data['status'];

      // Seul le client propriétaire peut annuler sa commande
      if (errandClientId != clientId) {
        throw StateError(
          "unauthorized: Seul le client propriétaire peut annuler cette commande.",
        );
      }

      // Idempotence : si déjà annulée
      if (currentStatus == ErrandStatus.cancelled) {
        return;
      }

      // Règle métier : une course clôturée ne peut pas être annulée
      if (currentStatus == ErrandStatus.completed) {
        throw StateError(
          "cannot_cancel_completed: Impossible d'annuler une course déjà terminée.",
        );
      }

      // Contrôle de transition légitime
      if (!ErrandStatus.isValidTransition(currentStatus, ErrandStatus.cancelled)) {
        throw StateError(
          "invalid_transition: Impossible d'annuler une course au statut '$currentStatus'.",
        );
      }

      transaction.update(docRef, {
        'status': ErrandStatus.cancelled,
        'cancellationReason': reason ?? 'Annulée par le client',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': clientId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (_dispatchService != null) {
      _dispatchService.notify(
        errandId: errandId,
        eventType: 'errand_cancelled',
      ).catchError((e) {
        debugPrint('ErrandService: errand_cancelled notification error: $e');
        return false;
      });
    }
  }
}
