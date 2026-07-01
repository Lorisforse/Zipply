import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/data/models/chat_model.dart';
import 'package:ziply_app/data/models/operator_chat_model.dart';
import 'package:ziply_app/services/operator_service.dart';

/// OP.08 — Console di supporto: elenco delle chat scalate a operatore (in
/// attesa/attive) e finestra di conversazione. Coda condivisa: qualsiasi
/// operatore collegato vede le stesse chat e puo' rispondere. La lista si
/// aggiorna periodicamente e segnala i nuovi arrivi con un avviso sonoro e
/// un badge visivo.
class ChatConsoleScreen extends StatefulWidget {
  const ChatConsoleScreen({super.key, this.onWaitingCountChanged});

  /// Notifica il numero di chat in attesa alla dashboard (badge sidebar).
  final ValueChanged<int>? onWaitingCountChanged;

  @override
  State<ChatConsoleScreen> createState() => _ChatConsoleScreenState();
}

class _ChatConsoleScreenState extends State<ChatConsoleScreen> {
  final _operatorService = OperatorService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  List<OperatorChatSessionModel> _sessions = const [];
  final Set<String> _knownWaitingIds = {};
  bool _loadingList = true;
  bool _listError = false;

  String? _selectedSessionId;
  List<ChatMessageModel> _messages = const [];
  bool _loadingMessages = false;
  bool _sending = false;
  bool _closing = false;

