package main

import (
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

const (
	itemTable = `CREATE TABLE IF NOT EXISTS items (
		id         TEXT PRIMARY KEY,
		timestamp  TEXT NOT NULL
	);`
	metaTable = `CREATE TABLE IF NOT EXISTS meta (
		key   TEXT PRIMARY KEY,
		value INTEGER NOT NULL
	);`
	userTable = `CREATE TABLE IF NOT EXISTS users (
		id            TEXT PRIMARY KEY,
		username      TEXT NOT NULL UNIQUE,
		password_hash TEXT NOT NULL,
		created_at    TEXT NOT NULL
	);`
	sessionTable = `CREATE TABLE IF NOT EXISTS sessions (
		token      TEXT PRIMARY KEY,
		user_id    TEXT NOT NULL,
		created_at TEXT NOT NULL
	);`
	appleUserTable = `CREATE TABLE IF NOT EXISTS apple_users (
		apple_sub  TEXT PRIMARY KEY,
		user_id    TEXT NOT NULL UNIQUE,
		created_at TEXT NOT NULL
	);`
)

type Item struct {
	ID        string    `json:"id"`
	Timestamp time.Time `json:"timestamp"`
}

type ItemStore struct {
	db *sql.DB
}

func NewItemStore() (*ItemStore, error) {
	path := os.Getenv("DB_PATH")
	if path == "" {
		path = filepath.Join(".", "shark.db")
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("creating data dir: %w", err)
	}

	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("opening database: %w", err)
	}

	if _, err := db.Exec(itemTable); err != nil {
		return nil, fmt.Errorf("creating items table: %w", err)
	}
	if _, err := db.Exec(metaTable); err != nil {
		return nil, fmt.Errorf("creating meta table: %w", err)
	}
	if _, err := db.Exec(userTable); err != nil {
		return nil, fmt.Errorf("creating users table: %w", err)
	}
	if _, err := db.Exec(sessionTable); err != nil {
		return nil, fmt.Errorf("creating sessions table: %w", err)
	}
	if _, err := db.Exec(appleUserTable); err != nil {
		return nil, fmt.Errorf("creating apple users table: %w", err)
	}

	return &ItemStore{db: db}, nil
}

func (s *ItemStore) Close() error {
	return s.db.Close()
}

func (s *ItemStore) Create(timestamp time.Time) (Item, error) {
	id := fmt.Sprintf("item-%d", s.nextID())
	_, err := s.db.Exec(
		`INSERT INTO items (id, timestamp) VALUES (?, ?)`,
		id,
		timestamp.UTC().Format(time.RFC3339Nano),
	)
	if err != nil {
		return Item{}, fmt.Errorf("inserting item: %w", err)
	}
	return Item{ID: id, Timestamp: timestamp}, nil
}

func (s *ItemStore) Get(id string) (Item, bool) {
	var ts string
	err := s.db.QueryRow(`SELECT timestamp FROM items WHERE id = ?`, id).Scan(&ts)
	if errors.Is(err, sql.ErrNoRows) {
		return Item{}, false
	}
	if err != nil {
		return Item{}, false
	}
	item, err := parseItem(id, ts)
	if err != nil {
		return Item{}, false
	}
	return item, true
}

func (s *ItemStore) List() ([]Item, error) {
	rows, err := s.db.Query(`SELECT id, timestamp FROM items ORDER BY timestamp DESC`)
	if err != nil {
		return nil, fmt.Errorf("querying items: %w", err)
	}
	defer rows.Close()

	items := make([]Item, 0, 16)
	for rows.Next() {
		var id, ts string
		if err := rows.Scan(&id, &ts); err != nil {
			return nil, fmt.Errorf("scanning item: %w", err)
		}
		item, err := parseItem(id, ts)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating items: %w", err)
	}
	return items, nil
}

func (s *ItemStore) Update(id string, timestamp time.Time) (Item, bool) {
	res, err := s.db.Exec(
		`UPDATE items SET timestamp = ? WHERE id = ?`,
		timestamp.UTC().Format(time.RFC3339Nano),
		id,
	)
	if err != nil {
		return Item{}, false
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return Item{}, false
	}
	return Item{ID: id, Timestamp: timestamp}, true
}

func (s *ItemStore) Delete(id string) bool {
	res, err := s.db.Exec(`DELETE FROM items WHERE id = ?`, id)
	if err != nil {
		return false
	}
	affected, _ := res.RowsAffected()
	return affected > 0
}

func (s *ItemStore) nextID() int64 {
	var next int64
	err := s.db.QueryRow(
		`INSERT INTO meta (key, value) VALUES ('next_id', 1)
		 ON CONFLICT(key) DO UPDATE SET value = value + 1
		 RETURNING value`,
	).Scan(&next)
	if err != nil {
		return 1
	}
	return next
}

func parseItem(id, ts string) (Item, error) {
	t, err := time.Parse(time.RFC3339Nano, ts)
	if err != nil {
		return Item{}, fmt.Errorf("parsing timestamp %q: %w", ts, err)
	}
	return Item{ID: id, Timestamp: t}, nil
}
