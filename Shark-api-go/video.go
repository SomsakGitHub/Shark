package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
)

type Video struct {
	ID       string `json:"id"`
	FileName string `json:"fileName"`
	VideoURL string `json:"videoUrl"`
	Username string `json:"username"`
	Caption  string `json:"caption"`
	Likes    int    `json:"likes"`
	Comments int    `json:"comments"`
	Shares   int    `json:"shares"`
	Music    string `json:"music"`
}

type VideosResponse struct {
	Videos  []Video `json:"videos"`
	HasMore bool    `json:"hasMore"`
}

var videoCatalog = []Video{
	{ID: "1", FileName: "fireworks", Username: "@somsak", Caption: "Happy New Year from Bangkok", Likes: 123400, Comments: 2340, Shares: 890, Music: "original sound - som"},
	{ID: "2", FileName: "oneDancing", Username: "@kate_beat", Caption: "Day one of dancing", Likes: 45200, Comments: 670, Shares: 250, Music: "sure thing - miguel"},
	{ID: "3", FileName: "selfie", Username: "@proud_pearl", Caption: "Golden hour selfie", Likes: 89000, Comments: 1120, Shares: 340, Music: "sunset drive - playlist"},
	{ID: "4", FileName: "twoDancing", Username: "@dao_squad", Caption: "Us after two coffee shots", Likes: 67000, Comments: 890, Shares: 410, Music: "Snooze - sza"},
	{ID: "5", FileName: "threeDancing", Username: "@bank_bounce", Caption: "The crew never misses", Likes: 215000, Comments: 3200, Shares: 1450, Music: "Gata Only - FloyyMenor"},
}

func videosHandler(w http.ResponseWriter, r *http.Request) {
	limit, offset := paginationParams(r)

	start := offset
	end := start + limit
	if end > len(videoCatalog) {
		end = len(videoCatalog)
	}
	if start > len(videoCatalog) {
		start = len(videoCatalog)
	}

	base := videoBaseURL(r)
	page := make([]Video, 0, limit)
	for _, v := range videoCatalog[start:end] {
		v.VideoURL = base + v.FileName + ".mp4"
		page = append(page, v)
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(VideosResponse{
		Videos:  page,
		HasMore: end < len(videoCatalog),
	}); err != nil {
		log.Printf("error encoding videos: %v", err)
	}
}

func paginationParams(r *http.Request) (limit, offset int) {
	limit = 20
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			limit = n
		}
	}
	if limit > 50 {
		limit = 50
	}

	offset = 0
	if raw := r.URL.Query().Get("offset"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			offset = n
		}
	}
	return limit, offset
}

func videoBaseURL(r *http.Request) string {
	scheme := "http"
	if proto := r.Header.Get("X-Forwarded-Proto"); proto != "" {
		scheme = proto
	}
	return scheme + "://" + r.Host + "/videos/"
}
