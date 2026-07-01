/// Sessione di chat scalata a operatore, vista nella console di supporto
/// (OP.08). Arricchita con i dati dell'utente e l'ultimo messaggio,
/// restituiti dal backend su GET /operator/chat/sessions. Coda condivisa:
/// nessun operatore assegnato, chiunque puo' rispondere.
class OperatorChatSessionModel {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String status; // 'bot' | 'operatore' | 'chiusa'
  final DateTime createdAt;
  final String lastMessage;
  final DateTime lastMessageAt;
  final String lastMessageFrom; // 'utente' | 'bot' | 'operatore'

  const OperatorChatSessionModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.status,
    required this.createdAt,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageFrom,
  });

  factory OperatorChatSessionModel.fromJson(Map<String, dynamic> json) {
    return OperatorChatSessionModel(
      id: json['id'] as String,
      userId: (json['user_id'] as String?) ?? '',
      userName: (json['user_name'] as String?) ?? '',
      userEmail: (json['user_email'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'operatore',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      lastMessage: (json['last_message'] as String?) ?? '',
      lastMessageAt: DateTime.tryParse(json['last_message_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      lastMessageFrom: (json['last_message_from'] as String?) ?? 'utente',
    );
  }

  /// In attesa di risposta: l'ultimo messaggio non e' dell'operatore.
  bool get isWaiting => lastMessageFrom != 'operatore';
}
