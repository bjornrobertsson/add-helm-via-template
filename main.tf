terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.31"
  agent_id = coder_agent.main.id
}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)
  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.
  Set this to true if the Coder host is running outside the Kubernetes cluster
  and you want to use the kubeconfig to authenticate to the cluster.
  EOF
  default   = false
  sensitive = true
}

variable "workspaces_namespace" {
  type        = string
  description = "The namespace to create workspaces in (must exist prior to creating workspaces). If the Coder host is itself running as a Pod on the same Kubernetes cluster as you are deploying workspaces to, set this to the same namespace."
  default     = "coder"
  sensitive   = true
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
  option {
    name  = "16 GB"
    value = "16"
  }
  option {
    name  = "32 GB"
    value = "32"
  }
}

data "coder_parameter" "storage" {
  name         = "storage"
  display_name = "Storage"
  description  = "The amount of storage in GB for Neo4j data"
  default      = "10"
  icon         = "/icon/database.svg"
  mutable      = true
  option {
    name  = "10 GB"
    value = "10"
  }
  option {
    name  = "20 GB"
    value = "20"
  }
  option {
    name  = "50 GB"
    value = "50"
  }
  option {
    name  = "100 GB"
    value = "100"
  }
}

data "coder_parameter" "neo4j_password" {
  name         = "neo4j_password"
  display_name = "Neo4j Password"
  description  = "Password for the Neo4j admin user"
  type         = "string"
  default      = "neo4j-secure-password"
  mutable      = true
}

data "coder_parameter" "neo4j_version" {
  name         = "neo4j_version"
  display_name = "Neo4j Version"
  description  = "Neo4j Helm chart version"
  default      = "5.22.0"
  mutable      = true
  option {
    name  = "5.22.0"
    value = "5.22.0"
  }
  option {
    name  = "5.21.0"
    value = "5.21.0"
  }
  option {
    name  = "5.20.0"
    value = "5.20.0"
  }
}

data "coder_parameter" "storage_class" {
  name         = "storage_class"
  display_name = "Storage Class"
  description  = "Kubernetes storage class for persistent volumes"
  default      = "standard"
  mutable      = true
}

data "coder_parameter" "enable_apoc" {
  name         = "enable_apoc"
  display_name = "Enable APOC Plugin"
  description  = "Enable Neo4j APOC (Awesome Procedures on Cypher) plugin"
  type         = "bool"
  default      = "true"
  mutable      = true
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  workspace_name     = "${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  neo4j_http_port    = 7474
  neo4j_bolt_port    = 7687
  neo4j_https_port   = 7473
  neo4j_release_name = "${local.workspace_name}-neo4j"
  neo4j_service_name = "${local.neo4j_release_name}"
}

