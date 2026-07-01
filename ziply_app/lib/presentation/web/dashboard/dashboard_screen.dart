import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/operator_vehicle_model.dart';
import 'package:ziply_app/presentation/web/alerts/alerts_screen.dart';
import 'package:ziply_app/presentation/web/auth/web_auth_gate.dart';
import 'package:ziply_app/presentation/web/chat/chat_console_screen.dart';
import 'package:ziply_app/presentation/web/fleet/fleet_screen.dart';
import 'package:ziply_app/presentation/web/malfunctions/malfunctions_screen.dart';
import 'package:ziply_app/services/auth_service.dart';
import 'package:ziply_app/services/operator_service.dart';

/// Shell della dashboard web operatore: sidebar di navigazione + area
/// contenuto. Sono attive la panoramica KPI, la mappa flotta in tempo reale
/// (OP.01), i malfunzionamenti (OP.03), gli avvisi di anomalia (OP.02 /
/// OP.07) e la console di chat di supporto (OP.08).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _authService = AuthService();
  final OperatorService _operatorService = OperatorService();

  String _operatorEmail = '';
  String _operatorRole = '';
  int _selectedTab = 0;

  List<OperatorVehicleModel> _vehicles = const [];
  int _recentAlertCount = 0;
  int _waitingChatCount = 0;
  Timer? _alertsRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadOperatorInfo();
    _loadAlertCount();
    _loadWaitingChatCount();
    _alertsRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        _loadAlertCount();
        _loadWaitingChatCount();
      },
    );
  }

  @override
  void dispose() {
    _alertsRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOperatorInfo() async {
    final token = await _authService.getToken();
    if (token != null && token.isNotEmpty) {
      try {
        final claims = decodeJwt(token);
        setState(() {
          _operatorEmail = claims['email'] as String? ?? 'N/A';
          _operatorRole = claims['ruolo'] as String? ?? 'operatore';
        });
      } catch (e) {
        zlog('Errore caricamento info operatore: $e', tag: 'WebDashboard');
      }
    }
    _loadFleet();
  }

  /// Contatore chat in attesa di risposta per il badge sidebar (OP.08).
  /// Mentre la console e' aperta il conteggio arriva da [ChatConsoleScreen]
  /// tramite [onWaitingCountChanged], quindi qui basta evitare la doppia fonte.
  Future<void> _loadWaitingChatCount() async {
    if (_selectedTab == 4) return;
    try {
      final sessions = await _operatorService.getChatSessions();
      final waiting = sessions.where((s) => s.isWaiting).length;
      if (mounted) setState(() => _waitingChatCount = waiting);
    } catch (e) {
      zlog('Errore caricamento contatore chat: $e', tag: 'WebDashboard');
    }
  }

  Future<void> _loadFleet() async {
    try {
      final vehicles = await _operatorService.getVehicles();
      if (mounted) setState(() => _vehicles = vehicles);
    } catch (e) {
      zlog('Errore caricamento KPI flotta: $e', tag: 'WebDashboard');
    }
  }

  /// Contatore avvisi anomalia nelle ultime 24h per la card KPI (OP.02 / OP.07).
  Future<void> _loadAlertCount() async {
    try {
      final alerts = await _operatorService.getAvailabilityAlerts();
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final recent = alerts.where((a) => a.createdAt.isAfter(cutoff)).length;
      if (mounted) setState(() => _recentAlertCount = recent);
    } catch (e) {
      zlog('Errore caricamento contatore avvisi: $e', tag: 'WebDashboard');
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await _confirmLogout();
    if (confirmed != true || !mounted) return;
    await _authService.logout();
    zlog('Logout completato, reindirizzo...', tag: 'WebDashboard');
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const WebAuthGate()),
      );
    }
  }

  /// Dialog di conferma prima del logout (azione distruttiva).
  Future<bool?> _confirmLogout() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text('Disconnettersi?', style: appCond(size: 20, w: FontWeight.bold)),
        content: Text(
          'Dovrai accedere di nuovo per rientrare nella dashboard.',
          style: appBody(size: 14, c: AppColors.dim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('ANNULLA', style: appCond(size: 14, w: FontWeight.w600, c: AppColors.dim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('DISCONNETTI', style: appCond(size: 14, w: FontWeight.w600, c: AppColors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 70,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Text(_getTabTitle(), style: appCond(size: 20, w: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.notifications_none_rounded, color: AppColors.dim),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: (_selectedTab == 1 || _selectedTab == 4) ? EdgeInsets.zero : const EdgeInsets.all(32),
                    child: _buildMainContent(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            // Stesso wordmark dell'app: 'ZIPLY' arancione + sottotitolo.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('ZIPLY', style: appCond(size: 24, w: FontWeight.w700, c: AppColors.accent, ls: 1)),
                const SizedBox(width: 9),
                Text('DASHBOARD', style: appCond(size: 11, w: FontWeight.w600, c: AppColors.dim, ls: 1.5)),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              children: [
                _buildSidebarItem(icon: Icons.analytics_outlined, label: 'Panoramica KPI', index: 0),
                _buildSidebarItem(icon: Icons.map_outlined, label: 'Mappa Flotta', index: 1),
                _buildSidebarItem(icon: Icons.report_problem_outlined, label: 'Malfunzionamenti', index: 2),
                _buildSidebarItem(icon: Icons.warning_amber_rounded, label: 'Anomalie', index: 3),
                _buildSidebarItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Chat Supporto',
                  index: 4,
                  badgeCount: _waitingChatCount,
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.surface2,
                      child: Text(
                        _operatorEmail.isNotEmpty ? _operatorEmail[0].toUpperCase() : 'O',
                        style: appCond(c: AppColors.accent, w: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _operatorEmail,
                            style: appBody(size: 13, c: AppColors.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _operatorRole.toUpperCase(),
                              style: appCond(size: 9, w: FontWeight.bold, c: AppColors.accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _handleLogout,
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: const Text('Disconnetti'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: BorderSide(color: AppColors.red.withValues(alpha: 0.20)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required int index,
    bool enabled = true,
    int badgeCount = 0,
  }) {
    final isSelected = enabled && _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected ? AppColors.accent.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? () => setState(() => _selectedTab = index) : null,
          borderRadius: BorderRadius.circular(8),
          child: Opacity(
            opacity: enabled ? 1.0 : 0.45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: isSelected ? AppColors.accent : AppColors.dim, size: 20),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      style: appCond(
                        size: 15,
                        w: isSelected ? FontWeight.w600 : FontWeight.w500,
                        c: isSelected ? AppColors.text : AppColors.dim,
                      ),
                    ),
                  ),
                  if (badgeCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        '$badgeCount',
                        style: appCond(size: 11, w: FontWeight.bold, c: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getTabTitle() {
    switch (_selectedTab) {
      case 1:
        return 'Mappa Flotta';
      case 2:
        return 'Malfunzionamenti';
      case 3:
        return 'Anomalie';
      case 4:
        return 'Chat Supporto';
      case 0:
      default:
        return 'Panoramica KPI';
    }
  }

  Widget _buildMainContent() {
    switch (_selectedTab) {
      case 1:
        return const FleetScreen();
      case 2:
        return const MalfunctionsScreen();
      case 3:
        return const AlertsScreen();
      case 4:
        return ChatConsoleScreen(onWaitingCountChanged: (count) {
          if (mounted) setState(() => _waitingChatCount = count);
        });
      case 0:
      default:
        return _buildKPIOverview();
    }
  }

  Widget _buildKPIOverview() {
    final totale = _vehicles.length;
    final disponibili = _vehicles.where((v) => v.status == 'disponibile').length;
    final manutenzione = _vehicles.where((v) => v.status == 'manutenzione').length;
    final bloccati = _vehicles.where((v) => v.status == 'bloccato').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bentornato, Operatore!', style: appCond(size: 28, w: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Stato attuale della flotta urbana in tempo reale.',
          style: appBody(size: 15, c: AppColors.dim),
        ),
        const SizedBox(height: 40),
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                title: 'Mezzi Totali',
                value: '$totale',
                icon: Icons.directions_bike_rounded,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildKPICard(
                title: 'Disponibili',
                value: '$disponibili',
                icon: Icons.check_circle_outline_rounded,
                color: AppColors.green,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildKPICard(
                title: 'In Manutenzione',
                value: '$manutenzione',
                icon: Icons.build_circle_outlined,
                color: AppColors.red,
              ),
            ),
            if (bloccati > 0) ...[
              const SizedBox(width: 24),
              Expanded(
                child: _buildKPICard(
                  title: 'Bloccati',
                  value: '$bloccati',
                  icon: Icons.lock_rounded,
                  color: const Color(0xFF9C27B0),
                ),
              ),
            ],
            const SizedBox(width: 24),
            Expanded(
              child: _buildKPICard(
                title: 'Anomalie (24h)',
                value: '$_recentAlertCount',
                icon: Icons.warning_amber_rounded,
                color: AppColors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: appCond(size: 15, w: FontWeight.w500, c: AppColors.dim)),
              const SizedBox(height: 12),
              Text(value, style: appCond(size: 36, w: FontWeight.bold)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
        ],
      ),
    );
  }
}
