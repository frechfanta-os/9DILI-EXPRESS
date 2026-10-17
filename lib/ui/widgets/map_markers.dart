import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Marqueurs cartographiques vectoriels et Canvas pour 9DILI EXPRESS.
/// Conçus pour être utilisés à la fois comme widgets Flutter (flutter_map / MapLibre WidgetMarker)
/// et comme bitmaps rasterisés (ui.Image / PNG bytes) pour MapLibre SymbolLayer (`addImage`).

class ShopperMarkerWidget extends StatelessWidget {
  final double? heading;
  final bool isMoving;
  final double size;

  const ShopperMarkerWidget({
    super.key,
    this.heading,
    this.isMoving = false,
    this.size = 46.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo de pulsation animé ou d'accentuation
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryOrange.withValues(alpha: 0.25),
            ),
          ),
          // Disque principal du Shopper
          Container(
            width: size * 0.76,
            height: size * 0.76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryOrange,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Transform.rotate(
              angle: heading != null ? (heading! * 3.1415926535 / 180) : 0,
              child: const Icon(
                Icons.delivery_dining,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ClientDestinationMarkerWidget extends StatelessWidget {
  final String? addressSnippet;
  final double size;

  const ClientDestinationMarkerWidget({
    super.key,
    this.addressSnippet,
    this.size = 46.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + (addressSnippet != null ? 20 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size * 0.8,
            height: size * 0.8,
            decoration: BoxDecoration(
              color: AppTheme.accentGreen,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.home_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          if (addressSnippet != null && addressSnippet!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceWhite,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Text(
                addressSnippet!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StoreMarkerWidget extends StatelessWidget {
  final String storeName;
  final double size;

  const StoreMarkerWidget({
    super.key,
    required this.storeName,
    this.size = 46.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size * 0.8,
            height: size * 0.8,
            decoration: BoxDecoration(
              color: AppTheme.violetAccent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              storeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Générateur d'images PNG en mémoire via [CustomPainter] et [ui.PictureRecorder].
/// Permet de pré-générer les icônes nécessaires à MapLibre Native (`controller.addImage()`)
/// sans dépendre du cycle de vie des widgets.
class MapMarkerBitmapGenerator {
  /// Génère le bitmap PNG de l'icône Shopper avec orientation.
  static Future<Uint8List> generateShopperMarkerBytes({
    int width = 96,
    int height = 96,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    final center = Offset(width / 2, height / 2);

    // Halo extérieur
    final haloPaint = Paint()
      ..color = const Color(0x40FF6B00)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, width * 0.46, haloPaint);

    // Disque principal
    final circlePaint = Paint()
      ..color = const Color(0xFFFF6B00)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, width * 0.35, circlePaint);

    // Bordure blanche
    final strokePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, width * 0.35, strokePaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Génère le bitmap PNG de l'icône Destination Client.
  static Future<Uint8List> generateDestinationMarkerBytes({
    int width = 96,
    int height = 96,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    final center = Offset(width / 2, height / 2);

    // Halo extérieur
    final haloPaint = Paint()
      ..color = const Color(0x4010B981)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, width * 0.46, haloPaint);

    // Disque principal
    final circlePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, width * 0.35, circlePaint);

    // Bordure blanche
    final strokePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, width * 0.35, strokePaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Charge les octets PNG d'un marqueur 3D depuis les assets pour MapLibre SymbolLayer.
  /// Si l'asset est introuvable, bascule sur le générateur Canvas de secours.
  static Future<Uint8List> loadAssetMarkerBytes(
    String assetPath, {
    bool isShopper = true,
  }) async {
    try {
      final byteData = await rootBundle.load(assetPath);
      return byteData.buffer.asUint8List();
    } catch (_) {
      return isShopper
          ? generateShopperMarkerBytes()
          : generateDestinationMarkerBytes();
    }
  }
}

/// Répertoire et constantes des marqueurs cartographiques 3D importés d'Android.
class MapMarkerAssets {
  static const String basePath = 'assets/images/map_markers/';

  // Marqueurs Shopper Orange Vif (différentes vues et véhicules 3D)
  static const String shopperOrange3D01 =
      '${basePath}MARQUEURS-MAPLIBRE-3D01.png';
  static const String shopperOrange3D02 =
      '${basePath}MARQUEURS-MAPLIBRE-3D02.png';
  static const String shopperOrange3D03 =
      '${basePath}MARQUEURS-MAPLIBRE-3D03.png';
  static const String shopperOrange3D04 =
      '${basePath}MARQUEURS-MAPLIBRE-3D04.png';
  static const String shopperOrange3D05 =
      '${basePath}MARQUEURS-MAPLIBRE-3D05.png';
  static const String shopperOrange3D07 =
      '${basePath}MARQUEURS-MAPLIBRE-3D07.png';
  static const String shopperOrange3D08 =
      '${basePath}MARQUEURS-MAPLIBRE-3D08.png';
  static const String shopperOrange3D11 =
      '${basePath}MARQUEURS-MAPLIBRE-3D11.png';

  // Marqueurs Vert Validation / Destination Client
  // NOTE DE SÉCURITÉ : Ce marqueur vert symbolise l'emplacement de livraison client,
  // et non la confirmation d'un paiement en espèces ou bancaire.
  static const String destinationGreen3D06 =
      '${basePath}MARQUEURS-MAPLIBRE-3D06.png';
  static const String clientLocationGreen3D10 =
      '${basePath}MARQUEURS-MAPLIBRE-3D10.png';

  // Marqueur Violet Supérette / Magasin de collecte
  static const String storeViolet3D09 =
      '${basePath}MARQUEURS-MAPLIBRE-3D09.png';
}

/// Marqueur 3D Shopper avec rotation dynamique selon le cap GPS et fallback vectoriel garanti.
class Shopper3DMarkerWidget extends StatelessWidget {
  final double? heading;
  final double size;
  final String assetPath;

  const Shopper3DMarkerWidget({
    super.key,
    this.heading,
    this.size = 54.0,
    this.assetPath = MapMarkerAssets.shopperOrange3D01,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo de pulsation orange Stitch
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryOrange.withValues(alpha: 0.22),
            ),
          ),
          // Rendu du PNG 3D avec orientation par cap
          Transform.rotate(
            angle: heading != null ? (heading! * 3.1415926535 / 180) : 0,
            child: Image.asset(
              assetPath,
              width: size * 0.82,
              height: size * 0.82,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback vectoriel transparent en cas d'asset manquant
                return ShopperMarkerWidget(heading: heading, size: size);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Marqueur 3D Destination Client (Vert Stitch) avec fallback vectoriel garanti.
/// Affiche l'adresse de destination sans ambiguïté sur le statut du paiement.
class ClientDestination3DMarkerWidget extends StatelessWidget {
  final String? addressSnippet;
  final double size;
  final String assetPath;

  const ClientDestination3DMarkerWidget({
    super.key,
    this.addressSnippet,
    this.size = 54.0,
    this.assetPath = MapMarkerAssets.destinationGreen3D06,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + (addressSnippet != null ? 22 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            assetPath,
            width: size * 0.85,
            height: size * 0.85,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return ClientDestinationMarkerWidget(
                addressSnippet: null,
                size: size,
              );
            },
          ),
          if (addressSnippet != null && addressSnippet!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceWhite,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Text(
                addressSnippet!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Marqueur 3D Magasin / Supérette (Violet Stitch) avec fallback vectoriel garanti.
class Store3DMarkerWidget extends StatelessWidget {
  final String storeName;
  final double size;
  final String assetPath;

  const Store3DMarkerWidget({
    super.key,
    required this.storeName,
    this.size = 54.0,
    this.assetPath = MapMarkerAssets.storeViolet3D09,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            assetPath,
            width: size * 0.85,
            height: size * 0.85,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return StoreMarkerWidget(storeName: storeName, size: size);
            },
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              storeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
