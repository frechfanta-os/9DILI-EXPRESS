import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Sélecteur (Toggle) haute fidélité Client / Shopper conforme à la maquette officielle.
/// - Mode Client  : Fond vert (#10B981), pilule blanche active sur « • Client », texte blanc « Shopper ».
/// - Mode Shopper : Fond orange (#FF6D00), texte blanc « Client », pilule blanche active sur « • Shopper ».
/// - Animation fluide du curseur (250 ms) avec retour haptique.
class ClientShopperToggle extends StatelessWidget {
  final AppMode currentMode;
  final ValueChanged<AppMode> onModeChanged;
  final double height;
  final double maxWidth;

  const ClientShopperToggle({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    this.height = 48.0,
    this.maxWidth = 340.0,
  });

  bool get isClient => currentMode == AppMode.client;

  @override
  Widget build(BuildContext context) {
    final activeColor = isClient
        ? AppTheme.clientGreen
        : AppTheme.shopperOrange;

    return Semantics(
      label:
          'Sélecteur de mode : ${isClient ? "Client actif" : "Shopper actif"}',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          height: height,
          padding: const EdgeInsets.all(4.0),
          decoration: BoxDecoration(
            color: activeColor,
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: activeColor, width: 2.0),
            boxShadow: [
              BoxShadow(
                color: activeColor.withValues(alpha: 0.28),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Curseur blanc animé glissant (White sliding pill)
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                alignment: isClient
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular((height - 8) / 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Cibles tactiles et libellés
              Row(
                children: [
                  // Onglet Client
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(height / 2),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onModeChanged(AppMode.client);
                        },
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isClient) ...[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.clientGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                'Client',
                                style: TextStyle(
                                  color: isClient
                                      ? AppTheme.clientGreen
                                      : Colors.white,
                                  fontWeight: isClient
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Onglet Shopper
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(height / 2),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onModeChanged(AppMode.shopper);
                        },
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!isClient) ...[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.shopperOrange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                'Shopper',
                                style: TextStyle(
                                  color: !isClient
                                      ? AppTheme.shopperOrange
                                      : Colors.white,
                                  fontWeight: !isClient
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
