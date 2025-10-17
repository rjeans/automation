package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/automation/cluster-dashboard/internal/handlers"
	"github.com/automation/cluster-dashboard/internal/k8s"
	"github.com/automation/cluster-dashboard/internal/metrics"
	"github.com/automation/cluster-dashboard/internal/talos"
)

func main() {
	log.Println("Starting Cluster Dashboard...")

	// Initialize Kubernetes client
	k8sClient, err := k8s.NewClient()
	if err != nil {
		log.Fatalf("Failed to create Kubernetes client: %v", err)
	}
	log.Println("Kubernetes client initialized")

	// Initialize Talos client
	talosClient, err := talos.NewClient()
	if err != nil {
		log.Printf("Warning: Failed to create Talos client: %v", err)
		log.Println("Continuing with limited functionality...")
	} else {
		log.Println("Talos client initialized")
	}

	// Create metrics collector with 30-second cache
	collector := metrics.NewMetricsCollector(k8sClient, talosClient, 30*time.Second)
	log.Println("Metrics collector initialized")

	// Create dashboard handler
	dashboardHandler, err := handlers.NewDashboardHandler(collector)
	if err != nil {
		log.Fatalf("Failed to create dashboard handler: %v", err)
	}
	log.Println("Dashboard handler initialized")

	// Setup HTTP routes
	mux := http.NewServeMux()
	mux.HandleFunc("/", dashboardHandler.ServeIndex)
	mux.HandleFunc("/metrics/json", dashboardHandler.ServeMetrics)
	mux.HandleFunc("/metrics/html", dashboardHandler.ServeMetricsHTML)
	mux.HandleFunc("/healthz", dashboardHandler.ServeHealth)
	mux.HandleFunc("/readiness", dashboardHandler.ServeReadiness)

	// Create HTTP server
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in a goroutine
	go func() {
		log.Printf("Server listening on port %s", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server stopped")
}
