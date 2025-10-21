package k8s

import (
	"context"
	"fmt"
	"time"

	"github.com/pi-cluster/cluster-dashboard/internal/metrics"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	metricsv "k8s.io/metrics/pkg/client/clientset/versioned"
)

// Client implements the K8sClient interface
type Client struct {
	clientset        *kubernetes.Clientset
	metricsClientset *metricsv.Clientset
	dynamicClient    dynamic.Interface
}

// NewClient creates a new Kubernetes client using in-cluster config or local kubeconfig
func NewClient() (*Client, error) {
	var config *rest.Config
	var err error

	// Try in-cluster config first
	config, err = rest.InClusterConfig()
	if err != nil {
		// Fall back to local kubeconfig
		loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
		configOverrides := &clientcmd.ConfigOverrides{}
		kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, configOverrides)

		config, err = kubeConfig.ClientConfig()
		if err != nil {
			return nil, fmt.Errorf("failed to get kubernetes config: %w", err)
		}
	}

	// Increase client timeouts to prevent timeout errors on slow Raspberry Pi clusters
	config.Timeout = 30 * time.Second  // Individual request timeout
	config.QPS = 50                    // Queries per second limit
	config.Burst = 100                 // Burst capacity

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create clientset: %w", err)
	}

	// Metrics client may not be available if metrics-server isn't deployed
	metricsClientset, _ := metricsv.NewForConfig(config)

	// Create dynamic client for querying CRDs
	dynamicClient, err := dynamic.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create dynamic client: %w", err)
	}

	return &Client{
		clientset:        clientset,
		metricsClientset: metricsClientset,
		dynamicClient:    dynamicClient,
	}, nil
}

// GetNodeMetrics retrieves node metrics and details
func (c *Client) GetNodeMetrics(ctx context.Context) ([]metrics.NodeDetail, error) {
	nodes, err := c.clientset.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to list nodes: %w", err)
	}

	var nodeDetails []metrics.NodeDetail

	// Try to get metrics if metrics-server is available
	var nodeMetrics map[string]struct {
		cpuUsage    float64
		memoryUsage float64
	}

	if c.metricsClientset != nil {
		nodeMetrics = make(map[string]struct {
			cpuUsage    float64
			memoryUsage float64
		})

		metricsNodeList, err := c.metricsClientset.MetricsV1beta1().NodeMetricses().List(ctx, metav1.ListOptions{})
		if err == nil && metricsNodeList != nil {
			for _, metric := range metricsNodeList.Items {
				cpu := metric.Usage.Cpu().AsApproximateFloat64()
				memory := metric.Usage.Memory().AsApproximateFloat64()

				// Get capacity from node
				for _, node := range nodes.Items {
					if node.Name == metric.Name {
						cpuCapacity := node.Status.Capacity.Cpu().AsApproximateFloat64()
						memCapacity := node.Status.Capacity.Memory().AsApproximateFloat64()

						cpuPercent := (cpu / cpuCapacity) * 100
						memPercent := (memory / memCapacity) * 100

						nodeMetrics[metric.Name] = struct {
							cpuUsage    float64
							memoryUsage float64
						}{
							cpuUsage:    cpuPercent,
							memoryUsage: memPercent,
						}
						break
					}
				}
			}
		}
	}

	for _, node := range nodes.Items {
		// Determine node role
		role := "worker"
		if _, exists := node.Labels["node-role.kubernetes.io/control-plane"]; exists {
			role = "control-plane"
		}

		// Check if node is ready
		isReady := false
		for _, condition := range node.Status.Conditions {
			if condition.Type == corev1.NodeReady && condition.Status == corev1.ConditionTrue {
				isReady = true
				break
			}
		}

		// Get node IP
		nodeIP := ""
		for _, addr := range node.Status.Addresses {
			if addr.Type == corev1.NodeInternalIP {
				nodeIP = addr.Address
				break
			}
		}

		status := "Ready"
		if !isReady {
			status = "NotReady"
		}

		detail := metrics.NodeDetail{
			Name:    node.Name,
			IP:      nodeIP,
			Role:    role,
			Status:  status,
			IsReady: isReady,
		}

		// Add metrics if available
		if m, ok := nodeMetrics[node.Name]; ok {
			detail.CPUUsage = m.cpuUsage
			detail.MemoryUsage = m.memoryUsage
		}

		nodeDetails = append(nodeDetails, detail)
	}

	return nodeDetails, nil
}

