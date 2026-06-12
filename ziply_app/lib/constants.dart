// Costanti globali dell'applicazione Ziply.

const String kBaseUrl = 'https://api.lorisamato.it/ziply/api';
const String kTokenKey = 'ziply_auth_token';

// API key Stadia Maps per il basemap scuro della mappa (https://stadiamaps.com).
// Chiave gratuita: registrati → Manage Properties → Add API Key.
// Consigliato: restringi la chiave per bundle id / dominio nel dashboard Stadia.
// Si può anche passare a build-time con --dart-define=STADIA_API_KEY=...
const String kStadiaApiKey = String.fromEnvironment(
  'STADIA_API_KEY',
  defaultValue: '115ed5f2-c838-4545-8756-3c76217b3c01',
);
