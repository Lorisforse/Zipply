import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:ziply_app/core/theme/app_colors.dart';

// Palette (alias di AppColors).
const Color _kBg     = AppColors.bg;
const Color _kBorder = AppColors.border;
const Color _kText   = AppColors.text;
const Color _kDim    = AppColors.dim;
const Color _kAccent = AppColors.accent;

/// [MOBILE] UT.13 — Scanner QR per lo sblocco del mezzo.
/// Apre la fotocamera, legge il QR stampato sul mezzo e restituisce al
/// chiamante (la mappa) il valore letto via [Navigator.pop]; null se l'utente
/// chiude senza inquadrare nulla.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  /// Apre lo scanner a schermo intero e restituisce il contenuto del QR letto,
  /// oppure null se l'utente annulla.
  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
  }

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  // Evita di restituire più volte lo stesso scan mentre la rotta si chiude.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        // Riempie lo schermo: senza questo lo Stack si dimensionerebbe sull'unico
        // figlio non-Positioned (la barra in alto) e la camera resterebbe un
        // quadratino in alto.
        fit: StackFit.expand,
        children: [
          // Anteprima fotocamera a schermo intero.
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) => _CameraError(error: error),
            ),
          ),
          // Velo scuro attorno al riquadro di scansione.
          const Positioned.fill(child: _ScannerOverlay()),
          // Top bar: wordmark + chiudi.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ZIPLY',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: _kAccent,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close, color: _kText),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Istruzione in basso.
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Inquadra il codice QR sul mezzo per sbloccarlo',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontSize: 15,
                height: 1.4,
                color: _kText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Riquadro di scansione con angoli accent ────────────────────────────────
class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          border: Border.all(color: _kAccent, width: 3),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

// ── Errore fotocamera (permesso negato / non disponibile) ──────────────────
class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: _kBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: _kDim, size: 48),
              const SizedBox(height: 16),
              Text(
                permissionDenied
                    ? 'Permesso fotocamera negato. Abilitalo dalle impostazioni per scansionare il QR.'
                    : 'Fotocamera non disponibile',
                textAlign: TextAlign.center,
                style: GoogleFonts.barlow(fontSize: 15, color: _kText),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kDim,
                    side: const BorderSide(color: _kBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text(
                    'CHIUDI',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: _kDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
