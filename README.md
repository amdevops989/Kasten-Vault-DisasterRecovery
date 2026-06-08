# Kasten-Vault-DisasterRecovery

crud app + postgres
ingress gateway + minikube 
vault 
k10

before installing k10 we should add some addons csi volume ...




simulating DR with microservices Crud app with postgress

## installing k10

# 1. Re-create a clean namespace
kubectl create namespace kasten-io

# 2. Tell Istio explicitly NEVER to inject proxy sidecars here
kubectl label namespace kasten-io istio-injection=disabled --overwrite


## Phase 4: Fresh Kasten K10 Installation 📥

# 1. Install official Kubernetes VolumeSnapshot APIs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# 2. Enable Minikube CSI addons
minikube addons enable volumesnapshots
minikube addons enable csi-hostpath-driver

# 3. Tag the snapshot class so Kasten knows it can use it locally
kubectl annotate volumesnapshotclass csi-hostpath-snapclass \
  k10.kasten.io/is-snapshot-class=true --overwrite

# 1. Update your charts
helm repo add kasten https://charts.kasten.io/
helm repo update

# 2. Install Kasten K10 natively
helm install k10 kasten/k10 --namespace=kasten-io

# 3. Re-create your administrative cluster binding
kubectl create clusterrolebinding k10-default-admin-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kasten-io:default