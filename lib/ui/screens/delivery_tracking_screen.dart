import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/errand_model.dart';
import '../../services/errand_service.dart';
import '../../services/map_tracking_service.dart';
import '../../services/realtime_tracking_service.dart';
import '../theme/app_theme.dart';

/// Section 5 : SUIVI GPS TEMPS RÉEL (RTDB) ET REMISE SÉCURISÉE (Handshake).
/// Architecture Spark optimisée :
/// - Les coordonnées GPS temps réel sont diffusées et lues exclusivement via Firebase Realtime Database.
/// - Throttling automatique (intervalle min 8 secondes / 10 mètres) pour respecter le quota Spark gratuit.
/// - Purge et désinscription systématiques lors de la clôture de la mission.
/// - Gestion des états : chargement, GPS indisponible, réseau dégradé et mission terminée.
class DeliveryTrackingScreen extends StatefulWidget {
  final ErrandModel errand;
  final ErrandService errandService;
  final RealtimeTrackingService? trackingService;
  final MapTrackingService? mapTrackingService;
  final bool isShopperView;

  const DeliveryTrackingScreen({
    super.key,
    required this.errand,
    required this.errandService,
    this.trackingService,
    this.mapTrackingService,
    this.isShopperView = false,
  });

  @override
  State<DeliveryTrackingScreen> createState() => _DeliveryTrackingScreenState();
}

class _DeliveryTrackingScreenState extends State<DeliveryTrackingScreen> {
  late final RealtimeTrackingService _trackingService;
  late final MapTrackingService _mapTrackingService;

  bool _isNetworkOnline = true;
  bool _isGpsAvailable = true;
  bool _isLoadingGps = false;
  LatLng? _liveShopperPosition;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<LatLng?>? _rtdbSubscription;
  Timer? _countdownTimer;

  int _pinExpirationSeconds = 900; // 15 minutes d'expiration du code
  bool _cashPaymentConfirmed = false;
  bool _isCompleting = false;

  @override
  void initState() {
    super.initState();
    _trackingService = widget.trackingService ?? RealtimeTrackingService();
    _mapTrackingService = widget.mapTrackingService ?? MapTrackingService();

    // Initialisation de la position initiale
    if (widget.errand.shopperLocation != null) {
      _liveShopperPosition = LatLng(
        widget.errand.shopperLocation!.latitude,
        widget.errand.shopperLocation!.longitude,
      );
    }

    _startCountdown();
    _initializeLiveTracking();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _positionSubscription?.cancel();
    _rtdbSubscription?.cancel();
    super.dispose();
  }

