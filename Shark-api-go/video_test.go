package main

import (
	"math"
	"testing"
)

func TestMockLocationsWithinRadius(t *testing.T) {
	for _, v := range videoCatalog {
		lat, lng := mockLocation(v.ID)
		if d := haversineKm(mockCenterLat, mockCenterLng, lat, lng); d > mockRadiusKm {
			t.Fatalf("video %s at %.6f,%.6f is %.2f km away", v.ID, lat, lng, d)
		}
	}
}

func haversineKm(lat1, lng1, lat2, lng2 float64) float64 {
	const r = 6371.0
	la1 := lat1 * math.Pi / 180
	la2 := lat2 * math.Pi / 180
	dla := (lat2 - lat1) * math.Pi / 180
	dlng := (lng2 - lng1) * math.Pi / 180
	a := math.Sin(dla/2)*math.Sin(dla/2) +
		math.Cos(la1)*math.Cos(la2)*math.Sin(dlng/2)*math.Sin(dlng/2)
	return 2 * r * math.Asin(math.Sqrt(a))
}
