part of '../map_screen.dart';

// ── UT.16 · Pulsante "prenota gruppo" (toggle modalità, bottom-left) ────────
class _GroupButton extends StatelessWidget {
  const _GroupButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _kBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.group_add, color: _kAccent, size: 24),
        ),
      ),
    );
  }
}

// ── UT.16 · Banner "seleziona i mezzi" (durante la selezione gruppo) ───────
class _GroupSelectBanner extends StatelessWidget {
  const _GroupSelectBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kAccent),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.group_add, color: _kAccent, size: 20),
          const SizedBox(width: 8),
          Text(
            'SELEZIONA I MEZZI',
            style: GoogleFonts.barlowCondensed(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _kAccent,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'bici/monopattini, entro 100 m',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(fontSize: 13, color: _kText),
            ),
          ),
        ],
      ),
    );
  }
}

// ── UT.16 · Messaggio contestuale selezione gruppo (stile banner zona) ─────
class _GroupHintBanner extends StatelessWidget {
  const _GroupHintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kAccent),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(fontSize: 13, color: _kText),
            ),
          ),
        ],
      ),
    );
  }
}

// ── UT.16 · Pannello selezione gruppo (conteggio + conferma) ───────────────
class _GroupSelectionPanel extends StatelessWidget {
  const _GroupSelectionPanel({
    required this.count,
    required this.max,
    required this.busy,
    required this.onConfirm,
    required this.onCancel,
  });

  final int count;
  final int max;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final enabled = count >= 1;
    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kBorder)),
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
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PRENOTAZIONE DI GRUPPO',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: _kDim,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          count == 0
                              ? 'Nessun mezzo selezionato'
                              : '$count ${count == 1 ? 'mezzo selezionato' : 'mezzi selezionati'}',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: _kText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'max $max',
                    style: GoogleFonts.barlow(fontSize: 12, color: _kDim),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 50,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (enabled && !busy) ? onConfirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: _kBg,
                    disabledBackgroundColor: _kSurface,
                    disabledForegroundColor: _kDim,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: enabled
                          ? BorderSide.none
                          : const BorderSide(color: _kBorder),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: _kBg),
                        )
                      : Text(
                          count <= 1 ? 'PRENOTA MEZZO' : 'PRENOTA $count MEZZI',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: enabled ? _kBg : _kDim,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kDim,
                    side: const BorderSide(color: _kBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text(
                    'ANNULLA',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
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

// ── UT.16 · Pannello prenotazione di gruppo attiva (countdown + sblocco) ───
class _GroupBookingPanel extends StatefulWidget {
  const _GroupBookingPanel({
    required this.group,
    required this.vehicles,
    required this.busy,
    required this.onUnlock,
    required this.onCancel,
  });

  final MultiBookingModel group;
  final List<VehicleModel> vehicles;
  final bool busy;
  final VoidCallback onUnlock;
  final VoidCallback onCancel;

  @override
  State<_GroupBookingPanel> createState() => _GroupBookingPanelState();
}

class _GroupBookingPanelState extends State<_GroupBookingPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_remaining() <= Duration.zero) _ticker?.cancel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _remaining() {
    final e = widget.group.expiresAt;
    if (e == null) return Duration.zero;
    return e.difference(DateTime.now());
  }

  String _format(Duration d) {
    final c = d.isNegative ? Duration.zero : d;
    final m = c.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = c.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining();
    final expired = remaining <= Duration.zero;
    final n = widget.vehicles.length;

    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kBorder)),
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
                          'PRENOTAZIONE DI GRUPPO',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: _kDim,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$n ${n == 1 ? 'mezzo' : 'mezzi'}',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: _kText,
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
                        expired ? 'SCADUTA' : 'SCADE TRA',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: _kDim,
                        ),
                      ),
                      Text(
                        _format(remaining),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: expired ? _kDim : _kAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in widget.vehicles)
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _kSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _kBorder, width: 0.5),
                      ),
                      child: vehicleGlyph(v.kind, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 50,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (expired || widget.busy) ? null : widget.onUnlock,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: _kBg,
                    disabledBackgroundColor: _kSurface,
                    disabledForegroundColor: _kDim,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: expired
                          ? const BorderSide(color: _kBorder)
                          : BorderSide.none,
                    ),
                  ),
                  child: widget.busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: _kBg),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_open_rounded,
                              color: expired ? _kDim : _kBg,
                              size: 19,
                            ),
                            const SizedBox(width: 9),
                            Text(
                              'SBLOCCA GRUPPO',
                              style: GoogleFonts.barlowCondensed(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: expired ? _kDim : _kBg,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: widget.busy ? null : widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kDim,
                    side: const BorderSide(color: _kBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Text(
                    'ANNULLA GRUPPO',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
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
