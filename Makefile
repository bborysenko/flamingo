CLUSTER_NAME := fleetdm
CHART_DIR := charts/fleetdm
CHART_REPO := https://bborysenko.github.io/flamingo
CHART_NAME := fleetdm
RELEASE_NAME := fleetdm
NAMESPACE := fleetdm

# Set CHART_SOURCE=remote to install from the published GitHub Pages chart repo
CHART_SOURCE ?= local

.PHONY: cluster install uninstall helm-dep-update

cluster:
	kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml --wait 60s
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

ifeq ($(CHART_SOURCE),remote)
install:
	helm repo add $(CHART_NAME) $(CHART_REPO) || true
	helm repo update $(CHART_NAME)
	helm upgrade --install $(RELEASE_NAME) $(CHART_NAME)/$(CHART_NAME) \
		--namespace $(NAMESPACE) \
		--wait --timeout 10m
else
install: helm-dep-update
	helm upgrade --install $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--wait --timeout 10m
endif

uninstall:
	helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE)
	kind delete cluster --name $(CLUSTER_NAME)

helm-dep-update:
	helm dependency update $(CHART_DIR)
