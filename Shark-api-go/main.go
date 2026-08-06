package main

import (
	"log"
	"net/http"
	"os"
	"time"
)

func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}

func main() {
	store := NewItemStore()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", healthHandler)
	mux.HandleFunc("/items/", itemHandler(store))
	mux.HandleFunc("/items", itemsHandler(store))
	mux.Handle("GET /videos/", http.StripPrefix("/videos/", http.FileServer(http.Dir("MP4"))))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Shark API listening on :%s", port)
	if err := http.ListenAndServe(":"+port, withLogging(mux)); err != nil {
		log.Fatal(err)
	}
}
