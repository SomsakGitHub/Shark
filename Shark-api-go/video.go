package main

import (
	"encoding/json"
	"log"
	"net/http"
)

type Video struct {
	ID       string `json:"id"`
	FileName string `json:"fileName"`
	Username string `json:"username"`
	Caption  string `json:"caption"`
	Likes    int    `json:"likes"`
	Comments int    `json:"comments"`
	Shares   int    `json:"shares"`
	Music    string `json:"music"`
}

var videoCatalog = []Video{
	{ID: "1", FileName: "fireworks", Username: "@somsak", Caption: "Happy New Year from Bangkok", Likes: 123400, Comments: 2340, Shares: 890, Music: "original sound - som"},
	{ID: "2", FileName: "oneDancing", Username: "@kate_beat", Caption: "Day one of dancing", Likes: 45200, Comments: 670, Shares: 250, Music: "sure thing - miguel"},
	{ID: "3", FileName: "selfie", Username: "@proud_pearl", Caption: "Golden hour selfie", Likes: 89000, Comments: 1120, Shares: 340, Music: "sunset drive - playlist"},
	{ID: "4", FileName: "twoDancing", Username: "@dao_squad", Caption: "Us after two coffee shots", Likes: 67000, Comments: 890, Shares: 410, Music: "Snooze - sza"},
	{ID: "5", FileName: "threeDancing", Username: "@bank_bounce", Caption: "The crew never misses", Likes: 215000, Comments: 3200, Shares: 1450, Music: "Gata Only - FloyyMenor"},
}

func videosHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(videoCatalog); err != nil {
		log.Printf("error encoding videos: %v", err)
	}
}
