package metrics

import (
	"context"
	"fmt"
	"time"
)

// ClusterMetrics holds all cluster health information
type ClusterMetrics struct {
	Hardware     HardwareStatus    `json:"hardware"`
	Talos        TalosStatus       `json:"talos"`
	Kubernetes   KubernetesStatus  `json:"kubernetes"`
	Flux         FluxStatus        `json:"flux"`
	Applications []AppStatus       `json:"applications"`
	UpdatedAt    time.Time         `json:"updated_at"`
}

// HardwareStatus represents physical hardware information
type HardwareStatus struct {
	NodeCount       int               `json:"node_count"`
	ControlPlanes   int               `json:"control_planes"`
	Workers         int               `json:"workers"`
	TotalCPU        string            `json:"total_cpu"`
	TotalMemory     string            `json:"total_memory"`
	Storage         string            `json:"storage"`
	AllNodesReady   bool              `json:"all_nodes_ready"`
	NodeDetails     []NodeDetail      `json:"node_details"`
}

// NodeDetail holds per-node information
type NodeDetail struct {
	Name         string  `json:"name"`
	IP           string  `json:"ip"`
	Role         string  `json:"role"`
	Status       string  `json:"status"`
	CPUUsage     float64 `json:"cpu_usage"`
	MemoryUsage  float64 `json:"memory_usage"`
	Temperature  float64 `json:"temperature"`
	IsReady      bool    `json:"is_ready"`
}

// TalosStatus represents Talos Linux health
type TalosStatus struct {
	Version       string            `json:"version"`
	ClusterHealth string            `json:"cluster_health"`
	Services      map[string]string `json:"services"` // service name -> status
	Healthy       bool              `json:"healthy"`
}

// KubernetesStatus represents Kubernetes cluster health
type KubernetesStatus struct {
	Version            string  `json:"version"`
	ControlPlaneReady  string  `json:"control_plane_ready"`
	WorkerNodesReady   string  `json:"worker_nodes_ready"`
	TotalPods          int     `json:"total_pods"`
	RunningPods        int     `json:"running_pods"`
	FailedPods         int     `json:"failed_pods"`
	CPUUsagePercent    float64 `json:"cpu_usage_percent"`
	MemoryUsagePercent float64 `json:"memory_usage_percent"`
	Healthy            bool    `json:"healthy"`
}

// AppStatus represents application health
type AppStatus struct {
	Name            string `json:"name"`
	Namespace       string `json:"namespace"`
	Status          string `json:"status"`
	ReadyReplicas   string `json:"ready_replicas"`
	DesiredReplicas string `json:"desired_replicas"`
	Healthy         bool   `json:"healthy"`
}

// FluxStatus represents Flux GitOps status
type FluxStatus struct {
	Version         string           `json:"version"`
	GitRepository   string           `json:"git_repository"`
	LastSync        string           `json:"last_sync"`
	Kustomizations  []FluxResource   `json:"kustomizations"`
	HelmReleases    []FluxResource   `json:"helm_releases"`
	RecentActivity  []FluxEvent      `json:"recent_activity"`
	Healthy         bool             `json:"healthy"`
}

// FluxResource represents a Flux resource (Kustomization or HelmRelease)
type FluxResource struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
	Ready     bool   `json:"ready"`
	Status    string `json:"status"`
	Revision  string `json:"revision"`
}

// FluxEvent represents a recent Flux activity event
type FluxEvent struct {
	Time     string `json:"time"`
	Type     string `json:"type"`
	Resource string `json:"resource"`
	Message  string `json:"message"`
}

// Collector interface for gathering metrics
type Collector interface {
	Collect(ctx context.Context) (*ClusterMetrics, error)
}

// MetricsCollector aggregates data from multiple sources
type MetricsCollector struct {
	k8sClient   K8sClient
	talosClient TalosClient
	cache       *ClusterMetrics
	cacheExpiry time.Time
	cacheTTL    time.Duration
}

