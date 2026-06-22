import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ziply_app/core/theme/app_colors.dart';
import 'package:ziply_app/core/theme/app_text_styles.dart';
import 'package:ziply_app/data/models/chat_model.dart';
import 'package:ziply_app/services/chat_service.dart';

// Palette (alias di AppColors).
const Color _kBg      = AppColors.bg;
const Color _kSurface = AppColors.surface;
const Color _kBorder  = AppColors.border;
const Color _kText    = AppColors.text;
const Color _kDim     = AppColors.dim;
const Color _kAccent  = AppColors.accent;

TextStyle _cond({double size = 14, FontWeight w = FontWeight.w700, Color c = _kText, double ls = 0}) =>
    appCond(size: size, w: w, c: c, ls: ls);

TextStyle _body({double size = 15, FontWeight w = FontWeight.w400, Color c = _kText}) =>
    appBody(size: size, w: w, c: c);

/// Schermata di chat di assistenza (UT.10).
/// Il bot risponde automaticamente; se non capisce scala a operatore.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  static Future<void> show(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      );

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _service = ChatService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  ChatSessionModel? _session;
  List<ChatMessageModel> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final session = await _service.getOrCreateSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
      });
      await _loadMessages();
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadMessages() async {
    if (_session == null) return;
    try {
      final result = await _service.getMessages(_session!.id);
      if (!mounted) return;
      setState(() {
        _session = result.session;
        _messages = result.messages;
      });
      _scrollToBottom();
    } catch (_) {
      // polling silenzioso: non mostra errore
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _session == null || _sending) return;

    setState(() => _sending = true);
    _inputController.clear();

    try {
      final newMsgs = await _service.sendMessage(_session!.id, text);
      if (!mounted) return;
      // Ricarica tutto per aggiornare anche lo stato sessione (escalation)
      await _loadMessages();
      // Se i messaggi non sono già arrivati via polling, aggiungili subito
      if (_messages.isNotEmpty && _messages.last.id != newMsgs.last.id) {
        setState(() => _messages.addAll(newMsgs));
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _kSurface,
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: _body(size: 14, c: _kText),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
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
        title: Text('SUPPORTO', style: _cond(size: 20, c: _kAccent, ls: 0.5)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: _kBorder, height: 1),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kAccent))
            : _error != null
                ? _ErrorView(error: _error!, onRetry: _init)
                : Column(
                    children: [
                      if (_session?.isEscalated == true) _EscalationBanner(),
                      Expanded(child: _MessageList(messages: _messages, scrollController: _scrollController)),
                      _InputBar(
                        controller: _inputController,
                        sending: _sending,
                        onSend: _send,
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ── Banner escalation ─────────────────────────────────────────────────────
class _EscalationBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _kAccent.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.support_agent, color: _kAccent, size: 18),
          const SizedBox(width: 10),
          Text(
            'In attesa di un operatore…',
            style: _cond(size: 14, c: _kAccent),
          ),
        ],
      ),
    );
  }
}

// ── Lista messaggi ────────────────────────────────────────────────────────
class _MessageList extends StatelessWidget {
  const _MessageList({required this.messages, required this.scrollController});

  final List<ChatMessageModel> messages;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Ciao! Come posso aiutarti?\nScrivi la tua richiesta qui sotto.',
            textAlign: TextAlign.center,
            style: _body(size: 15, c: _kDim),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (_, i) => _MessageBubble(message: messages[i]),
    );
  }
}

// ── Singolo messaggio ─────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? _kAccent : _kSurface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 2),
            bottomRight: Radius.circular(isUser ? 2 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.sender == 'operatore' ? 'OPERATORE' : 'ZIPLY BOT',
                  style: _cond(size: 10, c: _kAccent, ls: 0.5),
                ),
              ),
            Text(
              message.text,
              style: _body(size: 14.5, c: isUser ? _kBg : _kText),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Barra di input ────────────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: _body(size: 15, c: _kText),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Scrivi un messaggio…',
                hintStyle: _body(size: 14, c: _kDim),
                filled: true,
                fillColor: _kSurface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: _kBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: _kAccent),
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
              onPressed: sending ? null : onSend,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: _kBg,
                disabledBackgroundColor: _kAccent.withValues(alpha: 0.5),
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _kBg),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vista errore ──────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: _kDim, size: 48),
            const SizedBox(height: 16),
            Text(error, textAlign: TextAlign.center, style: _body(size: 14, c: _kDim)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onRetry,
              child: Text('RIPROVA', style: _cond(size: 15, c: _kAccent, ls: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}
