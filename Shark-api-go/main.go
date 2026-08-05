package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	store := NewItemStore()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", healthHandler)
	mux.HandleFunc("/items/", itemHandler(store))
	mux.HandleFunc("/items", itemsHandler(store))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Shark API listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}
