package main

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

func healthHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func itemsHandler(store *ItemStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			items, err := store.List()
			if err != nil {
				writeError(w, http.StatusInternalServerError, "failed to list items")
				return
			}
			writeJSON(w, http.StatusOK, items)
		case http.MethodPost:
			var req struct {
				Timestamp time.Time `json:"timestamp"`
			}
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				writeError(w, http.StatusBadRequest, "invalid request body")
				return
			}
			if req.Timestamp.IsZero() {
				req.Timestamp = time.Now()
			}
			item, err := store.Create(req.Timestamp)
			if err != nil {
				writeError(w, http.StatusInternalServerError, "failed to create item")
				return
			}
			writeJSON(w, http.StatusCreated, item)
		default:
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		}
	}
}

func itemHandler(store *ItemStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := strings.TrimPrefix(r.URL.Path, "/items/")

		switch r.Method {
		case http.MethodGet:
			item, ok := store.Get(id)
			if !ok {
				writeError(w, http.StatusNotFound, "item not found")
				return
			}
			writeJSON(w, http.StatusOK, item)
		case http.MethodPut:
			var req struct {
				Timestamp time.Time `json:"timestamp"`
			}
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				writeError(w, http.StatusBadRequest, "invalid request body")
				return
			}
			if req.Timestamp.IsZero() {
				writeError(w, http.StatusBadRequest, "timestamp is required")
				return
			}
			item, ok := store.Update(id, req.Timestamp)
			if !ok {
				writeError(w, http.StatusNotFound, "item not found")
				return
			}
			writeJSON(w, http.StatusOK, item)
		case http.MethodDelete:
			if !store.Delete(id) {
				writeError(w, http.StatusNotFound, "item not found")
				return
			}
			w.WriteHeader(http.StatusNoContent)
		default:
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		}
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
