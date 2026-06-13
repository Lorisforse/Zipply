/// Lanciata dai servizi quando il backend risponde 401: il token JWT è
/// assente, scaduto o non valido e l'utente deve autenticarsi di nuovo.
/// Le schermate la intercettano per pulire il token e tornare al login.
class SessionExpiredException implements Exception {
  const SessionExpiredException([
    this.message = 'Sessione scaduta, effettua di nuovo l\'accesso',
  ]);

  final String message;

  @override
  String toString() => 'SessionExpiredException: $message';
}
