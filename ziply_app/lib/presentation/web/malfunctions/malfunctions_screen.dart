import 'package:flutter/material.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/operator_malfunction_report_model.dart';
import 'package:ziply_app/services/operator_service.dart';

/// OP.03 / UC-26 — Gestione segnalazioni di malfunzionamento. L'operatore
/// consulta le segnalazioni provenienti dagli utenti (UT.11), le filtra per
/// stato e ne aggiorna lo stato di lavorazione (preso in carico / risolto).
/// Alla risoluzione il backend rimette il mezzo disponibile.
class MalfunctionsScreen extends StatefulWidget {
  const MalfunctionsScreen({super.key});

  @override
  State<MalfunctionsScreen> createState() => _MalfunctionsScreenState();
}

class _MalfunctionsScreenState extends State<MalfunctionsScreen> {
  final OperatorService _operatorService = OperatorService();

  List<OperatorMalfunctionReportModel> _reports = const [];
  bool _isLoading = true;
  bool _hasError = false;
  String _filter = 'tutti'; // 'tutti' | 'in_attesa' | 'preso_in_carico' | 'risolto'
  final Set<String> _updating = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final status = _filter == 'tutti' ? null : _filter;
      final loaded = await _operatorService.getMalfunctionReports(status: status);
      if (mounted) {
        setState(() {
          _reports = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      zlog('Errore caricamento segnalazioni: $e', tag: 'WebMalfunctions');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _updateStatus(OperatorMalfunctionReportModel r, String newStatus) async {
    setState(() => _updating.add(r.id));
    try {
      await _operatorService.updateMalfunctionStatus(r.id, newStatus);
      await _load();
    } catch (e) {
      zlog('Errore aggiornamento stato: $e', tag: 'WebMalfunctions');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Aggiornamento non riuscito: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating.remove(r.id));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'in_attesa':
        return AppColors.red;
      case 'preso_in_carico':
        return AppColors.accent;
      case 'risolto':
        return AppColors.green;
      default:
        return AppColors.dim;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_attesa':
        return 'In attesa';
      case 'preso_in_carico':
        return 'Preso in carico';
      case 'risolto':
        return 'Risolto';
      default:
        return status;
    }
  }

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'adesso';
    if (d.inMinutes < 60) return '${d.inMinutes} min fa';
    if (d.inHours < 24) return '${d.inHours} h fa';
    return '${d.inDays} g fa';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Segnalazioni malfunzionamenti', style: appCond(size: 28, w: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: _isLoading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, color: AppColors.dim),
              tooltip: 'Aggiorna',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Gestisci le segnalazioni dei mezzi e aggiornane lo stato di lavorazione.',
          style: appBody(size: 15, c: AppColors.dim),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildFilterTab('tutti', 'Tutte'),
            _buildFilterTab('in_attesa', 'In attesa'),
            _buildFilterTab('preso_in_carico', 'Preso in carico'),
            _buildFilterTab('risolto', 'Risolte'),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
        ),
      );
    }
    if (_hasError) {
      return _buildPlaceholder(
        Icons.cloud_off_rounded,
        'Impossibile caricare le segnalazioni',
        'Riprova',
        _load,
      );
    }
    if (_reports.isEmpty) {
      return _buildPlaceholder(
        Icons.check_circle_outline_rounded,
        'Nessuna segnalazione',
        null,
        null,
      );
    }
    return ListView.separated(
      itemCount: _reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildReportCard(_reports[index]),
    );
  }

  Widget _buildPlaceholder(IconData icon, String title, String? action, VoidCallback? onAction) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.dim),
          const SizedBox(height: 16),
          Text(title, style: appCond(size: 18, w: FontWeight.w600, c: AppColors.dim)),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent.withValues(alpha: 0.40)),
              ),
              child: Text(action),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportCard(OperatorMalfunctionReportModel r) {
    final statusColor = _statusColor(r.status);
    final isUpdating = _updating.contains(r.id);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.report_problem_rounded, color: statusColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      r.vehicleQr.isNotEmpty ? r.vehicleQr : r.vehicleId,
                      style: appCond(size: 19, w: FontWeight.bold),
                    ),
                    const SizedBox(width: 10),
                    _buildStatusBadge(r.status, statusColor),
                    const Spacer(),
                    Text(_relativeTime(r.createdAt), style: appBody(size: 12, c: AppColors.dim)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${r.vehicleType} · problema: ${r.problemType} · fonte: ${r.source}',
                  style: appBody(size: 13, c: AppColors.dim),
                ),
                if (r.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(r.description, style: appBody(size: 14, c: AppColors.text)),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (r.status == 'in_attesa')
                      _buildActionButton(
                        'Prendi in carico',
                        Icons.engineering_rounded,
                        AppColors.accent,
                        isUpdating ? null : () => _updateStatus(r, 'preso_in_carico'),
                      ),
                    if (r.status != 'risolto') ...[
                      const SizedBox(width: 10),
                      _buildActionButton(
                        'Segna risolto',
                        Icons.check_rounded,
                        AppColors.green,
                        isUpdating ? null : () => _updateStatus(r, 'risolto'),
                      ),
                    ],
                    if (isUpdating) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _statusLabel(status).toUpperCase(),
        style: appCond(size: 11, w: FontWeight.bold, c: color, ls: 0.6),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback? onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.40)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildFilterTab(String key, String label) {
    final isSelected = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          if (_filter == key) return;
          setState(() => _filter = key);
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: isSelected ? AppColors.accent : AppColors.border),
          ),
          child: Text(
            label,
            style: appCond(
              size: 14,
              w: FontWeight.w600,
              c: isSelected ? AppColors.bg : AppColors.dim,
              ls: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