// K8sClient interface for Kubernetes operations
type K8sClient interface {
	GetNodeMetrics(ctx context.Context) ([]NodeDetail, error)
	GetKubernetesStatus(ctx context.Context) (*KubernetesStatus, error)
	GetApplicationStatus(ctx context.Context) ([]AppStatus, error)
	GetFluxStatus(ctx context.Context) (*FluxStatus, error)
}

// TalosClient interface for Talos operations
type TalosClient interface {
	GetTalosStatus(ctx context.Context) (*TalosStatus, error)
	GetVersion(ctx context.Context) (string, error)
	GetNodeTemperature(ctx context.Context, nodeIP string) (float64, error)
}

// NewMetricsCollector creates a new metrics collector
func NewMetricsCollector(k8s K8sClient, talos TalosClient, cacheTTL time.Duration) *MetricsCollector {
	return &MetricsCollector{
		k8sClient:   k8s,
		talosClient: talos,
		cacheTTL:    cacheTTL,
	}
}

// Collect gathers all cluster metrics with caching
func (mc *MetricsCollector) Collect(ctx context.Context) (*ClusterMetrics, error) {
	// Return cached data if still valid
	if mc.cache != nil && time.Now().Before(mc.cacheExpiry) {
		return mc.cache, nil
	}

	// Gather fresh metrics
	metrics := &ClusterMetrics{
		UpdatedAt: time.Now(),
	}

	// Collect Kubernetes metrics
	nodes, err := mc.k8sClient.GetNodeMetrics(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get node metrics: %w", err)
	}

	// Enrich nodes with temperature data from Talos
	for i := range nodes {
		if nodes[i].IP != "" {
			temp, err := mc.talosClient.GetNodeTemperature(ctx, nodes[i].IP)
			if err == nil {
				nodes[i].Temperature = temp
			}
		}
	}

	k8sStatus, err := mc.k8sClient.GetKubernetesStatus(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get k8s status: %w", err)
	}
	metrics.Kubernetes = *k8sStatus

	apps, err := mc.k8sClient.GetApplicationStatus(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get app status: %w", err)
	}
	metrics.Applications = apps

	// Collect Flux status
	fluxStatus, err := mc.k8sClient.GetFluxStatus(ctx)
	if err != nil {
		// Flux might not be installed, don't fail completely
		metrics.Flux = FluxStatus{
			Version:        "Not Installed",
			GitRepository:  "N/A",
			LastSync:       "N/A",
			Kustomizations: []FluxResource{},
			HelmReleases:   []FluxResource{},
			Healthy:        false,
		}
	} else {
		metrics.Flux = *fluxStatus
	}

	// Build hardware status
	controlPlanes := 0
	workers := 0
	allReady := true
	for _, node := range nodes {
		if node.Role == "control-plane" {
			controlPlanes++
		} else {
			workers++
		}
		if !node.IsReady {
			allReady = false
		}
	}

	metrics.Hardware = HardwareStatus{
		NodeCount:     len(nodes),
		ControlPlanes: controlPlanes,
		Workers:       workers,
		TotalCPU:      "4x ARM Cortex-A72 (16 cores total)",
		TotalMemory:   "32GB (4x 8GB)",
		Storage:       "1TB External SSD",
		AllNodesReady: allReady,
		NodeDetails:   nodes,
	}

	// Collect Talos metrics
	talosStatus, err := mc.talosClient.GetTalosStatus(ctx)
	if err != nil {
		// Talos might not be accessible, don't fail completely
		metrics.Talos = TalosStatus{
			Version:       "Unknown",
			ClusterHealth: "Unknown",
			Services:      make(map[string]string),
			Healthy:       false,
		}
	} else {
		metrics.Talos = *talosStatus
	}

	// Cache the results
	mc.cache = metrics
	mc.cacheExpiry = time.Now().Add(mc.cacheTTL)

	return metrics, nil
}
