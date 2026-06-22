import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/data/models/vehicle_model.dart';
import 'package:ziply_app/services/route_service.dart';

/// UT.07 - Pannello anteprima percorso (mezzo scelto + km/min + CTA).
class RoutePreviewPanel extends StatelessWidget {
  const RoutePreviewPanel({
    super.key,
    required this.vehicle,
    required this.distanceKm,
    required this.durationMin,
    required this.estimatedCost,
    required this.fallback,
    required this.suggestion,
    required this.onContinue,
    required this.onClear,
  });

  final VehicleModel vehicle;
  final double distanceKm;
  final double durationMin;
  final double estimatedCost;
  final bool fallback;

  /// UT.08: tipologia consigliata per il tragitto (null = nessun consiglio).
  final SuggestedCategory? suggestion;

  final VoidCallback onContinue;
  final VoidCallback onClear;

  /// UT.08: Riga di consiglio. Conferma se il mezzo scelto e la tipologia
  /// consigliata, altrimenti suggerisce l'alternativa. null = niente consiglio.
  Widget? _consiglio() {
    final s = suggestion;
    if (s == null || s == SuggestedCategory.unknown) return null;
    final selected = vehicle.kind == VehicleType.car
        ? SuggestedCategory.auto
        : SuggestedCategory.biciScooter;
    final match = selected == s;
    final label = s == SuggestedCategory.auto ? "l'auto" : 'bici o monopattino';
    final text = match
        ? 'Ottima scelta: e il mezzo consigliato per questo tragitto.'
        : 'Per questo tragitto consigliamo $label.';
    final color = match ? AppColors.green : AppColors.accent;
    final icon = match ? Icons.check_circle_outline : Icons.lightbulb_outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.barlow(fontSize: 13, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mins = durationMin <= 0 ? 1 : durationMin.ceil();
    final title = vehicle.type.isEmpty ? 'Mezzo' : vehicle.type;
    final consiglio = _consiglio();
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 30,
            offset: Offset(0, -12),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PERCORSO VERSO LA DESTINAZIONE',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: AppColors.dim,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'COSTO STIMATO',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: AppColors.dim,
                        ),
                      ),
                      Text(
                        '€${estimatedCost.toStringAsFixed(2)}',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: AppColors.green,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${distanceKm.toStringAsFixed(1)} km · ~$mins min'
                        '${fallback ? ' ca.' : ''}',
                        style: GoogleFonts.barlow(fontSize: 12, color: AppColors.dim),
                      ),
                    ],
                  ),
                ],
              ),
              if (consiglio != null) ...[
                const SizedBox(height: 12),
                consiglio,
              ],
              const SizedBox(height: 14),
              SizedBox(
                height: 50,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.bg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text(
                    'PRENOTA O SBLOCCA',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.bg,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tocca un altro mezzo per confrontare il percorso.',
                style: GoogleFonts.barlow(
                  fontSize: 12.5,
                  height: 1.3,
                  color: AppColors.dim,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onClear,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dim,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text(
                    'ANNULLA DESTINAZIONE',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: AppColors.dim,
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

/// UT.07 - Indicatore "calcolo percorso" in corso.
class RoutingChip extends StatelessWidget {
  const RoutingChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.green),
          ),
          const SizedBox(width: 10),
          Text(
            'Calcolo percorso…',
            style: GoogleFonts.barlow(fontSize: 13, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}
