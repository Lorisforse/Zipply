import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/data/models/chat_model.dart';
import 'package:ziply_app/services/api_exceptions.dart';

class ChatService {
  ChatService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const Duration _timeout = Duration(seconds: 10);

  Future<Map<String, String>> _authHeaders() async {
    final token = await _storage.read(key: kTokenKey);
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Recupera o crea la sessione di chat aperta.
  Future<ChatSessionModel> getOrCreateSession() async {
    final response = await _client
        .post(
          Uri.parse('$kBaseUrl/chat/sessions'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);

    if (response.statusCode == 401) throw const SessionExpiredException();
    if (response.statusCode != 200) {
      throw Exception('Impossibile aprire la chat');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return ChatSessionModel.fromJson(json);
  }

  /// Invia un messaggio e restituisce i nuovi messaggi (utente + risposta bot).
  Future<List<ChatMessageModel>> sendMessage(String sessionId, String body) async {
    final response = await _client
        .post(
          Uri.parse('$kBaseUrl/chat/sessions/$sessionId/messages'),
          headers: await _authHeaders(),
          body: jsonEncode({'body': body}),
        )
        .timeout(_timeout);

    if (response.statusCode == 401) throw const SessionExpiredException();
    if (response.statusCode != 201) {
      final err = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception((err as Map?)?['error'] ?? 'Errore invio messaggio');
    }
    final list = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return list.map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Recupera tutti i messaggi e lo stato corrente della sessione.
  Future<({ChatSessionModel session, List<ChatMessageModel> messages})> getMessages(String sessionId) async {
    final response = await _client
        .get(
          Uri.parse('$kBaseUrl/chat/sessions/$sessionId/messages'),
          headers: await _authHeaders(),
        )
        .timeout(_timeout);

    if (response.statusCode == 401) throw const SessionExpiredException();
    if (response.statusCode != 200) {
      throw Exception('Impossibile caricare i messaggi');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final session = ChatSessionModel.fromJson(json['session'] as Map<String, dynamic>);
    final rawMsgs = json['messages'] as List<dynamic>? ?? [];
    final messages = rawMsgs
        .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return (session: session, messages: messages);
  }
}