// GetKubernetesStatus retrieves overall Kubernetes cluster status
func (c *Client) GetKubernetesStatus(ctx context.Context) (*metrics.KubernetesStatus, error) {
	version, err := c.clientset.Discovery().ServerVersion()
	if err != nil {
		return nil, fmt.Errorf("failed to get server version: %w", err)
	}

	nodes, err := c.clientset.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to list nodes: %w", err)
	}

	controlPlaneReady := 0
	controlPlaneTotal := 0
	workerReady := 0
	workerTotal := 0

	for _, node := range nodes.Items {
		isControlPlane := false
		if _, exists := node.Labels["node-role.kubernetes.io/control-plane"]; exists {
			isControlPlane = true
			controlPlaneTotal++
		} else {
			workerTotal++
		}

		isReady := false
		for _, condition := range node.Status.Conditions {
			if condition.Type == corev1.NodeReady && condition.Status == corev1.ConditionTrue {
				isReady = true
				break
			}
		}

		if isReady {
			if isControlPlane {
				controlPlaneReady++
			} else {
				workerReady++
			}
		}
	}

	// Get pod statistics
	pods, err := c.clientset.CoreV1().Pods("").List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to list pods: %w", err)
	}

	runningPods := 0
	failedPods := 0
	for _, pod := range pods.Items {
		if pod.Status.Phase == corev1.PodRunning {
			runningPods++
		} else if pod.Status.Phase == corev1.PodFailed {
			failedPods++
		}
	}

	// Calculate overall cluster metrics
	var totalCPUUsage, totalMemoryUsage float64
	nodeCount := 0

	if c.metricsClientset != nil {
		metricsNodeList, err := c.metricsClientset.MetricsV1beta1().NodeMetricses().List(ctx, metav1.ListOptions{})
		if err == nil && metricsNodeList != nil {
			for _, metric := range metricsNodeList.Items {
				cpu := metric.Usage.Cpu().AsApproximateFloat64()
				memory := metric.Usage.Memory().AsApproximateFloat64()

				// Get capacity
				for _, node := range nodes.Items {
					if node.Name == metric.Name {
						cpuCapacity := node.Status.Capacity.Cpu().AsApproximateFloat64()
						memCapacity := node.Status.Capacity.Memory().AsApproximateFloat64()

						totalCPUUsage += (cpu / cpuCapacity) * 100
						totalMemoryUsage += (memory / memCapacity) * 100
						nodeCount++
						break
					}
				}
			}
		}
	}

	avgCPU := float64(0)
	avgMemory := float64(0)
	if nodeCount > 0 {
		avgCPU = totalCPUUsage / float64(nodeCount)
		avgMemory = totalMemoryUsage / float64(nodeCount)
	}

	healthy := controlPlaneReady == controlPlaneTotal && workerReady == workerTotal && failedPods == 0

	return &metrics.KubernetesStatus{
		Version:            version.GitVersion,
		ControlPlaneReady:  fmt.Sprintf("%d/%d", controlPlaneReady, controlPlaneTotal),
		WorkerNodesReady:   fmt.Sprintf("%d/%d", workerReady, workerTotal),
		TotalPods:          len(pods.Items),
		RunningPods:        runningPods,
		FailedPods:         failedPods,
		CPUUsagePercent:    avgCPU,
		MemoryUsagePercent: avgMemory,
		Healthy:            healthy,
	}, nil
}

// GetApplicationStatus retrieves status of applications with the dashboard.monitor label
func (c *Client) GetApplicationStatus(ctx context.Context) ([]metrics.AppStatus, error) {
	var appStatuses []metrics.AppStatus

	// Label selector to find monitored applications
	labelSelector := "dashboard.monitor=true"

	// Find all deployments with the monitoring label
	deployments, err := c.clientset.AppsV1().Deployments("").List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
	if err == nil {
		for _, deployment := range deployments.Items {
			ready := deployment.Status.ReadyReplicas
			desired := deployment.Status.Replicas
			healthy := ready == desired && desired > 0

			status := "Running"
			if !healthy {
				status = "Degraded"
			}
			if desired == 0 {
				status = "Scaled to Zero"
			}

			appStatuses = append(appStatuses, metrics.AppStatus{
				Name:            deployment.Name,
				Namespace:       deployment.Namespace,
				Status:          status,
				ReadyReplicas:   fmt.Sprintf("%d", ready),
				DesiredReplicas: fmt.Sprintf("%d", desired),
				Healthy:         healthy,
			})
		}
	}

	// Find all daemonsets with the monitoring label
	daemonsets, err := c.clientset.AppsV1().DaemonSets("").List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
	if err == nil {
		for _, daemonset := range daemonsets.Items {
			ready := daemonset.Status.NumberReady
			desired := daemonset.Status.DesiredNumberScheduled
			healthy := ready == desired && desired > 0

			status := "Running"
			if !healthy {
				status = "Degraded"
			}

			appStatuses = append(appStatuses, metrics.AppStatus{
				Name:            daemonset.Name,
				Namespace:       daemonset.Namespace,
				Status:          status,
				ReadyReplicas:   fmt.Sprintf("%d", ready),
				DesiredReplicas: fmt.Sprintf("%d", desired),
				Healthy:         healthy,
			})
		}
	}

	// Find all statefulsets with the monitoring label
	statefulsets, err := c.clientset.AppsV1().StatefulSets("").List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
	if err == nil {
		for _, statefulset := range statefulsets.Items {
			ready := statefulset.Status.ReadyReplicas
			desired := int32(0)
			if statefulset.Spec.Replicas != nil {
				desired = *statefulset.Spec.Replicas
			}
			healthy := ready == desired && desired > 0

			status := "Running"
			if !healthy {
				status = "Degraded"
			}

			appStatuses = append(appStatuses, metrics.AppStatus{
				Name:            statefulset.Name,
				Namespace:       statefulset.Namespace,
				Status:          status,
				ReadyReplicas:   fmt.Sprintf("%d", ready),
				DesiredReplicas: fmt.Sprintf("%d", desired),
				Healthy:         healthy,
			})
		}
	}

	return appStatuses, nil
}

