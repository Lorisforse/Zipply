import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/availability_alert_model.dart';
import 'package:ziply_app/services/operator_service.dart';

/// OP.02 / OP.07 / UC-25 — Pannello avvisi di anomalia: batteria scarica,
/// movimento illecito e scarsita' mezzi, generati dal worker di rilevamento
/// in background. E' un log di sola lettura (nessuna azione operatore),
/// aggiornato con lo stesso polling di 10s gia' usato dalla mappa flotta.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final OperatorService _operatorService = OperatorService();

  List<AvailabilityAlertModel> _alerts = const [];
  bool _isLoading = true;
  bool _hasError = false;
  String _filter = 'tutti'; // 'tutti' | 'batteria' | 'movimento' | 'scarsita'
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }
    try {
      final loaded = await _operatorService.getAvailabilityAlerts();
      if (mounted) {
        setState(() {
          _alerts = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      zlog('Errore caricamento avvisi: $e', tag: 'WebAlerts');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  List<AvailabilityAlertModel> get _filtered {
    if (_filter == 'tutti') return _alerts;
    return _alerts.where((a) => a.type == _filter).toList();
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'batteria':
        return AppColors.accent;
      case 'movimento':
        return AppColors.red;
      case 'scarsita':
        return const Color(0xFF9C27B0);
      default:
        return AppColors.dim;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'batteria':
        return Icons.battery_alert_rounded;
      case 'movimento':
        return Icons.gps_off_rounded;
      case 'scarsita':
        return Icons.inventory_2_outlined;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'batteria':
        return 'Batteria scarica';
      case 'movimento':
        return 'Movimento illecito';
      case 'scarsita':
        return 'Scarsita mezzi';
      default:
        return type;
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
            Text('Avvisi anomalie', style: appCond(size: 28, w: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: _isLoading ? null : () => _load(),
              icon: const Icon(Icons.refresh_rounded, color: AppColors.dim),
              tooltip: 'Aggiorna',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Batteria scarica, movimento illecito e scarsita\' mezzi rilevati automaticamente.',
          style: appBody(size: 15, c: AppColors.dim),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildFilterTab('tutti', 'Tutti'),
            _buildFilterTab('batteria', 'Batteria'),
            _buildFilterTab('movimento', 'Movimento'),
            _buildFilterTab('scarsita', 'Scarsita'),
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
        'Impossibile caricare gli avvisi',
        'Riprova',
        () => _load(),
      );
    }
    final alerts = _filtered;
    if (alerts.isEmpty) {
      return _buildPlaceholder(
        Icons.check_circle_outline_rounded,
        'Nessun avviso',
        null,
        null,
      );
    }
    return ListView.separated(
      itemCount: alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildAlertCard(alerts[index]),
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

  Widget _buildAlertCard(AvailabilityAlertModel a) {
    final color = _typeColor(a.type);
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
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(_typeIcon(a.type), color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildTypeBadge(a.type, color),
                    const Spacer(),
                    Text(_relativeTime(a.createdAt), style: appBody(size: 12, c: AppColors.dim)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(a.message, style: appBody(size: 14, c: AppColors.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(String type, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _typeLabel(type).toUpperCase(),
        style: appCond(size: 11, w: FontWeight.bold, c: color, ls: 0.6),
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
