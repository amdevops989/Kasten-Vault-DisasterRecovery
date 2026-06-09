minikube start --addons volumesnapshots,csi-hostpath-driver --apiserver-port=6443 --container-runtime=containerd --memory=4096 --cpus=2 

Phase 1: Prepare the Minikube Infrastructure
First, we need to spin up the CSI storage subsystems built into Minikube. Run these commands to enable the storage drivers:

Bash


# 2. Verify that your core storage class exists
kubectl get sc
(You should see csi-hostpath-sc listed in the output).

Phase 2: Install Stable Volume Snapshot CRDs
To guarantee Kasten never throws a 404 Not Found or a Terminating error when talking to the Kubernetes API, let's manually inject the stable v1 Snapshot specifications:

Bash
# Apply stable v8.0.1 CSI external-snapshotter specifications
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.0.1/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.0.1/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.0.1/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# Create the specific VolumeSnapshotClass that tracks your driver
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-hostpath-snapclass
  annotations:
    k10.kasten.io/is-snapshot-class: "true"
driver: hostpath.csi.k8s.io
deletionPolicy: Delete
EOF
Phase 3: Deploy PostgreSQL Engine
Let's build your clean database layer inside a dedicated dev namespace.

Bash
# 1. Create the application target namespace
kubectl create namespace postgresql
helm install postgres bitnami/postgresql \
  --namespace postgresql \
  --create-namespace \
  --set global.security.allowInsecureImages=true \
  --set volumePermissions.image.repository=bitnamilegacy/os-shell \
  --set image.repository=bitnamilegacy/postgresql \
  --set auth.username=devopsadmin \
  --set auth.password=secretpassword \
  --set auth.database=app_production \
  --set primary.persistence.storageClass=csi-hostpath-sc \
  --set primary.persistence.size=2Gi


kubectl --namespace dev annotate statefulset/postgres-postgresql \ 
    kanister.kasten.io/blueprint=postgres-bp
Bash
# 1. Add the Kasten Helm Repository
helm repo add kasten https://charts.kasten.io/
helm repo update

# 2. Create the control plane namespace
kubectl create namespace kasten-io

# 3. Install Kasten K10 with standard evaluation parameters
helm install k10 kasten/k10 --namespace=kasten-io --set auth.tokenAuth.enabled=true
Let's wait for the control plane to completely stabilize before proceeding:

Bash
kubectl get pods -n kasten-io -w
(Wait until all pods show Running or Completed).

Phase 5: Implement the Kanister Blueprint for App Consistency
To keep your data safe and uncorrupted, apply our custom blueprint directly to the cluster, then annotate your database so Kasten knows to run it.

Bash
# 1. Inject the logical transactional flushing Blueprint
cat <<EOF | kubectl apply -n kasten-io -f -
apiVersion: cr.kanister.io/v1alpha1
kind: Blueprint
metadata:
  name: postgres-blueprint
actions:
  backupPrehook:
    phases:
    - func: KubeExec
      name: flushDbCache
      args:
        namespace: "{{ .StatefulSet.Namespace }}"
        pod: "{{ index .StatefulSet.Pods 0 }}"
        container: postgres
        command:
        - psql
        - -U
        - devopsadmin
        - -d
        - app_production
        - -c
        - "CHECKPOINT;"
  backupPosthook:
    phases:
    - func: KubeExec
      name: logResumeNotice
      args:
        namespace: "{{ .StatefulSet.Namespace }}"
        pod: "{{ index .StatefulSet.Pods 0 }}"
        container: postgres
        command:
        - echo
        - "CSI Snapshot execution complete."
EOF

# 2. Link your StatefulSet directly to this protection layer
kubectl annotate statefulset postgres-db -n dev kanister.kasten.io/blueprint=postgres-blueprint --overwrite
Next Step: Launch the Kasten Dashboard
Everything is laid out cleanly on the cluster side. Open your access gateway to configure your Location Profile (MinIO) and run your first policy:

Bash
minikube service gateway -n kasten-io

## minio

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: minio
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-pvc
  namespace: minio
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: csi-hostpath-sc
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio-deployment
  namespace: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:RELEASE.2024-01-11T05-49-40Z
        args:
        - server
        - /data
        - --console-address
        - ":9001"
        env:
        - name: MINIO_ROOT_USER
          value: minioadmin
        - name: MINIO_ROOT_PASSWORD
          value: minioadminpassword
        ports:
        - containerPort: 9000
          name: api
        - containerPort: 9001
          name: console
        volumeMounts:
        - mountPath: /data
          name: minio-storage
      volumes:
      - name: minio-storage
        persistentVolumeClaim:
          claimName: minio-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: minio-service
  namespace: minio
spec:
  type: ClusterIP
  ports:
    - port: 9000
      targetPort: 9000
      name: minio-api
    - port: 9001
      targetPort: 9001
      name: minio-console
  selector:
    app: minio
EOF

## 1. Create a dedicated admin service account
kubectl create serviceaccount k10-admin -n kasten-io

# 2. Bind it to the cluster-admin role so it can orchestrate backups
kubectl create clusterrolebinding k10-admin-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kasten-io:k10-admin

# 3. Generate the 24-hour token
kubectl create token k10-admin -n kasten-io --duration=24h