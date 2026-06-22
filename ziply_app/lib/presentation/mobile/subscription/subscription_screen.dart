import 'package:flutter/material.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/data/models/subscription_model.dart';
import 'package:ziply_app/services/subscription_service.dart';

// Palette (alias di AppColors).
const Color _kBg      = AppColors.bg;
const Color _kSurface = AppColors.surface;
const Color _kBorder  = AppColors.border;
const Color _kText    = AppColors.text;
const Color _kDim     = AppColors.dim;
const Color _kAccent  = AppColors.accent;
const Color _kGreen   = AppColors.green;

TextStyle _cond({double size = 14, FontWeight w = FontWeight.w700, Color c = _kText, double ls = 0}) =>
    appCond(size: size, w: w, c: c, ls: ls);

TextStyle _body({double size = 15, FontWeight w = FontWeight.w400, Color c = _kText}) =>
    appBody(size: size, w: w, c: c);

// Prezzi mock per la demo: i costi reali verranno integrati in Sprint 3.
const Map<int, double> _kPrices = {1: 9.99, 3: 24.99, 6: 44.99, 12: 79.99};
const Map<int, String> _kDurationLabels = {1: '1 mese', 3: '3 mesi', 6: '6 mesi', 12: '12 mesi'};

IconData _iconFor(String nome) {
  switch (nome) {
    case 'Bicicletta':
      return Icons.directions_bike;
    case 'Monopattino elettrico':
      return Icons.electric_scooter;
    case 'Automobile elettrica':
      return Icons.electric_car;
    default:
      return Icons.directions;
  }
}

