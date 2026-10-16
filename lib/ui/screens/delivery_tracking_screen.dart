import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/errand_model.dart';
import '../../services/errand_service.dart';
import '../../services/map_tracking_service.dart';
import '../theme/app_theme.dart';

/// Section 5 : SUIVI GPS ET REMISE (Delivery Tracking & Handshake).
/// Inclut :
/// - Carte/Radar visuel de position
/// - Temps estimé (ETA)
/// - Progression de la course
/// - Boutons d'appel et de message direct
/// - États d'actualisation réseau et résilience hors-ligne
/// - Remise sécurisée : QR Code, Code PIN à 4 chiffres, Expiration, Paiement en espèces
class DeliveryTrackingScreen extends StatefulWidget {
  final ErrandModel errand;
  final ErrandService errandService;
  final bool isShopperView;

  const DeliveryTrackingScreen({
    super.key,
    required this.errand,
    required this.errandService,
    this.isShopperView = false,
  });

  @override
  State<DeliveryTrackingScreen> createState() => _DeliveryTrackingScreenState();
}

class _DeliveryTrackingScreenState extends State<DeliveryTrackingScreen> {
  bool _isNetworkOnline = true;
  Timer? _countdownTimer;
  int _pinExpirationSeconds = 900; // 15 minutes d'expiration du code
  bool _cashPaymentConfirmed = false;
  bool _isCompleting = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_pinExpirationSeconds > 0) {
        setState(() => _pinExpirationSeconds--);
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
                        data: '9DILI:${errand.errandId}:${errand.securePin}',
                        version: QrVersions.auto,
                        size: 160.0,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppTheme.primaryOrange,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.violetSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'PIN : ${errand.securePin}',
                        style: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 6,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.violetAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Expire dans : $_formattedExpiration',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Instructions : Présentez ce QR code ou dictez le code PIN à votre shoppeur pour valider la réception et lui remettre le montant en espèces.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ]
                // Vue Shoppeur : Valide le PIN ou scanne le QR
                else ...[
                  const Text(
                    'Saisissez le code PIN à 4 chiffres communiqué par le client :',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinInputCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: '••••',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Confirmation de paiement en espèces
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Paiement en espèces reçu (${errand.totalAmount.toStringAsFixed(2)} DA)',
                      style: const TextStyle(
                        fontSize: 13,
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: result.isSuccess
                                      ? AppTheme.accentGreen
                                      : AppTheme.errorRed,
                                  content: Text(
                                    result.isSuccess
                                        ? 'Course clôturée et paiement validé ! 🎉'
                                        : result.message,
                                  ),
                                ),
                              );

                              if (result.isSuccess) {
                                Navigator.of(context)
                                    .popUntil((route) => route.isFirst);
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
              ? 'Appel vers le client/shoppeur : $phone 📞'
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
              // Bandeau réseau / sync
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

              // Carte / Radar Simulation
              Expanded(
                flex: 5,
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFE2E8F0),
                  child: Stack(
                    children: [
                      // Carte OpenStreetMap dynamique via FlutterMap
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: errand.shopperLocation != null
                              ? LatLng(
                                  errand.shopperLocation!.latitude,
                                  errand.shopperLocation!.longitude,
                                )
                              : const LatLng(36.7538, 3.0588), // Alger centre
                          initialZoom: 14.5,
                        ),
                        children: [
                          MapTrackingService.buildOsmTileLayer(),
                          MapTrackingService.buildTrackingMarkers(
                            shopperPosition: errand.shopperLocation != null
                                ? LatLng(
                                    errand.shopperLocation!.latitude,
                                    errand.shopperLocation!.longitude,
                                  )
                                : const LatLng(36.7538, 3.0588),
                            destinationPosition: const LatLng(36.7450, 3.0300),
                          ),
                        ],
                      ),

                      // Attribution légale OpenStreetMap obligatoire
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

              // Panneau inférieur : Progression & Handshake
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
                            const Text(
                              'Total à régler en espèces :',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
        return Column(
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
              style: TextStyle(
                fontSize: 9,
                fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                color: isDone ? AppTheme.textDark : AppTheme.textMuted,
              ),
            ),
          ],
        );
      }),
    );
  }
}
