package domain

import "encoding/json"

// RouteResult è il percorso calcolato da un mezzo a una destinazione (UT.07).
// Geometry è una LineString GeoJSON pronta per essere disegnata sulla mappa.
// Fallback è true quando OpenRouteService non era disponibile e si è ricaduti
// su una linea diretta, così il chiamante può segnalarlo.
type RouteResult struct {
	Geometry        json.RawMessage
	DistanceMeters  float64
	DurationSeconds float64
	Fallback        bool
}
