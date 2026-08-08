package main

import (
	"crypto/rsa"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	appleJWKSURL = "https://appleid.apple.com/auth/keys"
	appleIssuer  = "https://appleid.apple.com"
	appleKeyTTL  = 6 * time.Hour
)

type appleJWKS struct {
	Keys []appleJWK `json:"keys"`
}

type appleJWK struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type appleClaims struct {
	Email          string `json:"email"`
	EmailVerified  bool   `json:"email_verified"`
	IsPrivateEmail bool   `json:"is_private_email"`
	jwt.RegisteredClaims
}

var jwksStore = struct {
	mu        sync.Mutex
	keys      map[string]*rsa.PublicKey
	fetchedAt time.Time
}{keys: make(map[string]*rsa.PublicKey)}

func refreshAppleKeys() error {
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(appleJWKSURL)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	var jwks appleJWKS
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return err
	}

	keys := make(map[string]*rsa.PublicKey, len(jwks.Keys))
	for _, k := range jwks.Keys {
		if k.Kty != "RSA" || k.N == "" || k.E == "" {
			continue
		}
		nBytes, err := base64.RawURLEncoding.DecodeString(k.N)
		if err != nil {
			continue
		}
		eBytes, err := base64.RawURLEncoding.DecodeString(k.E)
		if err != nil {
			continue
		}
		e := 0
		for _, b := range eBytes {
			e = e<<8 | int(b)
		}
		keys[k.Kid] = &rsa.PublicKey{N: new(big.Int).SetBytes(nBytes), E: e}
	}

	jwksStore.mu.Lock()
	jwksStore.keys = keys
	jwksStore.fetchedAt = time.Now()
	jwksStore.mu.Unlock()
	return nil
}

func applePublicKey(kid string) (*rsa.PublicKey, error) {
	jwksStore.mu.Lock()
	key, ok := jwksStore.keys[kid]
	stale := time.Since(jwksStore.fetchedAt) > appleKeyTTL
	jwksStore.mu.Unlock()

	if ok && !stale {
		return key, nil
	}
	if err := refreshAppleKeys(); err != nil {
		if ok {
			return key, nil
		}
		return nil, err
	}

	jwksStore.mu.Lock()
	key, ok = jwksStore.keys[kid]
	jwksStore.mu.Unlock()
	if !ok {
		return nil, errors.New("unknown Apple key id")
	}
	return key, nil
}

func verifyAppleToken(identityToken, clientID string) (*appleClaims, error) {
	token, err := jwt.ParseWithClaims(identityToken, &appleClaims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method %v", t.Header["alg"])
		}
		kid, _ := t.Header["kid"].(string)
		return applePublicKey(kid)
	},
		jwt.WithIssuer(appleIssuer),
		jwt.WithAudience(clientID),
		jwt.WithValidMethods([]string{"RS256"}),
	)
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*appleClaims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid Apple identity token")
	}
	return claims, nil
}

func appleLoginHandler(store *ItemStore, clientID string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			IdentityToken string `json:"identityToken"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		if strings.TrimSpace(req.IdentityToken) == "" {
			writeError(w, http.StatusBadRequest, "identityToken is required")
			return
		}

		claims, err := verifyAppleToken(req.IdentityToken, clientID)
		if err != nil {
			log.Printf("apple sign-in rejected: %v", err)
			writeError(w, http.StatusUnauthorized, "invalid Apple identity token")
			return
		}

		user, err := store.GetOrCreateAppleUser(claims.Subject, claims.Email)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "failed to sign in")
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

func (s *ItemStore) GetOrCreateAppleUser(appleSub, email string) (User, error) {
	var userID string
	err := s.db.QueryRow(`SELECT user_id FROM apple_users WHERE apple_sub = ?`, appleSub).Scan(&userID)
	if err == nil {
		return s.getUserByID(userID)
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return User{}, err
	}

	username := email
	if username == "" {
		username = "apple-" + truncateSub(appleSub)
	}
	if _, exists := s.GetUserByUsername(username); exists {
		username = "apple-" + truncateSub(appleSub)
	}

	user := User{
		ID:        "user-" + randomHex(4),
		Username:  username,
		CreatedAt: time.Now().UTC(),
	}

	tx, err := s.db.Begin()
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(
		`INSERT INTO users (id, username, password_hash, created_at) VALUES (?, ?, '', ?)`,
		user.ID, user.Username, user.CreatedAt.Format(time.RFC3339Nano),
	); err != nil {
		return User{}, err
	}
	if _, err := tx.Exec(
		`INSERT INTO apple_users (apple_sub, user_id, created_at) VALUES (?, ?, ?)`,
		appleSub, user.ID, user.CreatedAt.Format(time.RFC3339Nano),
	); err != nil {
		return User{}, err
	}
	if err := tx.Commit(); err != nil {
		return User{}, err
	}
	return user, nil
}

func (s *ItemStore) getUserByID(id string) (User, error) {
	var username, passwordHash string
	err := s.db.QueryRow(
		`SELECT username, password_hash FROM users WHERE id = ?`,
		id,
	).Scan(&username, &passwordHash)
	if err != nil {
		return User{}, err
	}
	return User{ID: id, Username: username, PasswordHash: passwordHash}, nil
}

func truncateSub(sub string) string {
	if len(sub) > 10 {
		return sub[:10]
	}
	return sub
}
