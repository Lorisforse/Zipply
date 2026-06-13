package domain

import "encoding/json"

// ForbiddenZone represents a no-go area (es. ZTL, parchi, quartieri) stored in
// the forbidden_zones table. Polygon holds the area boundary as a raw GeoJSON
// geometry: può essere un Polygon o un MultiPolygon. Il backend non la
// interpreta, la inoltra così com'è al client.
type ForbiddenZone struct {
	ID       string
	Nome     string
	Polygon  json.RawMessage
	IsActive bool
}
