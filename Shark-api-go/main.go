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
	store, err := NewItemStore()
	if err != nil {
		log.Fatalf("initializing store: %v", err)
	}
	defer store.Close()

	clientID := os.Getenv("APPLE_CLIENT_ID")
	if clientID == "" {
		clientID = "com.somsak.Shark"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", healthHandler)
	mux.Handle("/items/", requireWriteKey(itemHandler(store)))
	mux.Handle("/items", requireWriteKey(itemsHandler(store)))
	mux.HandleFunc("POST /register", registerHandler(store))
	mux.HandleFunc("POST /login", loginHandler(store))
	mux.HandleFunc("POST /auth/apple", appleLoginHandler(store, clientID))
	mux.HandleFunc("GET /map", requireToken(store, mapHandler(store)))
	mux.HandleFunc("GET /videos", videosHandler)
	mux.Handle("GET /videos/", http.StripPrefix("/videos/", http.FileServer(http.Dir("MP4"))))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Shark API listening on :%s", port)
	handler := withLogging(withCORS(withRateLimit(mux)))
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatal(err)
	}
}
