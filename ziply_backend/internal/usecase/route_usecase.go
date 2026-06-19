package usecase

import (
	"context"
	"encoding/json"
	"math"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/pkg/ors"
)

// vehicleByID astrae il recupero del singolo mezzo (posizione + tipologia).
type vehicleByID interface {
	GetByID(ctx context.Context, id string) (*domain.Vehicle, error)
}

// zoneLister astrae l'elenco delle zone vietate attive da escludere.
type zoneLister interface {
	ListActive(ctx context.Context) ([]domain.ForbiddenZone, error)
}

// orsClient astrae la chiamata Directions a OpenRouteService.
type orsClient interface {
	Directions(ctx context.Context, profile string, from, to ors.Point, avoidPolygons json.RawMessage) (*ors.Route, error)
}

// RouteUsecase calcola il percorso dal mezzo selezionato alla destinazione
// inserita dall'utente (UT.07), per tipologia di mezzo ed evitando le zone
// vietate. In caso di indisponibilità di OpenRouteService ricade su una linea
// diretta, così l'endpoint restituisce sempre un percorso utilizzabile.
type RouteUsecase struct {
	vehicles vehicleByID
	zones    zoneLister
	ors      orsClient
}

// NewRouteUsecase crea un RouteUsecase con le dipendenze indicate.
func NewRouteUsecase(vehicles vehicleByID, zones zoneLister, orsc orsClient) *RouteUsecase {
	return &RouteUsecase{vehicles: vehicles, zones: zones, ors: orsc}
}

// Compute restituisce il percorso più rapido dal mezzo [vehicleID] al punto
// (destLat, destLng). Ritorna domain.ErrVehicleNotFound se il mezzo non esiste.
func (uc *RouteUsecase) Compute(ctx context.Context, vehicleID string, destLat, destLng float64) (*domain.RouteResult, error) {
	v, err := uc.vehicles.GetByID(ctx, vehicleID)
	if err != nil {
		return nil, err
	}

	from := ors.Point{Lon: v.Longitude, Lat: v.Latitude}
	to := ors.Point{Lon: destLng, Lat: destLat}

	var result *domain.RouteResult
	route, err := uc.ors.Directions(ctx, ors.ProfileFor(v.Type), from, to, uc.avoidPolygons(ctx))
	if err != nil {
		// ORS non disponibile (chiave assente, timeout, ...): linea diretta.
		result = straightLine(from, to)
	} else {
		result = &domain.RouteResult{
			Geometry:        route.Geometry,
			DistanceMeters:  route.DistanceMeters,
			DurationSeconds: route.DurationSeconds,
			Fallback:        false,
		}
	}

	// UT.03 — Stima costo: durata stimata (in minuti) × tariffa al minuto del
	// mezzo selezionato. Vale sia per il percorso ORS sia per il fallback.
	result.EstimatedCost = (result.DurationSeconds / 60) * v.TariffaAlMinuto

	// UT.08 — Suggerimento tipologia in base alla distanza del percorso (la
	// stessa mostrata all'utente): oltre la soglia auto, sotto bici/monopattino.
	result.SuggestedType = domain.SuggestionLight
	if result.DistanceMeters >= suggestDistanceThresholdM {
		result.SuggestedType = domain.SuggestionCar
	}
	return result, nil
}

// suggestDistanceThresholdM è la soglia (in metri, sulla distanza del percorso)
// oltre la quale si consiglia l'auto e sotto bici/monopattino (UT.08).
const suggestDistanceThresholdM = 3000.0

// avoidPolygons fonde le zone vietate attive in un'unica geometria MultiPolygon
// GeoJSON per il parametro avoid_polygons di ORS, o nil se non ce ne sono. Le
// zone sono un vincolo best-effort: in caso di errore non bloccano il calcolo.
func (uc *RouteUsecase) avoidPolygons(ctx context.Context) json.RawMessage {
	zones, err := uc.zones.ListActive(ctx)
	if err != nil || len(zones) == 0 {
		return nil
	}

	polygons := make([]json.RawMessage, 0, len(zones))
	for _, z := range zones {
		var geom struct {
			Type        string          `json:"type"`
			Coordinates json.RawMessage `json:"coordinates"`
		}
		if err := json.Unmarshal(z.Polygon, &geom); err != nil {
			continue
		}
		switch geom.Type {
		case "Polygon":
			polygons = append(polygons, geom.Coordinates)
		case "MultiPolygon":
			var parts []json.RawMessage
			if err := json.Unmarshal(geom.Coordinates, &parts); err != nil {
				continue
			}
			polygons = append(polygons, parts...)
		}
	}
	if len(polygons) == 0 {
		return nil
	}

	out, err := json.Marshal(map[string]any{
		"type":        "MultiPolygon",
		"coordinates": polygons,
	})
	if err != nil {
		return nil
	}
	return out
}

// straightLine costruisce il percorso di ripiego (linea diretta) con una stima
// di durata basata su una velocità urbana media.
func straightLine(from, to ors.Point) *domain.RouteResult {
	geom, _ := json.Marshal(map[string]any{
		"type":        "LineString",
		"coordinates": [][2]float64{{from.Lon, from.Lat}, {to.Lon, to.Lat}},
	})
	dist := haversineMeters(from.Lat, from.Lon, to.Lat, to.Lon)
	const fallbackSpeedMS = 5.0 // ~18 km/h
	return &domain.RouteResult{
		Geometry:        geom,
		DistanceMeters:  dist,
		DurationSeconds: dist / fallbackSpeedMS,
		Fallback:        true,
	}
}

// haversineMeters è la distanza in metri tra due coordinate (formula haversine).
func haversineMeters(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadiusM = 6371000.0
	p1 := lat1 * math.Pi / 180
	p2 := lat2 * math.Pi / 180
	dp := (lat2 - lat1) * math.Pi / 180
	dl := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dp/2)*math.Sin(dp/2) + math.Cos(p1)*math.Cos(p2)*math.Sin(dl/2)*math.Sin(dl/2)
	return earthRadiusM * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}
