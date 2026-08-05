package main

import (
	"sync"
	"time"
)

type Item struct {
	ID        string    `json:"id"`
	Timestamp time.Time `json:"timestamp"`
}

type ItemStore struct {
	mu    sync.RWMutex
	items map[string]Item
	next  int
}

func NewItemStore() *ItemStore {
	return &ItemStore{
		items: make(map[string]Item),
		next:  1,
	}
}

func (s *ItemStore) Create(timestamp time.Time) Item {
	s.mu.Lock()
	defer s.mu.Unlock()

	id := s.nextID()
	item := Item{ID: id, Timestamp: timestamp}
	s.items[id] = item
	return item
}

func (s *ItemStore) Get(id string) (Item, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	item, ok := s.items[id]
	return item, ok
}

func (s *ItemStore) List() []Item {
	s.mu.RLock()
	defer s.mu.RUnlock()

	items := make([]Item, 0, len(s.items))
	for _, item := range s.items {
		items = append(items, item)
	}
	return items
}

func (s *ItemStore) Update(id string, timestamp time.Time) (Item, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	item, ok := s.items[id]
	if !ok {
		return Item{}, false
	}
	item.Timestamp = timestamp
	s.items[id] = item
	return item, true
}

func (s *ItemStore) Delete(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.items[id]; !ok {
		return false
	}
	delete(s.items, id)
	return true
}

func (s *ItemStore) nextID() string {
	id := s.next
	s.next++
	return "item-" + itoa(id)
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	digits := make([]byte, 0, 10)
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	return string(digits)
}
