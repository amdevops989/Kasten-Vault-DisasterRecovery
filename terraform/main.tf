# AWS Authentication: Ensure your local environment (or CI/CD runner) has programmatic access to AWS
#  (via AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or an IAM Instance Profile) 
#  with explicit permission to execute kms:Encrypt and kms:Decrypt on your target key.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.2.0"
    }
  }
}

# -----------------------------------------------------------------------------
# 1. DEPLOY VAULT WITH AWS KMS AUTO-UNSEAL
# -----------------------------------------------------------------------------
resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = "default"
  create_namespace = false

  set {
    name  = "injector.enabled"
    value = "true"
  }

  # Pass Vault Server Configuration via standard HCL configuration string
  set {
    name  = "server.configuration"
    value = <<EOT
      ui = true
      
      storage "raft" {
        path = "/vault/data"
      }

      # The critical block replacing manual unsealing
      seal "awskms" {
        region     = "${var.aws_region}"
        kms_key_id = "${var.kms_key_id}"
      }

      listener "tcp" {
        address     = "[::]:8200"
        tls_disable = 1
      }
    EOT
  }
}

# -----------------------------------------------------------------------------
# 2. SECURE STORAGE ENGINE & VARIABLES (Runs after Vault auto-unseals)
# -----------------------------------------------------------------------------

resource "vault_mount" "kvv2" {
  path        = "internal"
  type        = "kv"
  options     = { version = "2" }
  description = "Production KV-v2 secret engine"
  
  depends_on = [helm_release.vault]
}

resource "vault_kv_secret_v2" "db_credentials" {
  mount               = vault_mount.kvv2.path
  name                = "database/config"
  delete_all_versions = true
  
  # Populated safely using variables from tfvars
  data_json = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}

# -----------------------------------------------------------------------------
# 3. KUBERNETES AUTH & SERVICE ROLE BINDINGS
# -----------------------------------------------------------------------------

resource "vault_auth_backend" "kubernetes" {
  type       = "kubernetes"
  path       = "kubernetes"
  depends_on = [helm_release.vault]
}

resource "vault_kubernetes_auth_backend_config" "config" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc"
}

resource "vault_policy" "crud_app_policy" {
  name   = "crud-app-policy"
  policy = <<EOT
path "internal/data/database/config" {
  capabilities = ["read"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "crud_backend_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "crud-backend-role"
  bound_service_account_names      = ["vault-auth"]
  bound_service_account_namespaces = ["crud-app"]
  token_policies                   = [vault_policy.crud_app_policy.name]
  token_ttl                        = 86400
  audience                         = "" # Bypasses strict local cluster check
}