  Timer? _listTimer;
  Timer? _messagesTimer;
  bool _firstLoad = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _listTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadSessions());
  }

  @override
  void dispose() {
    _listTimer?.cancel();
    _messagesTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await _operatorService.getChatSessions();
      if (!mounted) return;

      if (!_firstLoad) {
        final newWaiting = sessions.where((s) => s.isWaiting && !_knownWaitingIds.contains(s.id));
        if (newWaiting.isNotEmpty) _notifyNewMessage();
      }
      _firstLoad = false;
      _knownWaitingIds
        ..clear()
        ..addAll(sessions.where((s) => s.isWaiting).map((s) => s.id));

      setState(() {
        _sessions = sessions;
        _loadingList = false;
        _listError = false;
      });
      widget.onWaitingCountChanged?.call(sessions.where((s) => s.isWaiting).length);

      if (_selectedSessionId != null) _loadMessages(silent: true);
    } catch (e) {
      zlog('Errore caricamento chat operatore: $e', tag: 'WebChatConsole');
      if (mounted) {
        setState(() {
          _loadingList = false;
          _listError = _sessions.isEmpty;
        });
      }
    }
  }

  void _notifyNewMessage() {
    SystemSound.play(SystemSoundType.alert);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surface,
        content: Text('Nuovo messaggio in chat supporto', style: appBody(size: 14, c: AppColors.text)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _selectSession(String sessionId) {
    setState(() {
      _selectedSessionId = sessionId;
      _messages = const [];
    });
    _messagesTimer?.cancel();
    _loadMessages();
    _messagesTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages(silent: true));
  }

  Future<void> _loadMessages({bool silent = false}) async {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    if (!silent) setState(() => _loadingMessages = true);
    try {
      final result = await _operatorService.getChatMessages(sessionId);
      if (!mounted || _selectedSessionId != sessionId) return;
      setState(() {
        _messages = result.messages;
        _loadingMessages = false;
      });
      _scrollToBottom();
    } catch (e) {
      zlog('Errore caricamento messaggi chat: $e', tag: 'WebChatConsole');
      if (!silent && mounted) setState(() => _loadingMessages = false);
    }
  }

  Future<void> _send() async {
    final sessionId = _selectedSessionId;
    final text = _inputController.text.trim();
    if (sessionId == null || text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _inputController.clear();
    try {
      await _operatorService.sendChatMessage(sessionId, text);
      await _loadMessages(silent: true);
      await _loadSessions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _closeSession() async {
    final sessionId = _selectedSessionId;
    if (sessionId == null || _closing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text('Chiudere la chat?', style: appCond(size: 20, w: FontWeight.bold)),
        content: Text(
          "L'utente non potra' piu' scrivere in questa sessione; una nuova richiesta ripartira' dal bot.",
          style: appBody(size: 14, c: AppColors.dim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('ANNULLA', style: appCond(size: 14, w: FontWeight.w600, c: AppColors.dim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('CHIUDI', style: appCond(size: 14, w: FontWeight.w600, c: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _closing = true);
    try {
      await _operatorService.closeChatSession(sessionId);
      _messagesTimer?.cancel();
      if (mounted) {
        setState(() {
          _selectedSessionId = null;
          _messages = const [];
        });
      }
      await _loadSessions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 340, child: _buildSessionList()),
        Container(width: 1, color: AppColors.border),
        Expanded(child: _buildConversation()),
      ],
    );
  }

  Widget _buildSessionList() {
    return Container(
      color: AppColors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text('Chat di supporto', style: appCond(size: 18, w: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  onPressed: _loadSessions,
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.dim, size: 20),
                  tooltip: 'Aggiorna',
                ),
              ],
            ),
          ),
          Expanded(child: _buildSessionListBody()),
        ],
      ),
    );
  }

  Widget _buildSessionListBody() {
    if (_loadingList) {
      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent)));
    }
    if (_listError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.dim),
            const SizedBox(height: 12),
            Text('Impossibile caricare le chat', style: appBody(size: 14, c: AppColors.dim)),
          ],
        ),
      );
    }
    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nessuna chat scalata a operatore al momento.',
            textAlign: TextAlign.center,
            style: appBody(size: 14, c: AppColors.dim),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _sessions.length,
      itemBuilder: (context, index) => _buildSessionTile(_sessions[index]),
    );
  }

  Widget _buildSessionTile(OperatorChatSessionModel s) {
    final isSelected = s.id == _selectedSessionId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? AppColors.accent.withValues(alpha: 0.10) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _selectSession(s.id),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSelected ? AppColors.accent : AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.userName.isNotEmpty ? s.userName : s.userEmail,
                        style: appCond(size: 15, w: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (s.isWaiting)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  s.lastMessage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: appBody(size: 13, c: AppColors.dim),
                ),
                const SizedBox(height: 6),
                Text(_relativeTime(s.lastMessageAt), style: appBody(size: 11, c: AppColors.dim)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConversation() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) {
      return Center(
        child: Text(
          'Seleziona una chat per iniziare a rispondere.',
          style: appBody(size: 15, c: AppColors.dim),
        ),
      );
    }

    final session = _sessions.where((s) => s.id == sessionId).cast<OperatorChatSessionModel?>().firstOrNull;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  session != null && session.userName.isNotEmpty ? session.userName : 'Utente',
                  style: appCond(size: 17, w: FontWeight.bold),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _closing ? null : _closeSession,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                label: const Text('Chiudi chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.green,
                  side: BorderSide(color: AppColors.green.withValues(alpha: 0.40)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingMessages
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent)))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _buildMessageBubble(_messages[i]),
                ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildMessageBubble(ChatMessageModel m) {
    final isOperator = m.sender == 'operatore';
    final isUser = m.sender == 'utente';
    return Align(
      alignment: isOperator ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOperator ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isOperator)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  isUser ? 'UTENTE' : 'ZIPLY BOT',
                  style: appCond(size: 10, c: AppColors.accent, ls: 0.5),
                ),
              ),
            Text(m.text, style: appBody(size: 14, c: isOperator ? AppColors.bg : AppColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              style: appBody(size: 14, c: AppColors.text),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Rispondi all\'utente…',
                hintStyle: appBody(size: 14, c: AppColors.dim),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.accent),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            height: 46,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.bg,
                disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.5),
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg))
                  : const Icon(Icons.send_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
