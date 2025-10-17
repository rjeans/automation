package handlers

import (
	"encoding/json"
	"html/template"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/automation/cluster-dashboard/internal/metrics"
)

// DashboardHandler handles dashboard requests
type DashboardHandler struct {
	collector metrics.Collector
	templates *template.Template
}

// NewDashboardHandler creates a new dashboard handler
func NewDashboardHandler(collector metrics.Collector) (*DashboardHandler, error) {
	// Determine template path - support both local development and container deployment
	templatePath := os.Getenv("TEMPLATE_PATH")
	if templatePath == "" {
		// Check if running in container
		if _, err := os.Stat("/app/web/templates"); err == nil {
			templatePath = "/app/web/templates/*.html"
		} else {
			// Default to local development path
			templatePath = "web/templates/*.html"
		}
	}

	// Parse templates
	tmpl, err := template.ParseGlob(templatePath)
	if err != nil {
		// Try absolute path from current working directory
		if !filepath.IsAbs(templatePath) {
			wd, _ := os.Getwd()
			absPath := filepath.Join(wd, templatePath)
			tmpl, err = template.ParseGlob(absPath)
		}
		if err != nil {
			return nil, err
		}
	}

	return &DashboardHandler{
		collector: collector,
		templates: tmpl,
	}, nil
}

// ServeIndex serves the main dashboard page
func (h *DashboardHandler) ServeIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	err := h.templates.ExecuteTemplate(w, "index.html", nil)
	if err != nil {
		log.Printf("Error rendering template: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
	}
}

// ServeMetrics serves the metrics data as JSON
func (h *DashboardHandler) ServeMetrics(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	metrics, err := h.collector.Collect(ctx)
	if err != nil {
		log.Printf("Error collecting metrics: %v", err)
		http.Error(w, "Failed to collect metrics", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(metrics)
}

// ServeMetricsHTML serves the metrics as HTML fragment for htmx
func (h *DashboardHandler) ServeMetricsHTML(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	clusterMetrics, err := h.collector.Collect(ctx)
	if err != nil {
		log.Printf("Error collecting metrics: %v", err)
		http.Error(w, "Failed to collect metrics", http.StatusInternalServerError)
		return
	}

	err = h.templates.ExecuteTemplate(w, "metrics.html", clusterMetrics)
	if err != nil {
		log.Printf("Error rendering metrics template: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
	}
}

// ServeHealth serves health check endpoint
func (h *DashboardHandler) ServeHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "healthy",
		"timestamp": time.Now().Format(time.RFC3339),
	})
}

// ServeReadiness serves readiness check endpoint
func (h *DashboardHandler) ServeReadiness(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// Try to collect metrics to verify we can reach k8s API
	_, err := h.collector.Collect(ctx)
	if err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "not ready",
			"error":  err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "ready",
		"timestamp": time.Now().Format(time.RFC3339),
	})
}
