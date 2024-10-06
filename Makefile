CLUSTER=temporal
HELM_TEMPORAL_NAME=temporal
HELM_METRICS_NAME=metrics

cluster:
	@kind create cluster --name ${CLUSTER} --config kind-config.yaml
	@kubectl cluster-info --context kind-${CLUSTER}
	@kubectl apply -f metrics-server.yaml

# worker2 run ui+tools, worker3-6 run servers (frontend+worker+history+matching), worker7 runs cassandra, worker8 run elasticsearch
load-temporal:
	@docker pull temporalio/ui:2.31.0
	@docker pull temporalio/admin-tools:1.25.0-tctl-1.18.1-cli-1.0.0
	@docker pull temporalio/server:1.25.0.0
	@docker pull cassandra:3.11.3
	@docker pull docker.elastic.co/elasticsearch/elasticsearch:7.17.3
	@kind load docker-image temporalio/ui:2.31.0 --name ${CLUSTER} --nodes ${CLUSTER}-worker2
	@kind load docker-image temporalio/admin-tools:1.25.0-tctl-1.18.1-cli-1.0.0 --name ${CLUSTER} --nodes ${CLUSTER}-worker2
	@kind load docker-image temporalio/server:1.25.0.0 --name ${CLUSTER} --nodes ${CLUSTER}-worker3,${CLUSTER}-worker4,${CLUSTER}-worker5,${CLUSTER}-worker6
	@kind load docker-image cassandra:3.11.3 --name ${CLUSTER} --nodes ${CLUSTER}-worker7
	@kind load docker-image docker.elastic.co/elasticsearch/elasticsearch:7.17.3 --name ${CLUSTER} --nodes ${CLUSTER}-worker8

load: load-temporal

helm:
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	@helm repo add temporal https://go.temporal.io/helm-charts
	@helm repo update

install-metrics:
	@helm upgrade -i ${HELM_METRICS_NAME} prometheus-community/kube-prometheus-stack -f prometheus-kind-values.yaml

install-temporal:
	@helm upgrade -i ${HELM_TEMPORAL_NAME} temporal/temporal -f temporal-kind-values.yaml
	@kubectl get pods | grep "temporal-" | cut -d' ' -f1 | xargs -I{} kubectl label pods {} cluster=temporal
	@kubectl apply -f temporal-nodeports.yaml
	@kubectl wait --namespace default --for=condition=ready pod --selector=app.kubernetes.io/component=frontend --timeout=300s
	@kubectl wait --namespace default --for=condition=ready pod --selector=app.kubernetes.io/component=history --timeout=300s
	@kubectl exec -it services/temporal-admintools -- tctl namespace register

install: helm install-metrics install-temporal

uninstall:
	@helm uninstall ${HELM_METRICS_NAME}
	@helm uninstall ${HELM_TEMPORAL_NAME}

destroy:
	@kind delete cluster --name ${CLUSTER}

curl:
	kubectl run curl --image=curlimages/curl -i --tty -- sh

ns:
	@kubectl exec -it services/temporal-admintools -- tctl namespace register