/// [MOBILE] Schermata abbonamenti (UT.22): mostra le tipologie di mezzo,
/// gli abbonamenti attivi dell'utente e permette di sottoscriverne di nuovi.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
  }

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _service = SubscriptionService();

  bool _loading = true;
  String? _error;
  List<SubscriptionModel> _subscriptions = [];
  List<VehicleTypeModel> _vehicleTypes = [];

  // Durata selezionata per ogni tipologia (vehicleTypeId → mesi).
  final Map<String, int> _selectedDuration = {};
  // Flag di caricamento per singola sottoscrizione (vehicleTypeId → bool).
  final Map<String, bool> _subscribing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchAll();
      if (!mounted) return;
      setState(() {
        _subscriptions = result.subscriptions;
        _vehicleTypes = result.vehicleTypes;
        _loading = false;
        for (final vt in result.vehicleTypes) {
          _selectedDuration.putIfAbsent(vt.id, () => 1);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  SubscriptionModel? _activeSubFor(String vehicleTypeId) {
    for (final s in _subscriptions) {
      if (s.vehicleTypeId == vehicleTypeId && s.isActive) return s;
    }
    return null;
  }

  Future<void> _subscribe(VehicleTypeModel vt) async {
    final months = _selectedDuration[vt.id] ?? 1;
    setState(() => _subscribing[vt.id] = true);

    try {
      final sub = await _service.subscribe(
        vehicleTypeId: vt.id,
        durationMonths: months,
      );
      if (!mounted) return;
      setState(() {
        _subscriptions = [..._subscriptions, sub];
        _subscribing[vt.id] = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: _kSurface,
        content: Text(
          'Abbonamento ${vt.nome} attivato fino al ${_fmtDate(sub.endDate)}',
          style: _body(size: 14, c: _kGreen),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _subscribing[vt.id] = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: _kSurface,
        content: Text(
          e.toString().replaceFirst('Exception: ', ''),
          style: _body(size: 14, c: _kText),
        ),
      ));
    }
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kText),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('ABBONAMENTI', style: _cond(size: 20, c: _kAccent, ls: 0.5)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: _kBorder, height: 1),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _kDim, size: 48),
              const SizedBox(height: 16),
              Text(_error!, style: _body(size: 15, c: _kDim), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _load,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: _kBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                child: Text('RIPROVA', style: _cond(size: 16, c: _kBg, ls: 0.5)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _kAccent,
      backgroundColor: _kSurface,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Sezione abbonamenti attivi
          Text('I MIEI ABBONAMENTI', style: _cond(size: 13, c: _kDim, ls: 0.8)),
          const SizedBox(height: 12),
          ..._buildActiveSection(),
          const SizedBox(height: 28),
          // Sezione sottoscrizione per tipologia
          Text('NUOVI ABBONAMENTI', style: _cond(size: 13, c: _kDim, ls: 0.8)),
          const SizedBox(height: 4),
          Text(
            'Accedi illimitatamente a una tipologia di mezzo per il periodo scelto.',
            style: _body(size: 13, c: _kDim),
          ),
          const SizedBox(height: 16),
          ..._vehicleTypes.map(_buildVehicleTypeCard),
        ],
      ),
    );
  }

  List<Widget> _buildActiveSection() {
    final actives = _subscriptions.where((s) => s.isActive).toList();
    if (actives.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: _kSurface,
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              const Icon(Icons.workspace_premium_outlined, color: _kDim, size: 36),
              const SizedBox(height: 8),
              Text('Nessun abbonamento attivo', style: _body(size: 14, c: _kDim)),
            ],
          ),
        ),
      ];
    }
    return actives.map((sub) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          border: Border.all(color: _kGreen.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(_iconFor(sub.vehicleTypeName), color: _kGreen, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sub.vehicleTypeName, style: _cond(size: 17, c: _kText)),
                  const SizedBox(height: 4),
                  Text(
                    'Valido fino al ${_fmtDate(sub.endDate)}',
                    style: _body(size: 13, c: _kDim),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.12),
                border: Border.all(color: _kGreen),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('ATTIVO', style: _cond(size: 11, c: _kGreen, ls: 0.6)),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildVehicleTypeCard(VehicleTypeModel vt) {
    final activeSub = _activeSubFor(vt.id);
    final isSubscribed = activeSub != null;
    final isLoading = _subscribing[vt.id] == true;
    final selectedMonths = _selectedDuration[vt.id] ?? 1;
    final price = _kPrices[selectedMonths] ?? 9.99;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border.all(color: isSubscribed ? _kBorder : _kBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header tipologia
          Row(
            children: [
              Icon(_iconFor(vt.nome), color: _kAccent, size: 26),
              const SizedBox(width: 12),
              Text(vt.nome, style: _cond(size: 18, c: _kText)),
            ],
          ),
          const SizedBox(height: 16),
          if (isSubscribed) ...[
            // Già sottoscritto — mostra scadenza
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.08),
                border: Border.all(color: _kGreen.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  Text('ABBONAMENTO ATTIVO', style: _cond(size: 12, c: _kGreen, ls: 0.6)),
                  const SizedBox(height: 4),
                  Text(
                    'Valido fino al ${_fmtDate(activeSub.endDate)}',
                    style: _body(size: 14, c: _kDim),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Selettore durata
            Text('DURATA', style: _cond(size: 12, c: _kDim, ls: 0.6)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kDurationLabels.entries.map((e) {
                final selected = selectedMonths == e.key;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDuration[vt.id] = e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? _kAccent.withValues(alpha: 0.15) : Colors.transparent,
                      border: Border.all(color: selected ? _kAccent : _kBorder),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      e.value,
                      style: _cond(size: 14, c: selected ? _kAccent : _kDim, ls: 0.2),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Prezzo e pulsante
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '€ ${price.toStringAsFixed(2).replaceAll('.', ',')}',
                        style: _cond(size: 24, c: _kAccent),
                      ),
                      Text(
                        '/ ${_kDurationLabels[selectedMonths]}',
                        style: _body(size: 12, c: _kDim),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : () => _subscribe(vt),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: _kBg,
                      disabledBackgroundColor: _kAccent.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _kBg),
                          )
                        : Text('ABBONATI', style: _cond(size: 15, c: _kBg, ls: 0.8)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
