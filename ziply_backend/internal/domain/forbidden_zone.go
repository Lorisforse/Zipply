package domain

// ForbiddenZone represents a no-go area (es. ZTL, parchi) stored in the
// forbidden_zones table. Polygon holds the area boundary as GeoJSON.
type ForbiddenZone struct {
	ID       string
	Nome     string
	Polygon  Polygon
	IsActive bool
}

// Polygon is the GeoJSON representation of an area boundary. Coordinates follow
// the GeoJSON convention: an array of linear rings, each a list of [lng, lat]
// pairs (the first ring is the outer boundary).
type Polygon struct {
	Type        string        `json:"type"`
	Coordinates [][][]float64 `json:"coordinates"`
}
