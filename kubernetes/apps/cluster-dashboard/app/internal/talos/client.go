package talos

import (
	"context"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/pi-cluster/cluster-dashboard/internal/metrics"
)

// Client implements the TalosClient interface
type Client struct {
	// For now, we'll use a mock implementation
	// In production, you'd use the Talos gRPC client
	enabled bool
}

// NewClient creates a new Talos client
func NewClient() (*Client, error) {
	// Check if Talos config is available
	_, err := os.Stat("/var/run/secrets/talos.dev/config")
	enabled := err == nil

	return &Client{
		enabled: enabled,
	}, nil
}

// GetTalosStatus retrieves Talos cluster status
func (c *Client) GetTalosStatus(ctx context.Context) (*metrics.TalosStatus, error) {
	if !c.enabled {
		// Return mock data if Talos API is not accessible
		return &metrics.TalosStatus{
			Version:       "v1.8.x",
			ClusterHealth: "Healthy",
			Services: map[string]string{
				"kubelet": "Running",
				"etcd":    "Running",
				"apid":    "Running",
			},
			Healthy: true,
		}, nil
	}

	// In production, you would use:
	// - talos.NewClient() to create a gRPC client
	// - client.Health() to check cluster health
	// - client.ServiceList() to get service status
	// - client.Version() to get version info
	//
	// For now, return mock data
	return &metrics.TalosStatus{
		Version:       "v1.8.x",
		ClusterHealth: "Healthy",
		Services: map[string]string{
			"kubelet": "Running",
			"etcd":    "Running",
			"apid":    "Running",
		},
		Healthy: true,
	}, nil
}

// GetVersion retrieves Talos version
func (c *Client) GetVersion(ctx context.Context) (string, error) {
	if !c.enabled {
		return "v1.8.x", nil
	}

	// In production, use talos client.Version()
	return "v1.8.x", nil
}

// GetNodeTemperature retrieves CPU temperature for a specific node
func (c *Client) GetNodeTemperature(ctx context.Context, nodeIP string) (float64, error) {
	// Use talosctl to read temperature from thermal zone
	cmd := exec.CommandContext(ctx, "talosctl", "read", "/sys/class/thermal/thermal_zone0/temp", "--nodes", nodeIP)

	output, err := cmd.CombinedOutput()
	if err != nil {
		// If we can't get temperature, return 0 instead of erroring
		return 0, nil
	}

	// Parse output - format is the raw temperature value in millidegrees
	outputStr := strings.TrimSpace(string(output))

	// Temperature is in millidegrees Celsius, convert to degrees
	millidegrees, err := strconv.ParseFloat(outputStr, 64)
	if err != nil {
		return 0, nil
	}

	celsius := millidegrees / 1000.0
	return celsius, nil
}

// Note: To enable full Talos integration, you would:
// 1. Mount Talos config as a secret in the pod
// 2. Import "github.com/siderolabs/talos/pkg/machinery/client"
// 3. Create client with:
//    config, _ := clientconfig.Open(configPath)
//    opts := []client.OptionFunc{client.WithConfig(config)}
//    c, _ := client.New(ctx, opts...)
// 4. Use the client methods to query Talos API
//
// For security, the dashboard pod would need a read-only Talos config
// with minimal permissions (health checks and version info only)
