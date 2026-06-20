package domain

import (
	"math"
	"testing"
)

// TestScheduledPreAuth verifica la formula della preautorizzazione progressiva.
// La formula è: hourlyRate * 0.5 * (1 + advanceHours/24), arrotondata ai centesimi.
func TestScheduledPreAuth(t *testing.T) {
	tests := []struct {
		name        string
		hourlyRate  float64
		advanceHours float64
		want        float64
	}{
		{
			name:         "0h anticipo (minimo teorico)",
			hourlyRate:   6.0,
			advanceHours: 0,
			// 6.0 * 0.5 * (1 + 0/24) = 3.00
			want: 3.00,
		},
		{
			name:         "1h anticipo",
			hourlyRate:   6.0,
			advanceHours: 1,
			// 6.0 * 0.5 * (1 + 1/24) = 3.0 * 1.04167 = 3.125 → 3.13
			want: 3.13,
		},
		{
			name:         "12h anticipo",
			hourlyRate:   6.0,
			advanceHours: 12,
			// 6.0 * 0.5 * (1 + 12/24) = 3.0 * 1.5 = 4.50
			want: 4.50,
		},
		{
			name:         "24h anticipo (massimo)",
			hourlyRate:   6.0,
			advanceHours: 24,
			// 6.0 * 0.5 * (1 + 24/24) = 3.0 * 2 = 6.00
			want: 6.00,
		},
		{
			name:         "bici economica (3€/h) — 12h",
			hourlyRate:   3.0,
			advanceHours: 12,
			// 3.0 * 0.5 * 1.5 = 2.25
			want: 2.25,
		},
		{
			name:         "auto costosa (12€/h) — 24h",
			hourlyRate:   12.0,
			advanceHours: 24,
			// 12.0 * 0.5 * 2 = 12.00
			want: 12.00,
		},
		{
			name:         "arrotondamento centesimi",
			hourlyRate:   5.0,
			advanceHours: 1,
			// 5.0 * 0.5 * (1 + 1/24) = 2.5 * 1.04167 = 2.604... → 2.60
			want: 2.60,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ScheduledPreAuth(tt.hourlyRate, tt.advanceHours)
			if math.Abs(got-tt.want) > 0.005 {
				t.Errorf("ScheduledPreAuth(%.2f, %.1f) = %.4f, want %.2f",
					tt.hourlyRate, tt.advanceHours, got, tt.want)
			}
		})
	}
}