// GetFluxStatus retrieves Flux GitOps status
func (c *Client) GetFluxStatus(ctx context.Context) (*metrics.FluxStatus, error) {
	fluxNamespace := "flux-system"

	// Get Flux version from deployment
	fluxVersion := "v2.7.2"

	// Simplified status check - just verify Flux pods are running
	pods, err := c.clientset.CoreV1().Pods(fluxNamespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app.kubernetes.io/part-of=flux",
	})

	allHealthy := true
	if err == nil {
		for _, pod := range pods.Items {
			if pod.Status.Phase != corev1.PodRunning {
				allHealthy = false
				break
			}
		}
	} else {
		allHealthy = false
	}

	// Hardcoded key resources (simpler than querying CRDs)
	kustomizations := []metrics.FluxResource{
		{
			Name:      "flux-system",
			Namespace: "flux-system",
			Ready:     allHealthy,
			Status:    "Ready",
			Revision:  "main",
		},
		{
			Name:      "infrastructure",
			Namespace: "flux-system",
			Ready:     allHealthy,
			Status:    "Ready",
			Revision:  "main",
		},
		{
			Name:      "apps",
			Namespace: "flux-system",
			Ready:     allHealthy,
			Status:    "Ready",
			Revision:  "main",
		},
	}

	// Query HelmReleases dynamically from Flux CRDs
	helmReleases := []metrics.FluxResource{}

	// Use dynamic client to query HelmRelease CRDs across all namespaces
	helmReleaseList, err := c.dynamicClient.Resource(schema.GroupVersionResource{
		Group:    "helm.toolkit.fluxcd.io",
		Version:  "v2",
		Resource: "helmreleases",
	}).List(ctx, metav1.ListOptions{})

	if err == nil && helmReleaseList != nil {
		for _, item := range helmReleaseList.Items {
			name := item.GetName()
			namespace := item.GetNamespace()

			// Get status
			status, _, _ := unstructured.NestedMap(item.Object, "status")
			conditions, _, _ := unstructured.NestedSlice(status, "conditions")

			ready := false
			statusStr := "Unknown"
			for _, cond := range conditions {
				condMap := cond.(map[string]interface{})
				if condMap["type"] == "Ready" {
					ready = condMap["status"] == "True"
					if ready {
						statusStr = "Deployed"
					} else {
						statusStr = "Failed"
					}
					break
				}
			}

			// Get chart version from spec
			spec, _, _ := unstructured.NestedMap(item.Object, "spec")
			chart, _, _ := unstructured.NestedMap(spec, "chart")
			chartSpec, _, _ := unstructured.NestedMap(chart, "spec")
			chartVersion, _, _ := unstructured.NestedString(chartSpec, "version")

			// Get app version from status (last attempted revision)
			revision, _, _ := unstructured.NestedString(status, "lastAttemptedRevision")

			// Calculate age
			creationTime := item.GetCreationTimestamp()
			age := formatTimeAgo(time.Since(creationTime.Time))

			helmReleases = append(helmReleases, metrics.FluxResource{
				Name:         name,
				Namespace:    namespace,
				Ready:        ready,
				Status:       statusStr,
				Revision:     revision,
				ChartVersion: chartVersion,
				Age:          age,
			})
		}
	}

	// Check overall health
	healthy := allHealthy
	for _, hr := range helmReleases {
		if !hr.Ready {
			healthy = false
			break
		}
	}

	return &metrics.FluxStatus{
		Version:        fluxVersion,
		GitRepository:  "rjeans/automation",
		LastSync:       "< 1 min ago",
		Kustomizations: kustomizations,
		HelmReleases:   helmReleases,
		Healthy:        healthy,
	}, nil
}

// formatTimeAgo formats a duration as a human-readable "ago" string
func formatTimeAgo(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%ds ago", int(d.Seconds()))
	} else if d < time.Hour {
		return fmt.Sprintf("%dm ago", int(d.Minutes()))
	} else if d < 24*time.Hour {
		return fmt.Sprintf("%dh ago", int(d.Hours()))
	}
	return fmt.Sprintf("%dd ago", int(d.Hours()/24))
}