provider "kubernetes" {
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

provider "helm" {
  kubernetes = {
    config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
  }
}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"
  startup_script = <<-EOT
    #!/bin/bash
    set -x
    PATH=/usr/local/bin:/usr/bin:$PATH

    echo "🚀 Starting workspace setup..."

    # Install kubectl if not present
    if ! command -v kubectl &> /dev/null; then
      echo "📦 Installing kubectl..."
      curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
      sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
      rm kubectl
    fi

    # Install helm if not present
    if ! command -v helm &> /dev/null; then
      echo "📦 Installing Helm..."
      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    # Install cypher-shell for Neo4j CLI access
    if ! command -v cypher-shell &> /dev/null; then
      echo "📦 Installing cypher-shell..."
      curl -fsSL https://debian.neo4j.com/neotechnology.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/neo4j.gpg
      echo "deb [signed-by=/usr/share/keyrings/neo4j.gpg] https://debian.neo4j.com stable latest" | sudo tee -a /etc/apt/sources.list.d/neo4j.list
      sudo apt-get update
      sudo apt-get install -y cypher-shell
    fi

    # Function to wait for Neo4j service to be ready
    wait_for_neo4j_service() {
      echo "⏳ Waiting for Neo4j service to be ready..."
      local max_attempts=60
      local attempt=1

      while [ $attempt -le $max_attempts ]; do
        # Check if Neo4j service exists and has endpoints
        if kubectl get svc ${local.neo4j_service_name} -n ${var.workspaces_namespace} >/dev/null 2>&1; then
          # Check if Neo4j pod is running
          if kubectl get pods -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace} --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
            echo "✅ Neo4j service and pod are ready!"
            return 0
          fi
        fi
        echo "⏳ Attempt $attempt/$max_attempts: Neo4j not ready yet..."
        sleep 5
        ((attempt++))
      done

      echo "❌ Neo4j did not become ready within expected time"
      return 1
    }

    # Function to setup port forwarding
    setup_port_forwarding() {
      echo "🔗 Setting up port forwarding to Neo4j service..."

      # Kill any existing port forwards
      pkill -f "kubectl port-forward.*neo4j" || true
      pkill -f "kubectl port-forward.*${local.neo4j_service_name}" || true
      sleep 2

      # Start port forwarding to the Neo4j service (not pod)
      echo "🔗 Starting port forward for HTTP (${local.neo4j_http_port})..."
      kubectl port-forward -n ${var.workspaces_namespace} svc/${local.neo4j_service_name} ${local.neo4j_http_port}:${local.neo4j_http_port} > /tmp/neo4j-http-pf.log 2>&1 &

      echo "🔗 Starting port forward for Bolt (${local.neo4j_bolt_port})..."
      kubectl port-forward -n ${var.workspaces_namespace} svc/${local.neo4j_service_name} ${local.neo4j_bolt_port}:${local.neo4j_bolt_port} > /tmp/neo4j-bolt-pf.log 2>&1 &

      echo "🔗 Starting port forward for HTTPS (${local.neo4j_https_port})..."
      kubectl port-forward -n ${var.workspaces_namespace} svc/${local.neo4j_service_name} ${local.neo4j_https_port}:${local.neo4j_https_port} > /tmp/neo4j-https-pf.log 2>&1 &

      # Wait for port forwards to establish
      sleep 5

      # Test connectivity
      local retries=10
      local retry=1
      while [ $retry -le $retries ]; do
        if curl -s --connect-timeout 2 http://localhost:${local.neo4j_http_port} > /dev/null 2>&1; then
          echo "✅ Neo4j is accessible via port forward!"
          echo "🌐 Neo4j Browser: http://localhost:${local.neo4j_http_port}"
          echo "⚡ Bolt connection: bolt://localhost:${local.neo4j_bolt_port}"
          echo "👤 Username: neo4j"
          echo "🔑 Password: [configured during workspace creation]"
          echo ""
          echo "💡 Use 'cypher-shell -a bolt://localhost:${local.neo4j_bolt_port} -u neo4j' to connect via CLI"
          return 0
        fi
        echo "⏳ Retry $retry/$retries: Testing connectivity..."
        sleep 3
        ((retry++))
      done

      echo "⚠️  Neo4j port forwarding may not be ready yet. Check logs:"
      echo "   - HTTP: /tmp/neo4j-http-pf.log"
      echo "   - Bolt: /tmp/neo4j-bolt-pf.log"
      echo "   - HTTPS: /tmp/neo4j-https-pf.log"
      return 1
    }

    # Wait for Neo4j and set up port forwarding
    if wait_for_neo4j_service; then
      if setup_port_forwarding; then
        echo "🎉 Neo4j setup completed successfully!"
      else
        echo "⚠️  Neo4j is running but port forwarding needs attention"
      fi
    else
      echo "❌ Neo4j setup failed. Check the following:"
      echo "   kubectl get pods -n ${var.workspaces_namespace} -l app.kubernetes.io/name=neo4j"
      echo "   kubectl get svc -n ${var.workspaces_namespace} -l app.kubernetes.io/name=neo4j"
      echo "   kubectl logs -n ${var.workspaces_namespace} -l app.kubernetes.io/name=neo4j"
    fi

    # Create helpful aliases
    cat >> ~/.bashrc << 'ALIASES'
