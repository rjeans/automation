#!/bin/bash
echo "Checking Talos cluster health..."
echo "=== Kubernetes Nodes ==="
kubectl get nodes
echo ""
echo "=== System Pods ==="
kubectl get pods -n kube-system
echo ""
echo "=== Talos Version ==="
talosctl version
echo ""
echo "=== Cluster Summary ==="
kubectl get nodes,deployments,pods -n kube-system -o wide
