// Package ors è un client minimale per la Directions API di OpenRouteService,
// usato per calcolare il percorso più rapido tra due punti per un dato profilo
// di mezzo, eventualmente evitando le zone vietate (avoid_polygons).
//
// La chiave API è letta dalla variabile d'ambiente ORS_API_KEY. Il client non
// gestisce il fallback: in caso di errore ritorna error e spetta al chiamante
// (es. l'endpoint /routes) ricadere su una linea diretta.
package ors

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

const baseURL = "https://api.openrouteservice.org"

// Profili di navigazione usati da Ziply.
const (
	ProfileCycling = "cycling-regular" // bici e monopattini
	ProfileDriving = "driving-car"     // automobili
)

// ProfileFor mappa il nome della tipologia di mezzo sul profilo ORS: le
// automobili usano driving-car, tutti gli altri mezzi cycling-regular (che
// privilegia piste ciclabili ed evita le superstrade).
func ProfileFor(vehicleTypeName string) string {
	n := strings.ToLower(vehicleTypeName)
	if strings.Contains(n, "auto") || strings.Contains(n, "car") {
		return ProfileDriving
	}
	return ProfileCycling
}

// Client chiama la Directions API di OpenRouteService.
type Client struct {
	apiKey string
	http   *http.Client
}

// New crea un Client leggendo ORS_API_KEY dall'ambiente.
func New() *Client {
	return &Client{
		apiKey: os.Getenv("ORS_API_KEY"),
		http:   &http.Client{Timeout: 10 * time.Second},
	}
}

// Point è una coordinata [longitudine, latitudine] (ORS usa l'ordine lon,lat).
type Point struct {
	Lon float64
	Lat float64
}

// Route è il risultato di una chiamata Directions.
type Route struct {
	Geometry        json.RawMessage // geometria GeoJSON (LineString)
	DistanceMeters  float64
	DurationSeconds float64
}

// ErrNoAPIKey è ritornato quando ORS_API_KEY non è configurata.
var ErrNoAPIKey = fmt.Errorf("ORS_API_KEY non configurata")

// Directions calcola il percorso più rapido da `from` a `to` con `profile`,
// evitando opzionalmente `avoidPolygons` (una geometria GeoJSON Polygon o
// MultiPolygon; nil per non escludere nulla). Ritorna error in caso di
// fallimento: il chiamante è atteso ricadere su una linea diretta.
func (c *Client) Directions(ctx context.Context, profile string, from, to Point, avoidPolygons json.RawMessage) (*Route, error) {
	if c.apiKey == "" {
		return nil, ErrNoAPIKey
	}

	reqBody := map[string]any{
		"coordinates": [][2]float64{{from.Lon, from.Lat}, {to.Lon, to.Lat}},
	}
	if len(avoidPolygons) > 0 {
		reqBody["options"] = map[string]any{"avoid_polygons": avoidPolygons}
	}
	payload, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/v2/directions/%s/geojson", baseURL, profile)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("openrouteservice: status %d", resp.StatusCode)
	}

	var decoded struct {
		Features []struct {
			Geometry   json.RawMessage `json:"geometry"`
			Properties struct {
				Summary struct {
					Distance float64 `json:"distance"`
					Duration float64 `json:"duration"`
				} `json:"summary"`
			} `json:"properties"`
		} `json:"features"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		return nil, err
	}
	if len(decoded.Features) == 0 {
		return nil, fmt.Errorf("openrouteservice: nessun percorso trovato")
	}

	f := decoded.Features[0]
	return &Route{
		Geometry:        f.Geometry,
		DistanceMeters:  f.Properties.Summary.Distance,
		DurationSeconds: f.Properties.Summary.Duration,
	}, nil
}
