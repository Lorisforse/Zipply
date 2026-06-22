package middleware

import (
	"net/http"
	"os"
	"strings"
)

// CORS aggiunge gli header CORS necessari quando la dashboard web e il backend
// stanno su origini diverse. Serve in particolare allo sviluppo locale senza
// Docker: `flutter run -d chrome` serve la pagina su localhost:<porta-random>,
// che è un'origine diversa da localhost:8080 → senza questi header il browser
// blocca le richieste. In produzione, se la web è servita dallo stesso host del
// backend (same-origin via reverse proxy), questi header sono semplicemente
// innocui.
//
// Le origini ammesse si configurano con la variabile d'ambiente
// CORS_ALLOWED_ORIGINS (lista separata da virgola). Default: "*" (qualsiasi
// origine), comodo in locale; in produzione si può restringere al proprio host.
// Gestisce il preflight OPTIONS rispondendo 204 senza raggiungere il router.
func CORS(next http.Handler) http.Handler {
	allowed := parseOrigins(os.Getenv("CORS_ALLOWED_ORIGINS"))
	allowAny := len(allowed) == 0 || contains(allowed, "*")

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" {
			if allowAny {
				w.Header().Set("Access-Control-Allow-Origin", "*")
			} else if contains(allowed, origin) {
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Add("Vary", "Origin")
			}
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Max-Age", "3600")
		}

		// Preflight: il browser chiede i permessi prima della richiesta vera.
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// parseOrigins normalizza la lista di origini dalla env (separata da virgola),
// scartando spazi ed elementi vuoti.
func parseOrigins(raw string) []string {
	var origins []string
	for _, o := range strings.Split(raw, ",") {
		if trimmed := strings.TrimSpace(o); trimmed != "" {
			origins = append(origins, trimmed)
		}
	}
	return origins
}

func contains(list []string, target string) bool {
	for _, v := range list {
		if v == target {
			return true
		}
	}
	return false
}
