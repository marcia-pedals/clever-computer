package main

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"

	"github.com/BurntSushi/toml"
	"github.com/bradleyfalzon/ghinstallation/v2"
)

type Config struct {
	GitHub GitHubConfig `toml:"github"`
	Server ServerConfig `toml:"server"`
}

type GitHubConfig struct {
	AppID          int64  `toml:"app_id"`
	InstallationID int64  `toml:"installation_id"`
	PrivateKeyPath string `toml:"private_key_path"`
}

type ServerConfig struct {
	ListenAddr  string `toml:"listen_addr"`
	TLSCertPath string `toml:"tls_cert_path"`
	TLSKeyPath  string `toml:"tls_key_path"`
}

func main() {
	configPath := "config.toml"
	if len(os.Args) > 1 {
		configPath = os.Args[1]
	}

	var cfg Config
	if _, err := toml.DecodeFile(configPath, &cfg); err != nil {
		log.Fatalf("Failed to load config from %s: %v", configPath, err)
	}

	transport, err := ghinstallation.NewKeyFromFile(
		http.DefaultTransport,
		cfg.GitHub.AppID,
		cfg.GitHub.InstallationID,
		cfg.GitHub.PrivateKeyPath,
	)
	if err != nil {
		log.Fatalf("Failed to create GitHub App transport: %v", err)
	}

	githubURL, _ := url.Parse("https://github.com")
	apiURL, _ := url.Parse("https://api.github.com")

	proxy := &httputil.ReverseProxy{
		Director: func(req *http.Request) {
			token, err := transport.Token(context.Background())
			if err != nil {
				log.Printf("Failed to get installation token: %v", err)
				return
			}

			// Use Basic auth with x-access-token — required for git HTTP transport,
			// and also accepted by the REST and GraphQL APIs.
			basicAuth := base64.StdEncoding.EncodeToString([]byte("x-access-token:" + token))
			req.Header.Set("Authorization", "Basic "+basicAuth)
			req.Header.Del("X-Forwarded-For")

			// Clients (gh) treat this proxy as a GitHub Enterprise Server, which
			// uses /api/v3/* for REST and /api/graphql for GraphQL. We strip those
			// prefixes when forwarding to api.github.com, which serves both APIs
			// at its root (e.g. GHES /api/v3/repos/o/r → api.github.com/repos/o/r).
			if strings.HasPrefix(req.URL.Path, "/api/v3/") || req.URL.Path == "/api/v3" {
				req.URL.Scheme = apiURL.Scheme
				req.URL.Host = apiURL.Host
				req.Host = apiURL.Host
				req.URL.Path = strings.TrimPrefix(req.URL.Path, "/api/v3")
				if req.URL.Path == "" {
					req.URL.Path = "/"
				}
			} else if req.URL.Path == "/api/graphql" {
				req.URL.Scheme = apiURL.Scheme
				req.URL.Host = apiURL.Host
				req.Host = apiURL.Host
				req.URL.Path = "/graphql"
			} else {
				req.URL.Scheme = githubURL.Scheme
				req.URL.Host = githubURL.Host
				req.Host = githubURL.Host
			}
		},
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				MinVersion: tls.VersionTLS12,
			},
		},
	}

	mux := http.NewServeMux()
	mux.Handle("/", proxy)

	server := &http.Server{
		Addr:    cfg.Server.ListenAddr,
		Handler: mux,
	}

	log.Printf("Starting GitHub proxy on %s", cfg.Server.ListenAddr)
	log.Printf("  /api/v3/*    → api.github.com")
	log.Printf("  /api/graphql → api.github.com/graphql")
	log.Printf("  /*           → github.com")

	if err := server.ListenAndServeTLS(cfg.Server.TLSCertPath, cfg.Server.TLSKeyPath); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
