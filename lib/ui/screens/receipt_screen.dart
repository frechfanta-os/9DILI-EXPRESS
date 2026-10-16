import 'package:flutter/material.dart';

import '../../models/errand_model.dart';
import '../../services/errand_service.dart';
import '../theme/app_theme.dart';
import 'delivery_tracking_screen.dart';

/// Section 4 : TICKET DE CAISSE.
/// Règle absolue : Le passage au statut « En route » est bloqué
/// tant que le justificatif photo et le montant exact ne sont pas enregistrés et validés.
/// Formule obligatoire : Total à payer = Montant du ticket + Commission négociée.
class ReceiptScreen extends StatefulWidget {
  final ErrandModel errand;
  final ErrandService errandService;

  const ReceiptScreen({
    super.key,
    required this.errand,
    required this.errandService,
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final _amountController = TextEditingController();
  String? _photoUrl;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.errand.ticketAmount != null && widget.errand.ticketAmount! > 0) {
      _amountController.text = widget.errand.ticketAmount!.toStringAsFixed(2);
    }
    _photoUrl = widget.errand.ticketPhotoUrl;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // Simulation capture photo haute fidélité (compatible caméra ou URL de preuve)
  void _takeReceiptPhoto() {
    setState(() {
      _photoUrl = 'https://images.unsplash.com/photo-1554415707-9e4966668834?auto=format&fit=crop&w=800&q=80';
      _errorMessage = null;
    });
  }

  void _retakePhoto() {
    setState(() {
      _photoUrl = null;
    });
  }

  double get _ticketAmount =>
      double.tryParse(_amountController.text.trim()) ?? 0.0;
  double get _commission => widget.errand.negotiatedCommission;
  double get _totalToPay => _ticketAmount + _commission; // Formule obligatoire

  bool get _isValidated =>
      _ticketAmount > 0 && _photoUrl != null && _photoUrl!.isNotEmpty;

  Future<void> _submitAndStartDelivering() async {
    final amount = double.tryParse(_amountController.text.trim());

    if (_photoUrl == null || _photoUrl!.isEmpty) {
      setState(() {
        _errorMessage = 'Veuillez prendre une photo nette du ticket de caisse.';
      });
      return;
    }

    if (amount == null || amount <= 0) {
      setState(() {
        _errorMessage = 'Veuillez saisir le montant exact payé en caisse.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      // 1. Enregistrement du montant et du justificatif
      await widget.errandService.submitTicket(
        errandId: widget.errand.errandId,
        ticketAmount: amount,
        ticketPhotoUrl: _photoUrl!,
      );

      // 2. Déblocage et passage en route (delivering)
      await widget.errandService.startDelivering(widget.errand.errandId);

      if (mounted) {
        final updatedErrand = widget.errand.copyWith(
          ticketAmount: amount,
          ticketPhotoUrl: _photoUrl,
          status: ErrandStatus.delivering,
        );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DeliveryTrackingScreen(
              errand: updatedErrand,
              errandService: widget.errandService,
              isShopperView: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Justificatif de Caisse 🧾')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Alerte de blocage
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isValidated
                    ? AppTheme.accentGreen.withValues(alpha: 0.1)
                    : AppTheme.warningOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isValidated
                      ? AppTheme.accentGreen.withValues(alpha: 0.3)
                      : AppTheme.warningOrange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isValidated ? Icons.check_circle : Icons.lock_clock,
                    color: _isValidated
                        ? AppTheme.accentGreen
                        : AppTheme.warningOrange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isValidated
                          ? 'Justificatif conforme. Vous pouvez partir en livraison.'
                          : 'Le passage au statut « En route » est bloqué tant que le ticket et le montant ne sont pas validés.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isValidated
                            ? AppTheme.accentGreen
                            : AppTheme.warningOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: AppTheme.errorRed,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Zone Photo du ticket
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Photo du ticket de caisse *',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Assurez-vous que le total et les articles sont parfaitement lisibles.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 12),
                    if (_photoUrl == null) ...[
                      GestureDetector(
                        onTap: _takeReceiptPhoto,
                        child: Container(
                          height: 180,
                          decoration: BoxDecoration(
                            color: AppTheme.violetSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.violetAccent,
                              width: 1.5,
                            ),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt,
                                size: 48,
                                color: AppTheme.violetAccent,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Appuyez pour prendre la photo du ticket',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.violetAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          _photoUrl!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                height: 160,
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: Text(
                                    'Photo du ticket enregistrée (mode aperçu)',
                                  ),
                                ),
                              ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _retakePhoto,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reprendre la photo (si illisible)'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Saisie du montant et formule de calcul automatique
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Détail Financier Transparent',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const Divider(height: 20),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Montant exact payé au ticket (DA) *',
                        hintText: 'Ex: 2450.00',
                        prefixIcon: Icon(Icons.receipt),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Lignes récapitulatives
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Montant réel du ticket :'),
                        Text(
                          '${_ticketAmount.toStringAsFixed(2)} DA',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Commission négociée :'),
                        Text(
                          '+ ${_commission.toStringAsFixed(2)} DA',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryOrange,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    // Total à encaisser (Formule obligatoire)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.violetSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TOTAL À ENCAISSER',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.violetAccent,
                                ),
                              ),
                              Text(
                                '(Ticket + Commission)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${_totalToPay.toStringAsFixed(2)} DA',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Bouton bloquant de départ en livraison
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isValidated
                    ? AppTheme.accentGreen
                    : Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isSaving ? null : _submitAndStartDelivering,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sports_motorsports),
              label: Text(
                _isValidated
                    ? 'Valider le ticket et Partir en livraison 🚀'
                    : 'Bloqué (Ticket et Montant requis)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
