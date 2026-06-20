class ChatSessionModel {
  final String id;
  final String status; // 'bot' | 'operatore' | 'chiusa'

  const ChatSessionModel({required this.id, required this.status});

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) =>
      ChatSessionModel(
        id: json['id'] as String,
        status: json['status'] as String,
      );

  bool get isEscalated => status == 'operatore';
}

class ChatMessageModel {
  final String id;
  final String sessionId;
  final String sender; // 'utente' | 'bot' | 'operatore'
  final String text;
  final DateTime sentAt;

  const ChatMessageModel({
    required this.id,
    required this.sessionId,
    required this.sender,
    required this.text,
    required this.sentAt,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) =>
      ChatMessageModel(
        id: json['id'] as String,
        sessionId: json['session_id'] as String,
        sender: json['sender'] as String,
        text: json['text'] as String,
        sentAt: DateTime.parse(json['sent_at'] as String).toLocal(),
      );

  bool get isUser => sender == 'utente';
}
