helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault --set "injector.enabled=true"


Step 1.2: Store the Secret in Vault
Exec into your Vault pod to initialize it and store your database credentials.
kubectl exec -it vault-0 -- vault operator init

Step 2: Unseal Vault
By default, Vault requires 3 out of the 5 generated unseal keys to unlock its storage engine.

Run the unseal command three separate times, providing a different unseal key from your notepad each time:

Bash
# First key
kubectl exec -it vault-0 -- vault operator unseal <YOUR_UNSEAL_KEY_1>

# Second key
kubectl exec -it vault-0 -- vault operator unseal <YOUR_UNSEAL_KEY_2>

# Third key
kubectl exec -it vault-0 -- vault operator unseal <YOUR_UNSEAL_KEY_3>

Step 3: Log In and Proceed
Now that the door is unlocked, log into Vault using the Initial Root Token you saved from Step 1:

Bash
# Exec back into the pod to continue Step 2
kubectl exec -it vault-0 -- /bin/sh

# Log in using the root token
vault login <YOUR_INITIAL_ROOT_TOKEN>

Now you can run your commands to enable the KV secret engine and save your secrets cleanly:

Bash
vault secrets enable -path=internal kv-v2
vault kv put internal/database/config username="devopsadmin" password="secretpassword"


# 1. Enable Kubernetes authentication
vault auth enable kubernetes

# 2. Configure Vault to read local cluster tokens
vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"

# 3. Create the policy allowing access to your secret path
vault policy write crud-app-policy - <<EOF
path "internal/data/database/config" {
  capabilities = ["read"]
}
EOF

# 4. Bind the policy to the service account your app will use
vault write auth/kubernetes/role/crud-backend-role \
    bound_service_account_names=vault-auth \
    bound_service_account_namespaces=crud-app \
    policies=crud-app-policy \
    audience="https://kubernetes.default.svc" \
    ttl=24h