package domain

import (
	"testing"
	"time"
)

func TestDiscountCodeUsable(t *testing.T) {
	now := time.Date(2026, 6, 19, 12, 0, 0, 0, time.UTC)
	base := DiscountCode{
		ValidFrom:  now.Add(-24 * time.Hour),
		ValidUntil: now.Add(24 * time.Hour),
		IsActive:   true,
		MaxUses:    5,
		UsedCount:  0,
	}

	tests := []struct {
		name   string
		mutate func(*DiscountCode)
		want   bool
	}{
		{"valido", func(*DiscountCode) {}, true},
		{"disattivato", func(d *DiscountCode) { d.IsActive = false }, false},
		{"non ancora valido", func(d *DiscountCode) { d.ValidFrom = now.Add(1 * time.Hour) }, false},
		{"scaduto", func(d *DiscountCode) { d.ValidUntil = now.Add(-1 * time.Hour) }, false},
		{"esaurito", func(d *DiscountCode) { d.UsedCount = d.MaxUses }, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d := base
			tt.mutate(&d)
			if got := d.Usable(now); got != tt.want {
				t.Errorf("Usable() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestApplyDiscount(t *testing.T) {
	tests := []struct {
		name          string
		cost          float64
		percentage    float64
		wantDiscounted float64
		wantDiscount   float64
	}{
		{"sconto 10% su 10€", 10.00, 10, 9.00, 1.00},
		{"sconto 20% su 3,50€", 3.50, 20, 2.80, 0.70},
		{"sconto 15% con arrotondamento", 3.33, 15, 2.83, 0.50},
		{"percentuale nulla", 10.00, 0, 10.00, 0},
		{"costo nullo (corsa gratis)", 0, 20, 0, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			discounted, discount := ApplyDiscount(tt.cost, tt.percentage)
			if discounted != tt.wantDiscounted {
				t.Errorf("discounted = %.2f, want %.2f", discounted, tt.wantDiscounted)
			}
			if discount != tt.wantDiscount {
				t.Errorf("discount = %.2f, want %.2f", discount, tt.wantDiscount)
			}
		})
	}
}