  /// Initialise le flux de position adapté au rôle (Shopper diffuseur vs Client observateur).
  Future<void> _initializeLiveTracking() async {
    if (widget.isShopperView) {
      // 1. Vue Shopper : Demande de permission et streaming matériel GPS
      setState(() => _isLoadingGps = true);
      final hasPermission = await _mapTrackingService
          .checkAndRequestPermission();

      if (!hasPermission) {
        if (mounted) {
          setState(() {
            _isGpsAvailable = false;
            _isLoadingGps = false;
          });
        }
        return;
      }

      final positionStream = _mapTrackingService.startMissionTracking(
        errandId: widget.errand.errandId,
      );

      if (positionStream != null) {
        _positionSubscription = positionStream.listen(
          (pos) async {
            if (!mounted) return;
            final latLng = LatLng(pos.latitude, pos.longitude);
            setState(() {
              _liveShopperPosition = latLng;
              _isGpsAvailable = true;
              _isLoadingGps = false;
            });

            // Diffusion vers Realtime Database avec throttling Spark 8s
            final shopperUid = widget.errand.shopperId;
            if (shopperUid != null && shopperUid.isNotEmpty) {
              await _trackingService.pushActiveErrandLocation(
                errandId: widget.errand.errandId,
                shopperId: shopperUid,
                clientId: widget.errand.clientId,
                latitude: pos.latitude,
                longitude: pos.longitude,
              );
            }
          },
          onError: (_) {
            if (mounted) {
              setState(() => _isGpsAvailable = false);
            }
          },
        );
      }
    } else {
      // 2. Vue Client : Écoute en direct du nœud RTDB de la course
      _rtdbSubscription = _trackingService
          .streamActiveErrandLocation(widget.errand.errandId)
          .listen((liveCoords) {
            if (mounted && liveCoords != null) {
              setState(() {
                _liveShopperPosition = liveCoords;
              });
            }
          });
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_pinExpirationSeconds > 0) {
        if (mounted) {
          setState(() => _pinExpirationSeconds--);
        }
      } else {
        timer.cancel();
      }
    });
  }

  String get _formattedExpiration {
    final mins = (_pinExpirationSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_pinExpirationSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _openHandshakeSheet(ErrandModel errand) {
    final pinInputCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Remise Sécurisée & Paiement',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetCtx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Vue Client : Présente son QR code et son PIN au shoppeur
                if (!widget.isShopperView) ...[
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data:
                            '9DILI_DELIVERY:${errand.errandId}:${errand.securePin}',
                        version: QrVersions.auto,
                        size: 160.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.violetSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'VOTRE CODE PIN DE REMISE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.violetAccent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          errand.securePin,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Expire dans : $_formattedExpiration',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Communiquez ce code uniquement lors de la réception des articles et du ticket original.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ] else ...[
                  // Vue Shopper : Saisie du PIN fourni par le client
                  const Text(
                    'Code PIN fourni par le client :',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pinInputCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: '••••',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Confirmation de l'encaissement en espèces et remise ticket
                  CheckboxListTile(
                    title: Text(
                      'Paiement espèces encaissé (${errand.totalAmount.toStringAsFixed(2)} DA) & Ticket remis',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Montant ticket + Commission négociée',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    value: _cashPaymentConfirmed,
                    activeColor: AppTheme.accentGreen,
                    onChanged: (val) {
                      setSheetState(() => _cashPaymentConfirmed = val ?? false);
                    },
                  ),
                  const SizedBox(height: 16),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cashPaymentConfirmed
                          ? AppTheme.accentGreen
                          : Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: (!_cashPaymentConfirmed || _isCompleting)
                        ? null
                        : () async {
                            final inputPin = pinInputCtrl.text.trim();
                            if (inputPin.length != 4) return;

                            setSheetState(() => _isCompleting = true);
                            final result = await widget.errandService
                                .completeErrandWithPin(
                                  errand.errandId,
                                  inputPin,
                                );

                            if (mounted && sheetCtx.mounted) {
                              setSheetState(() => _isCompleting = false);
                              Navigator.pop(sheetCtx);

                              if (!mounted) return;

                              if (result.isSuccess) {
                                // Nettoyage de l'abonnement et de la position RTDB
                                await _trackingService.cleanUpActiveErrand(
                                  errand.errandId,
                                );
                                await _mapTrackingService.stopTracking();

                                if (!mounted) return;

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: AppTheme.accentGreen,
                                    content: Text(
                                      'Course clôturée et paiement validé ! 🎉',
                                    ),
                                  ),
                                );
                                Navigator.of(context)
                                    .popUntil((route) => route.isFirst);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppTheme.errorRed,
                                    content: Text(result.message),
                                  ),
                                );
                              }
                            }
                          },
                    child: _isCompleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Valider la remise en main propre'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _makePhoneCall(String? phone) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.primaryOrange,
        content: Text(
          phone != null && phone.isNotEmpty
              ? 'Appel vers le correspondant : $phone 📞'
              : 'Lancement de l\'appel sécurisé via le relais 9DILI 📞',
        ),
      ),
    );
  }

  void _sendMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppTheme.secondaryNavy,
        content: Text('Ouverture du chat sécurisé 9DILI 💬'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ErrandModel?>(
      stream: widget.errandService.streamErrand(widget.errand.errandId),
      builder: (context, snapshot) {
        final errand = snapshot.data ?? widget.errand;

        // Position par défaut sur Alger centre si non géolocalisé
        final shopperPos =
            _liveShopperPosition ??
            (errand.shopperLocation != null
                ? LatLng(
                    errand.shopperLocation!.latitude,
                    errand.shopperLocation!.longitude,
                  )
                : const LatLng(36.7538, 3.0588));

        final destPos = errand.deliveryGeoPoint != null
            ? LatLng(
                errand.deliveryGeoPoint!.latitude,
                errand.deliveryGeoPoint!.longitude,
              )
            : const LatLng(36.7450, 3.0300);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Suivi en Direct 📍'),
            actions: [
              IconButton(
                icon: Icon(
                  _isNetworkOnline ? Icons.cloud_done : Icons.cloud_off,
                  color: _isNetworkOnline
                      ? AppTheme.accentGreen
                      : AppTheme.warningOrange,
                ),
                tooltip: _isNetworkOnline ? 'Synchronisé' : 'Mode hors-ligne',
                onPressed: () {
                  setState(() => _isNetworkOnline = !_isNetworkOnline);
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // 1. Bandeau alerte réseau dégradé
              if (!_isNetworkOnline)
                Container(
                  color: AppTheme.warningOrange.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.wifi_off,
                        size: 16,
                        color: AppTheme.warningOrange,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Connexion réseau instable — Données et PIN synchronisés localement.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.warningOrange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 2. Bandeau alerte GPS indisponible
              if (!_isGpsAvailable && widget.isShopperView)
                Container(
                  color: AppTheme.errorRed.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.location_off,
                        size: 16,
                        color: AppTheme.errorRed,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Position GPS indisponible — Veuillez activer la localisation pour diffuser votre trajet.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.errorRed,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 3. Carte temps réel OpenStreetMap
              Expanded(
                flex: 5,
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFE2E8F0),
                  child: Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: shopperPos,
                          initialZoom: 14.5,
                        ),
                        children: [
                          MapTrackingService.buildOsmTileLayer(),
                          MapTrackingService.buildTrackingMarkers(
                            shopperPosition: shopperPos,
                            destinationPosition: destPos,
                          ),
                        ],
                      ),

                      // Indicateur de chargement GPS initial
                      if (_isLoadingGps)
                        Positioned(
                          top: 16,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primaryOrange,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Signal GPS...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Attribution légale OpenStreetMap
                      Positioned(
                        bottom: 6,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '© OpenStreetMap contributors',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      // Badge ETA (Temps estimé)
                      if (!_isLoadingGps)
                        Positioned(
                          top: 16,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.timer,
                                  size: 18,
                                  color: AppTheme.primaryOrange,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'ETA : ${errand.etaMinutes ?? 12} min',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Boutons d'action rapides : Appeler & Message
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Row(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'callBtn',
                              backgroundColor: AppTheme.primaryOrange,
                              foregroundColor: Colors.white,
                              onPressed: () => _makePhoneCall(
                                widget.isShopperView
                                    ? errand.clientPhone
                                    : errand.shopperPhone,
                              ),
                              child: const Icon(Icons.phone),
                            ),
                            const SizedBox(width: 8),
                            FloatingActionButton.small(
                              heroTag: 'msgBtn',
                              backgroundColor: AppTheme.secondaryNavy,
                              foregroundColor: Colors.white,
                              onPressed: _sendMessage,
                              child: const Icon(Icons.chat),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Panneau inférieur : Progression & Handshake
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Progression des étapes
                      _buildStepProgress(errand.status),
                      const Spacer(),

                      // Récapitulatif financier
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.violetSurface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'Total à régler en espèces :',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${errand.totalAmount.toStringAsFixed(2)} DA',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Bouton d'ouverture du Handshake (QR / PIN)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryOrange,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _openHandshakeSheet(errand),
                        icon: const Icon(Icons.qr_code),
                        label: Text(
                          widget.isShopperView
                              ? 'Valider le PIN de Remise'
                              : 'Afficher mon QR Code / PIN',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepProgress(String status) {
    final steps = [
      'Acceptée',
      'En magasin',
      'Ticket validé',
      'En route',
      'Terminée',
    ];
    int currentIndex = 0;
    if (status == ErrandStatus.shopping) currentIndex = 1;
    if (widget.errand.isReceiptValidated) currentIndex = 2;
    if (status == ErrandStatus.delivering) currentIndex = 3;
    if (status == ErrandStatus.completed) currentIndex = 4;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(steps.length, (index) {
        final isDone = index <= currentIndex;
        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: isDone
                    ? AppTheme.accentGreen
                    : const Color(0xFFE2E8F0),
                child: Icon(
                  isDone ? Icons.check : Icons.circle,
                  size: 14,
                  color: isDone ? Colors.white : AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[index],
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                  color: isDone ? AppTheme.textDark : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
