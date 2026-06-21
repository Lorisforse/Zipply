import 'package:flutter/material.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/services/malfunction_report_service.dart';

const Color _kBg = AppColors.bg;
const Color _kSurface = AppColors.surface;
const Color _kBorder = AppColors.border;
const Color _kText = AppColors.text;
const Color _kDim = AppColors.dim;
const Color _kAccent = AppColors.accent;

TextStyle _cond({double size = 14, FontWeight w = FontWeight.w700, Color c = _kText, double ls = 0}) =>
    appCond(size: size, w: w, c: c, ls: ls);

TextStyle _body({double size = 15, FontWeight w = FontWeight.w400, Color c = _kText}) =>
    appBody(size: size, w: w, c: c);

class MalfunctionReportScreen extends StatefulWidget {
  const MalfunctionReportScreen({
    super.key,
    required this.rideId,
    required this.vehicleId,
  });

  final String rideId;
  final String vehicleId;

  static Future<void> show(BuildContext context, {required String rideId, required String vehicleId}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MalfunctionReportScreen(rideId: rideId, vehicleId: vehicleId),
      ),
    );
  }

  @override
  State<MalfunctionReportScreen> createState() => _MalfunctionReportScreenState();
}

class _MalfunctionReportScreenState extends State<MalfunctionReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _service = MalfunctionReportService();

  String _selectedProblem = 'Freni';
  final List<String> _problems = ['Freni', 'Batteria', 'Luci', 'Ruote', 'Altro'];
  
  final List<String> _attachments = [];
  bool _submitting = false;

  void _addMockAttachment() {
    setState(() {
      final index = _attachments.length + 1;
      _attachments.add('screenshot_malfunzionamento_$index.png');
    });
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _service.submitReport(
        rideId: widget.rideId,
        problemType: _selectedProblem,
        description: _descriptionController.text.trim(),
        attachmentUrls: _attachments.map((filename) => 'http://ziply-mock-storage.local/$filename').toList(),
      );

      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: _kSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          title: Text(
            'SEGNALAZIONE INVIATA',
            style: _cond(size: 20, c: _kAccent),
          ),
          content: Text(
            'Grazie per il tuo contributo. Il veicolo è stato posto in manutenzione per le opportune verifiche.',
            style: _body(size: 14.5, c: _kText),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(); // Chiude il dialogo
                Navigator.of(context).popUntil((route) => route.isFirst); // Ritorna alla mappa
              },
              child: Text(
                'OK',
                style: _cond(size: 16, c: _kAccent),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: _body(size: 14, c: _kText),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

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
        title: Text(
          'SEGNALA PROBLEMA',
          style: _cond(size: 20, c: _kAccent, ls: 0.5),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: _kBorder, height: 1),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHE TIPO DI PROBLEMA HAI RISCONTRATO?',
                  style: _cond(size: 14, c: _kDim, ls: 0.5),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedProblem,
                  dropdownColor: _kSurface,
                  style: _body(size: 16, c: _kText),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _kSurface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: _kBorder),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: _kAccent),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  items: _problems.map((p) {
                    return DropdownMenuItem<String>(
                      value: p,
                      child: Text(p),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedProblem = val);
                    }
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'DESCRIVI IL DETTAGLIO DEL PROBLEMA',
                  style: _cond(size: 14, c: _kDim, ls: 0.5),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 5,
                  minLines: 3,
                  style: _body(size: 15, c: _kText),
                  validator: (value) {
                    if (value == null || value.trim().length < 8) {
                      return 'Inserisci una descrizione di almeno 8 caratteri';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: 'es. I freni posteriori non rispondono bene alla frenata...',
                    hintStyle: _body(size: 14, c: _kDim),
                    filled: true,
                    fillColor: _kSurface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: _kBorder),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: _kAccent),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.red),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.red),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ALLEGATI FACOLTATIVI',
                      style: _cond(size: 14, c: _kDim, ls: 0.5),
                    ),
                    TextButton.icon(
                      onPressed: _addMockAttachment,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 16, color: _kAccent),
                      label: Text(
                        'AGGIUNGI',
                        style: _cond(size: 13, c: _kAccent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_attachments.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      border: Border.all(color: _kBorder),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.image_not_supported_outlined, color: _kDim, size: 36),
                        const SizedBox(height: 8),
                        Text(
                          'Nessun allegato caricato',
                          style: _body(size: 13, c: _kDim),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _attachments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final item = _attachments[idx];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _kSurface,
                          border: Border.all(color: _kBorder),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.insert_drive_file_outlined, color: _kAccent, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _body(size: 14, c: _kText),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () => _removeAttachment(idx),
                              splashRadius: 20,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: _kBg,
                      disabledBackgroundColor: _kAccent.withOpacity(0.6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _kBg,
                            ),
                          )
                        : Text(
                            'INVIA SEGNALAZIONE',
                            style: _cond(size: 17, w: FontWeight.w700, c: _kBg, ls: 1),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