# Neo4j aliases
alias neo4j-status='kubectl get pods -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace}'
alias neo4j-svc='kubectl get svc -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace}'
alias neo4j-logs='kubectl logs -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace} --tail=100'
alias neo4j-shell='cypher-shell -a bolt://localhost:${local.neo4j_bolt_port} -u neo4j'
alias neo4j-restart-pf='pkill -f "kubectl port-forward.*neo4j" && sleep 2 && kubectl port-forward -n ${var.workspaces_namespace} svc/${local.neo4j_service_name} ${local.neo4j_http_port}:${local.neo4j_http_port} > /tmp/neo4j-http-pf.log 2>&1 & kubectl port-forward -n ${var.workspaces_namespace} svc/${local.neo4j_service_name} ${local.neo4j_bolt_port}:${local.neo4j_bolt_port} > /tmp/neo4j-bolt-pf.log 2>&1 &'
alias neo4j-pf-logs='echo "=== HTTP Port Forward ==="; tail -10 /tmp/neo4j-http-pf.log; echo "=== Bolt Port Forward ==="; tail -10 /tmp/neo4j-bolt-pf.log'
ALIASES

    echo "🚀 Workspace setup complete!"
    echo "📝 Available commands:"
    echo "   neo4j-status    - Check Neo4j pod status"
    echo "   neo4j-svc       - Check Neo4j service status"
    echo "   neo4j-logs      - View Neo4j logs"
    echo "   neo4j-shell     - Connect via cypher-shell"
    echo "   neo4j-restart-pf - Restart port forwarding"
    echo "   neo4j-pf-logs   - View port forward logs"
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
    NEO4J_URI           = "bolt://localhost:${local.neo4j_bolt_port}"
    NEO4J_USERNAME      = "neo4j"
    NEO4J_PASSWORD      = data.coder_parameter.neo4j_password.value
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Neo4j Status"
    key          = "4_neo4j_status"
    script       = <<-EOT
      status=$(kubectl get pods -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace} -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo 'NotFound')
      case $status in
        "Running") echo "🟢 Running" ;;
        "Pending") echo "🟡 Starting" ;;
        "Failed") echo "🔴 Failed" ;;
        "NotFound") echo "⚪ Not Deployed" ;;
        *) echo "🟡 $status" ;;
      esac
    EOT
    interval     = 30
    timeout      = 5
  }

  metadata {
    display_name = "Port Forward Status"
    key          = "5_port_forward_status"
    script       = <<-EOT
      if pgrep -f "kubectl port-forward.*${local.neo4j_service_name}.*${local.neo4j_http_port}" > /dev/null; then
        if curl -s --connect-timeout 2 http://localhost:${local.neo4j_http_port} > /dev/null 2>&1; then
          echo "🟢 Active"
        else
          echo "🟡 Starting"
        fi
      else
        echo "🔴 Inactive"
      fi
    EOT
    interval     = 30
    timeout      = 5
  }

  metadata {
    display_name = "Neo4j Service"
    key          = "6_neo4j_service"
    script       = <<-EOT
      if kubectl get svc ${local.neo4j_service_name} -n ${var.workspaces_namespace} >/dev/null 2>&1; then
        endpoints=$(kubectl get endpoints ${local.neo4j_service_name} -n ${var.workspaces_namespace} -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "none")
        if [ "$endpoints" != "none" ] && [ "$endpoints" != "" ]; then
          echo "🟢 Ready"
        else
          echo "🟡 No Endpoints"
        fi
      else
        echo "🔴 Not Found"
      fi
    EOT
    interval     = 30
    timeout      = 5
  }
}

