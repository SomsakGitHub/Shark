package main

import (
	"crypto/rand"
	"crypto/rsa"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func TestRefreshAppleKeys(t *testing.T) {
	if err := refreshAppleKeys(); err != nil {
		t.Fatalf("refreshAppleKeys failed (network?): %v", err)
	}
	if len(jwksStore.keys) == 0 {
		t.Fatal("no keys fetched from Apple JWKS")
	}
	for kid, key := range jwksStore.keys {
		if key.N == nil || key.N.BitLen() < 1024 || key.E == 0 {
			t.Fatalf("key %s is not a valid RSA public key", kid)
		}
	}
}

func TestVerifyAppleToken(t *testing.T) {
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}

	jwksStore.mu.Lock()
	jwksStore.keys["testkid"] = &priv.PublicKey
	jwksStore.fetchedAt = time.Now()
	jwksStore.mu.Unlock()

	now := time.Now()
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, &appleClaims{
		Email:          "somsak@example.com",
		EmailVerified:  true,
		IsPrivateEmail: false,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   "001234.5a6b7c8d",
			Issuer:    appleIssuer,
			Audience:  jwt.ClaimStrings{"com.somsak.Shark"},
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(time.Hour)),
		},
	})
	token.Header["kid"] = "testkid"
	signed, err := token.SignedString(priv)
	if err != nil {
		t.Fatal(err)
	}

	claims, err := verifyAppleToken(signed, "com.somsak.Shark")
	if err != nil {
		t.Fatalf("valid token rejected: %v", err)
	}
	if claims.Subject != "001234.5a6b7c8d" {
		t.Fatalf("unexpected subject: %s", claims.Subject)
	}
}

func TestVerifyAppleTokenWrongAudience(t *testing.T) {
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	jwksStore.mu.Lock()
	jwksStore.keys["testkid"] = &priv.PublicKey
	jwksStore.fetchedAt = time.Now()
	jwksStore.mu.Unlock()

	now := time.Now()
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, &appleClaims{
		Email: "x@example.com",
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   "001234.5a6b7c8d",
			Issuer:    appleIssuer,
			Audience:  jwt.ClaimStrings{"com.someone.else"},
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(time.Hour)),
		},
	})
	token.Header["kid"] = "testkid"
	signed, err := token.SignedString(priv)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := verifyAppleToken(signed, "com.somsak.Shark"); err == nil {
		t.Fatal("token with wrong audience should be rejected")
	}
}
