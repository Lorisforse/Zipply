import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/services/api_exceptions.dart';

/// Esito di una chiamata HTTP al backend: codice di stato e corpo JSON già
/// decodificato in modo difensivo (Map, List o null).
class ApiResponse {
  const ApiResponse(this.statusCode, this.json);

  final int statusCode;

  /// Corpo decodificato: può essere una Map, una List o null.
  final dynamic json;

  /// true per gli status 2xx.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Corpo come oggetto JSON, o null se non è un oggetto.
  Map<String, dynamic>? get map =>
      json is Map<String, dynamic> ? json as Map<String, dynamic> : null;

  /// Corpo come array JSON, o null se non è un array.
  List<dynamic>? get list => json is List<dynamic> ? json as List<dynamic> : null;

  /// Messaggio d'errore del backend ({"error": "..."}), se presente e non vuoto.
  String? get errorMessage {
    final m = map?['error'];
    return m is String && m.isNotEmpty ? m : null;
  }
}

/// Client HTTP centralizzato verso ziply_backend. Concentra in un unico punto le
/// convenzioni comuni a tutti i servizi:
///   - base URL ([kBaseUrl]) e header `Content-Type: application/json`;
///   - token JWT da [FlutterSecureStorage] in `Authorization: Bearer` per le
///     chiamate autenticate;
///   - timeout e traduzione degli errori di rete in una Exception uniforme;
///   - gestione uniforme del 401 → [SessionExpiredException] (solo per le
///     chiamate autenticate; sulle pubbliche, es. login, il 401 è restituito al
///     chiamante che lo interpreta come credenziali errate).
///
/// La mappatura dei messaggi di dominio (409/422/404/...) resta nei singoli
/// servizi, perché è specifica del caso d'uso.
class ApiClient {
  ApiClient({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  /// Timeout di default delle chiamate (sovrascrivibile per singola richiesta).
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// GET su [path]; [query] opzionale per i parametri di query.
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
    Duration timeout = defaultTimeout,
  }) {
    return _send(
      () async => _client.get(_uri(path, query), headers: await _headers(authenticated)),
      authenticated: authenticated,
      timeout: timeout,
    );
  }

  /// POST su [path]; [body] viene serializzato in JSON (null = nessun corpo).
  Future<ApiResponse> post(
    String path, {
    Object? body,
    bool authenticated = true,
    Duration timeout = defaultTimeout,
  }) {
    return _send(
      () async => _client.post(
        _uri(path, null),
        headers: await _headers(authenticated),
        body: body == null ? null : jsonEncode(body),
      ),
      authenticated: authenticated,
      timeout: timeout,
    );
  }

  /// DELETE su [path].
  Future<ApiResponse> delete(
    String path, {
    bool authenticated = true,
    Duration timeout = defaultTimeout,
  }) {
    return _send(
      () async => _client.delete(_uri(path, null), headers: await _headers(authenticated)),
      authenticated: authenticated,
      timeout: timeout,
    );
  }

  Uri _uri(String path, Map<String, String>? query) {
    final uri = Uri.parse('$kBaseUrl$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers(bool authenticated) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated) {
      final token = await _storage.read(key: kTokenKey);
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Esegue [request] con timeout, traduce gli errori di rete in una Exception
  /// pronta per la UI e decodifica il corpo. Per le chiamate autenticate un 401
  /// viene convertito in [SessionExpiredException].
  Future<ApiResponse> _send(
    Future<http.Response> Function() request, {
    required bool authenticated,
    required Duration timeout,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on http.ClientException {
      throw Exception('Impossibile connettersi al server');
    } on TimeoutException {
      throw Exception('Impossibile connettersi al server');
    }

    if (authenticated && response.statusCode == 401) {
      throw const SessionExpiredException();
    }

    return ApiResponse(response.statusCode, _decode(response.bodyBytes));
  }

  /// Decodifica difensiva del corpo JSON: ritorna Map, List o null se il corpo
  /// è assente o non è JSON valido.
  static dynamic _decode(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }
}