# Enhanced Helm install script with proper escaping
resource "coder_script" "helm_install" {
  agent_id      = coder_agent.main.id
  display_name  = "Install Neo4j"
  icon          = "/icon/database.svg"
  run_on_start  = true
  script = <<-EOT
    #!/bin/bash
    set -x
    sleep 60

    echo "🔧 Adding Neo4j Helm repository..."
    helm repo add neo4j https://helm.neo4j.com/neo4j
    helm repo update

    echo "📦 Installing Neo4j with Helm..."

    # Create values file to avoid escaping issues
    cat > /tmp/neo4j-values.yaml << 'VALUES'
neo4j:
  name: "neo4j"
  password: "${data.coder_parameter.neo4j_password.value}"
  resources:
    cpu: ${data.coder_parameter.cpu.value}
    memory: ${data.coder_parameter.memory.value}Gi
  config:
    dbms.security.procedures.unrestricted: "apoc.*,algo.*"
    dbms.security.procedures.allowlist: "apoc.*,algo.*"
    dbms.memory.heap.initial_size: "${floor(data.coder_parameter.memory.value * 0.5)}G"
    dbms.memory.heap.max_size: "${floor(data.coder_parameter.memory.value * 0.5)}G"
    dbms.memory.pagecache.size: "${floor(data.coder_parameter.memory.value * 0.3)}G"

volumes:
  data:
    mode: dynamic
    dynamic:
      storageClassName: ${data.coder_parameter.storage_class.value}
      accessModes:
        - ReadWriteOnce
      requests:
        storage: ${data.coder_parameter.storage.value}Gi

services:
  neo4j:
    enabled: true
    spec:
      type: ClusterIP
      ports:
        http:
          enabled: true
          port: ${local.neo4j_http_port}
        https:
          enabled: true
          port: ${local.neo4j_https_port}
        bolt:
          enabled: true
          port: ${local.neo4j_bolt_port}

podLabels:
  "app.kubernetes.io/managed-by": "coder"
  "coder.workspace": "${data.coder_workspace.me.name}"
  "coder.workspace_owner": "${data.coder_workspace_owner.me.name}"

podAnnotations:
  "coder.workspace.id": "${data.coder_workspace.me.id}"
  "coder.user.email": "${data.coder_workspace_owner.me.email}"

%{ if data.coder_parameter.enable_apoc.value == "true" ~}
env:
  NEO4J_PLUGINS: '["apoc"]'
%{ endif ~}
VALUES

    # Install with values file
    helm upgrade --install ${local.neo4j_release_name} neo4j/neo4j \
      --namespace ${var.workspaces_namespace} \
      --version ${data.coder_parameter.neo4j_version.value} \
      --values /tmp/neo4j-values.yaml \
      --wait --timeout=600s

    echo "✅ Neo4j installation completed!"
    echo "📊 Release: ${local.neo4j_release_name}"
    echo "🏷️  Version: ${data.coder_parameter.neo4j_version.value}"
    echo "💾 Storage: ${data.coder_parameter.storage.value}GB"

    # Clean up values file
    rm -f /tmp/neo4j-values.yaml

    # Verify installation
    echo "🔍 Verifying installation..."
    kubectl get pods -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace}
    kubectl get svc -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace}
  EOT
}

resource "coder_script" "helm_uninstall" {
  agent_id      = coder_agent.main.id
  display_name  = "Uninstall Neo4j"
  icon          = "/icon/database.svg"
  run_on_stop   = true
  script = <<-EOT
    #!/bin/bash
    set -x
    sleep 60

    echo "🗑️  Stopping port forwards..."
    pkill -f "kubectl port-forward.*neo4j" || true
    pkill -f "kubectl port-forward.*${local.neo4j_service_name}" || true

    echo "🗑️  Uninstalling Neo4j..."
    helm uninstall ${local.neo4j_release_name} --namespace ${var.workspaces_namespace} || true

    echo "✅ Neo4j uninstalled!"
  EOT
}

