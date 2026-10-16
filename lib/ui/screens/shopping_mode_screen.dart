import 'package:flutter/material.dart';

import '../../models/errand_model.dart';
import '../../models/errand_item_model.dart';
import '../../services/errand_service.dart';
import '../theme/app_theme.dart';
import 'receipt_screen.dart';

/// Section 3 : MODE EN MAGASIN (Shopping Mode).
/// Conçu pour une utilisation ultra-rapide à une seule main.
/// Statuts articles :
/// - Trouvé : vert
/// - Remplacé : orange
/// - Rupture : rouge
class ShoppingModeScreen extends StatefulWidget {
  final ErrandModel errand;
  final ErrandService errandService;

  const ShoppingModeScreen({
    super.key,
    required this.errand,
    required this.errandService,
  });

  @override
  State<ShoppingModeScreen> createState() => _ShoppingModeScreenState();
}

class _ShoppingModeScreenState extends State<ShoppingModeScreen> {
  void _openReplacementDialog(ErrandItemModel item) {
    final noteCtrl = TextEditingController(text: item.replacementNote ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Remplacement pour ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Précisez l\'article de remplacement proposé au client :',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom / Marque / Prix du substitut',
                hintText: 'Ex: Marque Candia à 120 DA au lieu de Soummam',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warningOrange,
            ),
            onPressed: () async {
              final updated = item.copyWith(
                status: ErrandItemStatus.replaced,
                replacementNote: noteCtrl.text.trim(),
              );
              await widget.errandService.updateItem(
                widget.errand.errandId,
                updated,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Confirmer le remplacement'),
          ),
        ],
      ),
    );
  }

  void _goToReceiptScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          errand: widget.errand,
          errandService: widget.errandService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Mode En Magasin 🛒', style: TextStyle(fontSize: 16)),
            Text(
              widget.errand.storeName,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<ErrandItemModel>>(
        stream: widget.errandService.streamItems(widget.errand.errandId),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];

          final foundCount = items
              .where((i) => i.status == ErrandItemStatus.found)
              .length;
          final replacedCount = items
              .where((i) => i.status == ErrandItemStatus.replaced)
              .length;
          final unavailableCount = items
              .where((i) => i.status == ErrandItemStatus.unavailable)
              .length;
          final allProcessed =
              items.isNotEmpty &&
              (foundCount + replacedCount + unavailableCount) == items.length;

          return Column(
            children: [
              // Barre de progression rapide (Une main)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: AppTheme.violetSurface,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildQuickMetric(
                      'Trouvés',
                      foundCount,
                      AppTheme.accentGreen,
                    ),
                    _buildQuickMetric(
                      'Remplacés',
                      replacedCount,
                      AppTheme.warningOrange,
                    ),
                    _buildQuickMetric(
                      'Rupture',
                      unavailableCount,
                      AppTheme.errorRed,
                    ),
                    _buildQuickMetric(
                      'Total',
                      items.length,
                      AppTheme.secondaryNavy,
                    ),
                  ],
                ),
              ),

              // Liste des articles
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('Aucun article listé'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: _getStatusBorderColor(item.status),
                                width: 1.5,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.violetSurface,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)} ${item.unit}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.violetAccent,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (item.notes.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Note client : ${item.notes}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textMuted,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                  if (item.replacementNote != null &&
                                      item.replacementNote!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Substitut : ${item.replacementNote}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.warningOrange,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),

                                  // 3 Statuts rapides à une seule main
                                  Row(
                                    children: [
                                      // Trouvé (Vert)
                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: item.isFound
                                                ? AppTheme.accentGreen
                                                : const Color(0xFFF1F5F9),
                                            foregroundColor: item.isFound
                                                ? Colors.white
                                                : AppTheme.textDark,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                          ),
                                          onPressed: () {
                                            widget.errandService.updateItem(
                                              widget.errand.errandId,
                                              item.copyWith(
                                                status: ErrandItemStatus.found,
                                                replacementNote: null,
                                              ),
                                            );
                                          },
                                          child: const Text(
                                            'Trouvé',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Remplacé (Orange)
                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: item.isReplaced
                                                ? AppTheme.warningOrange
                                                : const Color(0xFFF1F5F9),
                                            foregroundColor: item.isReplaced
                                                ? Colors.white
                                                : AppTheme.textDark,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                          ),
                                          onPressed: () =>
                                              _openReplacementDialog(item),
                                          child: const Text(
                                            'Remplacer',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Rupture (Rouge)
                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: item.isUnavailable
                                                ? AppTheme.errorRed
                                                : const Color(0xFFF1F5F9),
                                            foregroundColor: item.isUnavailable
                                                ? Colors.white
                                                : AppTheme.textDark,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                          ),
                                          onPressed: () {
                                            widget.errandService.updateItem(
                                              widget.errand.errandId,
                                              item.copyWith(
                                                status: ErrandItemStatus
                                                    .unavailable,
                                                replacementNote: null,
                                              ),
                                            );
                                          },
                                          child: const Text(
                                            'Rupture',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Bouton passage en caisse
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: allProcessed
                          ? AppTheme.primaryOrange
                          : AppTheme.secondaryNavy,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _goToReceiptScreen,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text(
                      'Passer au Ticket de Caisse 🧾',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickMetric(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  Color _getStatusBorderColor(String status) {
    switch (status) {
      case ErrandItemStatus.found:
        return AppTheme.accentGreen;
      case ErrandItemStatus.replaced:
        return AppTheme.warningOrange;
      case ErrandItemStatus.unavailable:
        return AppTheme.errorRed;
      default:
        return const Color(0xFFE2E8F0);
    }
  }
}
