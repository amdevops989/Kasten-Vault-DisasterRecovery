🛠️ Complete Vault + Minikube Setup Architecture
The diagram below outlines exactly how our working architecture looks, showing the lifecycle from token authentication to injection.

Step 1: Install Vault via Helm
Run these commands from your local machine to deploy Vault onto your Minikube cluster with the sidecar injector enabled:

Bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault --set "injector.enabled=true"
Step 2: Initialize & Unseal Vault
Vault installs in a sealed state. Run the setup sequence to unlock the storage engine:

Bash
# 1. Initialize Vault and capture the 5 Unseal Keys and 1 Root Token
kubectl exec -it vault-0 -- vault operator init

# 2. Run the unseal command 3 separate times using 3 different unseal keys
kubectl exec -it vault-0 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -it vault-0 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -it vault-0 -- vault operator unseal <UNSEAL_KEY_3>
(Verify that Sealed reads false in the final command's output).

Step 3: Configure Vault Engine & Kubernetes Auth
Exec into the Vault pod to configure how your cluster applications will talk to Vault securely:

Bash
# 1. Exec into the pod shell
kubectl exec -it vault-0 -- /bin/sh

# 2. Log in using your Initial Root Token
vault login <YOUR_INITIAL_ROOT_TOKEN>

# 3. Enable the Key-Value (KV-v2) engine and write your secrets
vault secrets enable -path=internal kv-v2
vault kv put internal/database/config username="devopsadmin" password="secretpassword"

# 4. Enable and configure Kubernetes Auth backend
vault auth enable kubernetes

vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"

# 5. Create an access control policy for your backend app
vault policy write crud-app-policy - <<EOF
path "internal/data/database/config" {
  capabilities = ["read"]
}
EOF

# 6. Bind the policy to your ServiceAccount (with audience bypass for local Minikube)
vault write auth/kubernetes/role/crud-backend-role \
    bound_service_account_names=vault-auth \
    bound_service_account_namespaces=crud-app \
    policies=crud-app-policy \
    audience="" \
    ttl=24h

# 7. Exit the pod shell
exit
Step 4: Apply the Bulletproof Manifest
Create your application namespace, save this configuration as backend-deployment.yaml, and apply it using kubectl apply -f backend-deployment.yaml.

YAML
apiVersion: v1
kind: Namespace
metadata:
  name: crud-app
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: crud-app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crud-backend-deployment
  namespace: crud-app
  labels:
    app: crud-backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: crud-backend
  template:
    metadata:
      labels:
        app: crud-backend
      annotations:
        # Enable sidecar injection
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "crud-backend-role"
        
        # Pull the data from Vault path
        vault.hashicorp.com/agent-inject-secret-db-credentials: "internal/data/database/config"
        
        # Cleanly format data to a mountable script file
        vault.hashicorp.com/agent-inject-template-db-credentials: |
          {{- with secret "internal/data/database/config" -}}
          export DB_USER="{{ .Data.data.username }}"
          export DB_PASSWORD="{{ .Data.data.password }}"
          {{- end -}}
    spec:
      serviceAccountName: vault-auth
      containers:
        - name: backend-api
          image: devopsflow999/crud-backend:latest 
          imagePullPolicy: Always
          ports:
            - containerPort: 3000
          # Source the dynamic file to memory before triggering the node container run command
          command: ["/bin/sh", "-c"]
          args: ["source /vault/secrets/db-credentials && npm run start"]
          env:
            - name: DB_HOST
              value: "postgres-postgresql.postgresql.svc.cluster.local"
            - name: DB_NAME
              value: "app_production"
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: crud-app
  labels:
    app: crud-backend
spec:
  selector:
    app: crud-backend
  ports:
    - protocol: TCP
      port: 3000
      targetPort: 3000
      name: http-web
  type: ClusterIP
Step 5: Verification Commands
Run these diagnostic commands to see everything working flawlessly:

Bash
# Check the status of your app pods
kubectl get pods -n crud-app

# View the sidecar agent handling dynamic token updates
kubectl logs deployment/crud-backend-deployment -c vault-agent -n crud-app

# View your Node.js application process logs running with secure variables
kubectl logs deployment/crud-backend-deployment -c backend-api -n crud-app