resource "coder_script" "helm_status" {
  agent_id      = coder_agent.main.id
  display_name  = "Check Neo4j Status"
  icon          = "/icon/database.svg"
  run_on_start  = false
  script = <<-EOT
    #!/bin/bash

    echo "=== 📊 Helm Release Status ==="
    if helm status ${local.neo4j_release_name} --namespace ${var.workspaces_namespace} 2>/dev/null; then
      echo ""
      echo "=== 🏷️  Release Values ==="
      helm get values ${local.neo4j_release_name} --namespace ${var.workspaces_namespace}
    else
      echo "❌ Neo4j not installed or not found"
    fi

    echo ""
    echo "=== 🐳 Pod Status ==="
    kubectl get pods -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace} -o wide 2>/dev/null || echo "No Neo4j pods found"

    echo ""
    echo "=== 🌐 Service Status ==="
    kubectl get svc -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace} -o wide 2>/dev/null || echo "No Neo4j services found"

    echo ""
    echo "=== 🔗 Endpoints Status ==="
    kubectl get endpoints -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace} 2>/dev/null || echo "No Neo4j endpoints found"

    echo ""
    echo "=== 💾 Storage Status ==="
    kubectl get pvc -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace} 2>/dev/null || echo "No Neo4j PVCs found"

    echo ""
    echo "=== 🔗 Port Forward Status ==="
    if pgrep -f "kubectl port-forward.*${local.neo4j_service_name}" > /dev/null; then
      echo "✅ Port forwarding is active"
      echo "🌐 Neo4j Browser: http://localhost:${local.neo4j_http_port}"
      echo "⚡ Bolt: bolt://localhost:${local.neo4j_bolt_port}"

      # Test connectivity
      if curl -s --connect-timeout 2 http://localhost:${local.neo4j_http_port} > /dev/null 2>&1; then
        echo "✅ HTTP connection test: SUCCESS"
      else
        echo "❌ HTTP connection test: FAILED"
      fi
    else
      echo "❌ Port forwarding is not active"
      echo "💡 Run 'neo4j-restart-pf' to restart port forwarding"
    fi

    echo ""
    echo "=== 📝 Port Forward Logs ==="
    if [ -f /tmp/neo4j-http-pf.log ]; then
      echo "HTTP Port Forward (last 5 lines):"
      tail -5 /tmp/neo4j-http-pf.log
    fi
    if [ -f /tmp/neo4j-bolt-pf.log ]; then
      echo "Bolt Port Forward (last 5 lines):"
      tail -5 /tmp/neo4j-bolt-pf.log
    fi
  EOT
}

# Script to restart port forwarding
resource "coder_script" "restart_port_forward" {
  agent_id      = coder_agent.main.id
  display_name  = "Restart Port Forward"
  icon          = "/icon/network.svg"
  run_on_start  = true
  script = <<-EOT
    #!/bin/bash
    set -x
    sleep 60

    echo "🔄 Restarting Neo4j port forwarding..."

    # Kill existing port forwards
    pkill -f "kubectl port-forward.*neo4j" || true
    pkill -f "kubectl port-forward.*${local.neo4j_service_name}" || true
    sleep 2

    # Check if Neo4j service exists
    if ! kubectl get svc ${local.neo4j_service_name} -n ${var.workspaces_namespace} >/dev/null 2>&1; then
      echo "❌ Neo4j service '${local.neo4j_service_name}' not found in namespace '${var.workspaces_namespace}'"
      echo "Available services:"
      kubectl get svc -n ${var.workspaces_namespace}
      exit 1
    fi

    # Check if Neo4j pod is running
    if ! kubectl get pods -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace} --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
      echo "❌ Neo4j pod is not running. Please check the pod status first."
      kubectl get pods -l app.kubernetes.io/name=neo4j -n ${var.workspaces_namespace}
      exit 1
    fi

    # Start new port forwards
    echo "🚀 Starting port forwards to service ${local.neo4j_service_name}..."
    kubectl port-forward -n ${var.workspaces_namespace} svc/${local.neo4j_service_name} ${local.neo4j_http_port}:${local.neo4j_http_port} > /tmp/neo4j-http-pf.log 2>&1 &
    kubectl port-forward -n ${var.workspaces_namespace} svc/${local.neo4j_service_name} ${local.neo4j_bolt_port}:${local.neo4j_bolt_port} > /tmp/neo4j-bolt-pf.log 2>&1 &
    kubectl port-forward -n ${var.workspaces_namespace} svc/${local.neo4j_service_name} ${local.neo4j_https_port}:${local.neo4j_https_port} > /tmp/neo4j-https-pf.log 2>&1 &

    sleep 5

    # Test connectivity
    if curl -s --connect-timeout 3 http://localhost:${local.neo4j_http_port} > /dev/null 2>&1; then
      echo "✅ Port forwarding restored successfully!"
      echo "🌐 Neo4j Browser: http://localhost:${local.neo4j_http_port}"
      echo "⚡ Bolt: bolt://localhost:${local.neo4j_bolt_port}"
    else
      echo "⚠️  Port forwarding started but connectivity test failed."
      echo "Check logs: neo4j-pf-logs"
      echo "Service info:"
      kubectl get svc ${local.neo4j_service_name} -n ${var.workspaces_namespace}
    fi
  EOT
}

