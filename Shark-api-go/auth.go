package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
)

type User struct {
	ID           string    `json:"id"`
	Username     string    `json:"username"`
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"-"`
}

func registerHandler(store *ItemStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Username string `json:"username"`
			Password string `json:"password"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		username := strings.TrimSpace(req.Username)
		if len(username) < 3 || len(req.Password) < 4 {
			writeError(w, http.StatusBadRequest, "username must be at least 3 characters and password at least 4 characters")
			return
		}
		if _, ok := store.GetUserByUsername(username); ok {
			writeError(w, http.StatusConflict, "username already taken")
			return
		}
		hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to create user")
			return
		}
		user, err := store.CreateUser(username, string(hash))
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to create user")
			return
		}
		writeJSON(w, http.StatusCreated, user)
	}
}

func loginHandler(store *ItemStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Username string `json:"username"`
			Password string `json:"password"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		user, ok := store.GetUserByUsername(strings.TrimSpace(req.Username))
		if !ok || bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)) != nil {
			writeError(w, http.StatusUnauthorized, "invalid username or password")
			return
		}
		token, err := store.CreateSession(user.ID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to create session")
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{
			"token":    token,
			"username": user.Username,
		})
	}
}

func mapHandler(store *ItemStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"center": map[string]float64{"latitude": 13.7367, "longitude": 100.5231},
			"spots":  []any{},
		})
	}
}

func requireToken(store *ItemStore, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || !store.ValidateSession(token) {
			writeError(w, http.StatusUnauthorized, "missing or invalid token")
			return
		}
		next(w, r)
	}
}

func (s *ItemStore) CreateUser(username, passwordHash string) (User, error) {
	user := User{
		ID:           "user-" + randomHex(4),
		Username:     username,
		PasswordHash: passwordHash,
		CreatedAt:    time.Now().UTC(),
	}
	_, err := s.db.Exec(
		`INSERT INTO users (id, username, password_hash, created_at) VALUES (?, ?, ?, ?)`,
		user.ID,
		user.Username,
		user.PasswordHash,
		user.CreatedAt.Format(time.RFC3339Nano),
	)
	if err != nil {
		return User{}, err
	}
	return user, nil
}

func (s *ItemStore) GetUserByUsername(username string) (User, bool) {
	var id, hash string
	err := s.db.QueryRow(
		`SELECT id, password_hash FROM users WHERE username = ?`,
		username,
	).Scan(&id, &hash)
	if err != nil {
		return User{}, false
	}
	return User{ID: id, Username: username, PasswordHash: hash}, true
}

func (s *ItemStore) CreateSession(userID string) (string, error) {
	token := randomHex(32)
	_, err := s.db.Exec(
		`INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)`,
		token,
		userID,
		time.Now().UTC().Format(time.RFC3339Nano),
	)
	if err != nil {
		return "", err
	}
	return token, nil
}

func (s *ItemStore) ValidateSession(token string) bool {
	var userID string
	err := s.db.QueryRow(`SELECT user_id FROM sessions WHERE token = ?`, token).Scan(&userID)
	return err == nil
}

func randomHex(bytes int) string {
	buf := make([]byte, bytes)
	if _, err := rand.Read(buf); err != nil {
		return "0"
	}
	return hex.EncodeToString(buf)
}
