import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/data/models/chat_model.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio per la chat di assistenza (UT.10): chiamate REST verso ziply_backend
/// tramite [ApiClient] (base URL, token JWT, 401 → sessione scaduta).
class ChatService {
  ChatService({http.Client? client, FlutterSecureStorage? storage})
      : _api = ApiClient(client: client, storage: storage);

  final ApiClient _api;

  /// Recupera o crea la sessione di chat aperta.
  Future<ChatSessionModel> getOrCreateSession() async {
    final res = await _api.post('/chat/sessions');

    if (res.statusCode != 200) {
      throw Exception('Impossibile aprire la chat');
    }
    return ChatSessionModel.fromJson(res.map ?? const {});
  }

  /// Invia un messaggio e restituisce i nuovi messaggi (utente + risposta bot).
  Future<List<ChatMessageModel>> sendMessage(String sessionId, String body) async {
    final res = await _api.post(
      '/chat/sessions/$sessionId/messages',
      body: {'body': body},
    );

    if (res.statusCode != 201) {
      throw Exception(res.errorMessage ?? 'Errore invio messaggio');
    }
    final list = res.list ?? const [];
    return list
        .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Recupera tutti i messaggi e lo stato corrente della sessione.
  Future<({ChatSessionModel session, List<ChatMessageModel> messages})> getMessages(String sessionId) async {
    final res = await _api.get('/chat/sessions/$sessionId/messages');

    if (res.statusCode != 200) {
      throw Exception('Impossibile caricare i messaggi');
    }
    final json = res.map ?? const <String, dynamic>{};
    final session = ChatSessionModel.fromJson(json['session'] as Map<String, dynamic>);
    final rawMsgs = json['messages'] as List<dynamic>? ?? [];
    final messages = rawMsgs
        .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return (session: session, messages: messages);
  }
}