resource "coder_app" "neo4j_browser" {
  agent_id     = coder_agent.main.id
  slug         = "neo4j-browser"
  display_name = "Neo4j Browser"
  url          = "http://localhost:${local.neo4j_http_port}"
  icon         = "https://neo4j.com/wp-content/themes/neo4jweb/assets/images/neo4j-logo-color.png"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:${local.neo4j_http_port}"
    interval  = 5
    threshold = 6
  }
}

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = local.workspace_name
    namespace = var.workspaces_namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = local.workspace_name
      "app.kubernetes.io/part-of"  = "coder"
      "coder.workspace"            = data.coder_workspace.me.name
      "coder.workspace_owner"      = data.coder_workspace_owner.me.name
    }
    annotations = {
      "coder.workspace.id" = data.coder_workspace.me.id
      "coder.user.email"   = data.coder_workspace_owner.me.email
    }
  }

  spec {
    security_context {
      run_as_user = 1000
      fs_group    = 1000
    }

    container {
      name              = "dev"
      image             = "codercom/enterprise-base:ubuntu"
      image_pull_policy = "Always"
      command           = ["sh", "-c", coder_agent.main.init_script]

      security_context {
        run_as_user = "1000"
      }

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }

      resources {
        requests = {
          "cpu"    = "250m"
          "memory" = "512Mi"
        }
        limits = {
          "cpu"    = "2"
          "memory" = "4Gi"
        }
      }

      volume_mount {
        mount_path = "/home/coder"
        name       = "home"
        read_only  = false
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home.metadata.0.name
        read_only  = false
      }
    }

    affinity {
      pod_anti_affinity {
        preferred_during_scheduling_ignored_during_execution {
          weight = 1
          pod_affinity_term {
            topology_key = "kubernetes.io/hostname"
            label_selector {
              match_expressions {
                key      = "app.kubernetes.io/name"
                operator = "In"
                values   = ["coder-workspace"]
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "${local.workspace_name}-home"
    namespace = var.workspaces_namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = local.workspace_name
      "app.kubernetes.io/part-of"  = "coder"
      "coder.workspace"            = data.coder_workspace.me.name
      "coder.workspace_owner"      = data.coder_workspace_owner.me.name
    }
    annotations = {
      "coder.workspace.id" = data.coder_workspace.me.id
      "coder.user.email"   = data.coder_workspace_owner.me.email
    }
  }

  wait_until_bound = false

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
    storage_class_name = data.coder_parameter.storage_class.value
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_pod.main[0].id

  item {
    key   = "Neo4j Browser URL"
    value = "http://localhost:${local.neo4j_http_port}"
  }

  item {
    key   = "Neo4j Bolt URL"
    value = "bolt://localhost:${local.neo4j_bolt_port}"
  }

  item {
    key   = "Username"
    value = "neo4j"
  }

  item {
    key   = "CPU"
    value = "${data.coder_parameter.cpu.value} cores"
  }

  item {
    key   = "Memory"
    value = "${data.coder_parameter.memory.value}GB"
  }

  item {
    key   = "Storage"
    value = "${data.coder_parameter.storage.value}GB"
  }

  item {
    key   = "APOC Plugin"
    value = data.coder_parameter.enable_apoc.value == "true" ? "Enabled" : "Disabled"
  }

  item {
    key   = "Chart Version"
    value = data.coder_parameter.neo4j_version.value
  }

  item {
    key   = "Service Name"
    value = local.neo4j_service_name
  }
}
