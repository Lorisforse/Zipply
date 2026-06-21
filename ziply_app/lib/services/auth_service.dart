import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ziply_app/constants.dart';
import 'package:ziply_app/core/utils/app_logger.dart';
import 'package:ziply_app/services/api_client.dart';

/// Servizio di autenticazione: chiamate REST verso ziply_backend e
/// persistenza del token JWT in storage sicuro.
class AuthService {
  AuthService({http.Client? client, FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        _api = ApiClient(client: client, storage: storage);

  final FlutterSecureStorage _storage;
  final ApiClient _api;

  /// Effettua il login e restituisce il body JSON della risposta (token + user).
  Future<Map<String, dynamic>> login(String email, String password) async {
    zlog('Login in corso per $email', tag: 'Auth');
    try {
      final data = await _postJson(
        '/auth/login',
        {'email': email, 'password': password},
        expectedStatus: 200,
      );
      zlog('Login riuscito per $email', tag: 'Auth');
      return data;
    } on Exception catch (e) {
      zlog('Login fallito per $email: $e', tag: 'Auth');
      rethrow;
    }
  }

  /// Registra un nuovo utente e restituisce il body JSON della risposta (token + user).
  Future<Map<String, dynamic>> register(
      String nome, String cognome, String email, String password) async {
    zlog('Registrazione in corso per $email', tag: 'Auth');
    try {
      final data = await _postJson(
        '/auth/register',
        {'nome': nome, 'cognome': cognome, 'email': email, 'password': password},
        expectedStatus: 201,
      );
      zlog('Registrazione riuscita per $email', tag: 'Auth');
      return data;
    } on Exception catch (e) {
      zlog('Registrazione fallita per $email: $e', tag: 'Auth');
      rethrow;
    }
  }

  /// Salva il token JWT nello storage sicuro.
  Future<void> saveToken(String token) =>
      _storage.write(key: kTokenKey, value: token);

  /// Restituisce il token salvato, o null se assente.
  Future<String?> getToken() => _storage.read(key: kTokenKey);

  /// Elimina il token salvato (logout).
  Future<void> logout() async {
    zlog('Logout: rimuovo il token', tag: 'Auth');
    await _storage.delete(key: kTokenKey);
  }

  /// Esegue una POST JSON pubblica (login/registrazione) e converte gli errori
  /// HTTP in Exception con messaggi human-readable pronti per la UI. Gli errori
  /// di rete sono già tradotti da [ApiClient].
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    required int expectedStatus,
  }) async {
    // authenticated:false → il 401 qui significa "credenziali errate", non
    // sessione scaduta, quindi va mappato come errore di login.
    final res = await _api.post(path, body: body, authenticated: false);
    if (res.statusCode == expectedStatus) {
      return res.map ?? const <String, dynamic>{};
    }
    throw Exception(_errorMessageFor(res.statusCode));
  }

  /// Mappa uno status code di errore del backend in un messaggio per la UI.
  String _errorMessageFor(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Dati non validi';
      case 401:
        return 'Email o password non corretti';
      case 409:
        return 'Email già in uso';
      default:
        return 'Errore del server, riprova più tardi';
    }
  }
}
