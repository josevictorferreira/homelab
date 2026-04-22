package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

type GrafanaAlert struct {
	Title       string            `json:"title"`
	State       string            `json:"state"`
	Message     string            `json:"message"`
	Annotations map[string]string `json:"annotations"`
	Labels      map[string]string `json:"labels"`
}

func main() {
	homeserver := os.Getenv("MATRIX_HOMESERVER")
	username := os.Getenv("MATRIX_USER")
	password := os.Getenv("MATRIX_PASSWORD")
	roomID := os.Getenv("MATRIX_ROOM_ID")
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	if homeserver == "" || username == "" || password == "" || roomID == "" {
		log.Fatal("MATRIX_HOMESERVER, MATRIX_USER, MATRIX_PASSWORD, and MATRIX_ROOM_ID must be set")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})
	mux.HandleFunc("/webhook", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "POST only", http.StatusMethodNotAllowed)
			return
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Failed to read body", http.StatusBadRequest)
			return
		}
		log.Printf("Received webhook: %s", string(body))

		var alerts map[string]interface{}
		if err := json.Unmarshal(body, &alerts); err != nil {
			log.Printf("Failed to parse JSON: %v", err)
			http.Error(w, "Invalid JSON", http.StatusBadRequest)
			return
		}

		msg := formatAlert(alerts)
		if err := sendMatrixMessage(homeserver, username, password, roomID, msg); err != nil {
			log.Printf("Failed to send Matrix message: %v", err)
			http.Error(w, "Failed to send", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	})

	log.Printf("Starting server on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}

func formatAlert(alerts map[string]interface{}) string {
	var lines []string

	if title, ok := alerts["title"].(string); ok && title != "" {
		lines = append(lines, fmt.Sprintf("**%s**", title))
	}
	if state, ok := alerts["state"].(string); ok && state != "" {
		lines = append(lines, fmt.Sprintf("State: %s", state))
	}
	if msg, ok := alerts["message"].(string); ok && msg != "" {
		lines = append(lines, msg)
	}
	if annotations, ok := alerts["annotations"].(map[string]interface{}); ok {
		for k, v := range annotations {
			if k != "summary" && k != "description" {
				lines = append(lines, fmt.Sprintf("%s: %v", k, v))
			}
		}
	}
	if labels, ok := alerts["labels"].(map[string]interface{}); ok {
		var labelParts []string
		for k, v := range labels {
			labelParts = append(labelParts, fmt.Sprintf("%s=%v", k, v))
		}
		if len(labelParts) > 0 {
			lines = append(lines, fmt.Sprintf("Labels: %s", strings.Join(labelParts, ", ")))
		}
	}

	if len(lines) == 0 {
		lines = append(lines, fmt.Sprintf("Alert received: %v", alerts))
	}

	return strings.Join(lines, "\n")
}

func sendMatrixMessage(homeserver, username, password, roomID, message string) error {
	loginURL := homeserver + "/_matrix/client/v3/login"
	loginData := map[string]string{
		"type":     "m.login.password",
		"user":     username,
		"password": password,
	}
	loginJSON, _ := json.Marshal(loginData)

	req, _ := http.NewRequest("POST", loginURL, bytes.NewBuffer(loginJSON))
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("login request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("login failed: %s", string(body))
	}

	var loginResp map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&loginResp); err != nil {
		return fmt.Errorf("failed to parse login response: %w", err)
	}
	accessToken, ok := loginResp["access_token"].(string)
	if !ok {
		return fmt.Errorf("no access token in login response")
	}

	sendURL := fmt.Sprintf("%s/_matrix/client/v3/rooms/%s/send/m.room.message",
		homeserver, url.PathEscape(roomID))
	txnID := fmt.Sprintf("msg-%d", time.Now().UnixNano())

	msgContent := map[string]interface{}{
		"msgtype": "m.text",
		"body":    message,
	}
	msgJSON, _ := json.Marshal(msgContent)
	req2, _ := http.NewRequest("PUT", sendURL+"?txn_id="+txnID, bytes.NewBuffer(msgJSON))
	req2.Header.Set("Content-Type", "application/json")
	req2.Header.Set("Authorization", "Bearer "+accessToken)
	resp2, err := client.Do(req2)
	if err != nil {
		return fmt.Errorf("send message failed: %w", err)
	}
	defer resp2.Body.Close()

	if resp2.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp2.Body)
		return fmt.Errorf("send message failed: %s", string(body))
	}
	log.Printf("Message sent to Matrix room %s", roomID)
	return nil
}