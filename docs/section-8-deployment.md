# Section 8: Containerization and Cloud-Native Deployment

This section details the strategy for packaging, deploying, and orchestrating Qilbee OS in modern cloud environments. The architecture is designed to be cloud-native, leveraging Docker for containerization and Kubernetes for orchestration to achieve scalability, resilience, and maintainability.

## 8.1. Containerization Strategy with Docker

All Qilbee OS components MUST be packaged as Docker containers. This approach ensures a consistent and reproducible runtime environment, encapsulating the application code with all its dependencies.

### 8.1.1. Dockerfile Best Practices

The Dockerfile for each component will adhere to established best practices to create optimized, secure, and efficient images:

#### Multi-stage Build Strategy

```dockerfile
# Dockerfile for Qilbee OS
FROM python:3.11-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy requirements first for better layer caching
COPY requirements.txt requirements-dev.txt ./

# Install Python dependencies
RUN pip install --no-cache-dir --user -r requirements.txt

# Copy source code
COPY src/ ./src/
COPY setup.py README.md ./

# Install the application
RUN pip install --no-cache-dir --user .

# Production stage
FROM python:3.11-slim as production

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    # Essential system packages
    curl \
    gnupg \
    ca-certificates \
    # GUI automation dependencies
    xvfb \
    x11-utils \
    scrot \
    xdotool \
    # nsjail for sandboxing
    nsjail \
    # Wayland support
    grim \
    ydotool \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r qilbee && useradd -r -g qilbee -s /bin/bash qilbee

# Copy Python packages from builder
COPY --from=builder /root/.local /home/qilbee/.local

# Copy application files
COPY --chown=qilbee:qilbee config/ /etc/qilbee/
COPY --chown=qilbee:qilbee scripts/ /usr/local/bin/

# Set PATH to include user packages
ENV PATH=/home/qilbee/.local/bin:$PATH

# Create necessary directories
RUN mkdir -p /tmp/qilbee-sandboxes /var/log/qilbee \
    && chown -R qilbee:qilbee /tmp/qilbee-sandboxes /var/log/qilbee

# Switch to non-root user
USER qilbee

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Expose ports
EXPOSE 8080 50051

# Default command
CMD ["qilbee-os", "--config", "/etc/qilbee/config.yaml"]
```

#### Component-Specific Dockerfiles

```dockerfile
# Dockerfile.agent-orchestrator
FROM qilbee-os-base:latest

# Install orchestrator-specific dependencies
RUN pip install --no-cache-dir anthropic>=0.25.0

# Copy orchestrator code
COPY src/agent_orchestrator/ /app/agent_orchestrator/

# Set component-specific environment
ENV QILBEE_COMPONENT=agent_orchestrator

CMD ["python", "-m", "agent_orchestrator.main"]
```

```dockerfile
# Dockerfile.task-scheduler  
FROM qilbee-os-base:latest

# Install scheduler-specific dependencies
RUN pip install --no-cache-dir celery[redis]>=5.3.0

# Copy scheduler code
COPY src/task_scheduler/ /app/task_scheduler/

ENV QILBEE_COMPONENT=task_scheduler

CMD ["python", "-m", "task_scheduler.main"]
```

```dockerfile
# Dockerfile.execution-engine
FROM qilbee-os-base:latest

# Additional security tools
RUN apt-get update && apt-get install -y \
    apparmor-utils \
    && rm -rf /var/lib/apt/lists/*

# Copy execution engine code
COPY src/execution_engine/ /app/execution_engine/

ENV QILBEE_COMPONENT=execution_engine

CMD ["python", "-m", "execution_engine.main"]
```

### 8.1.2. Docker Image Optimization

#### .dockerignore Configuration

```dockerignore
# Version control
.git
.gitignore

# Python
__pycache__
*.pyc
*.pyo
*.pyd
.Python
env
pip-log.txt
pip-delete-this-directory.txt
.tox
.coverage
.coverage.*
.cache
nosetests.xml
coverage.xml
*.cover
*.log

# Development files
.vscode/
.idea/
*.swp
*.swo
*~

# Testing
tests/
pytest.ini
.pytest_cache/

# Documentation
docs/
*.md
!README.md

# Local configuration
.env
.env.local
config/local.yaml

# Temporary files
tmp/
temp/
*.tmp
```

#### Multi-architecture Build Support

```yaml
# docker-bake.hcl
target "qilbee-os" {
  context = "."
  dockerfile = "Dockerfile"
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
  tags = [
    "qilbee-os:latest",
    "qilbee-os:${VERSION}"
  ]
}

target "agent-orchestrator" {
  context = "."
  dockerfile = "Dockerfile.agent-orchestrator"
  platforms = [
    "linux/amd64", 
    "linux/arm64"
  ]
  tags = [
    "qilbee-os/agent-orchestrator:latest",
    "qilbee-os/agent-orchestrator:${VERSION}"
  ]
}
```

## 8.2. Orchestration with Kubernetes

Qilbee OS is designed to be deployed and managed on a Kubernetes cluster. Kubernetes will handle service discovery, scaling, self-healing, and configuration management.

### 8.2.1. Kubernetes Resource Definitions

#### Namespace and RBAC

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: qilbee-os
  labels:
    name: qilbee-os
    app.kubernetes.io/name: qilbee-os
    app.kubernetes.io/version: "1.0.0"

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: qilbee-os
  namespace: qilbee-os

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: qilbee-os
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: qilbee-os
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: qilbee-os
subjects:
- kind: ServiceAccount
  name: qilbee-os
  namespace: qilbee-os
```

#### ConfigMaps and Secrets

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: qilbee-os-config
  namespace: qilbee-os
data:
  config.yaml: |
    server:
      host: "0.0.0.0"
      port: 8080
      debug: false
    
    celery:
      broker_url: "amqps://qilbee:${RABBITMQ_PASSWORD}@rabbitmq:5671/qilbee"
      result_backend: "redis+ssl://redis:6380/0"
      task_serializer: "json"
      result_serializer: "json"
      
    anthropic:
      api_key: "${ANTHROPIC_API_KEY}"
      model: "claude-sonnet-4-20250514"
      
    security:
      tls_cert_path: "/etc/qilbee/tls/server.crt"
      tls_key_path: "/etc/qilbee/tls/server.key"
      ca_cert_path: "/etc/qilbee/tls/ca.crt"
      
    sandbox:
      default_timeout: 30
      default_memory_limit: 256
      nsjail_config_path: "/etc/qilbee/nsjail-default.cfg"

---
apiVersion: v1
kind: Secret
metadata:
  name: qilbee-os-secrets
  namespace: qilbee-os
type: Opaque
data:
  anthropic-api-key: <base64-encoded-api-key>
  rabbitmq-password: <base64-encoded-password>
  oauth-client-secret: <base64-encoded-client-secret>
  jwt-private-key: <base64-encoded-private-key>

---
apiVersion: v1
kind: Secret  
metadata:
  name: qilbee-os-tls
  namespace: qilbee-os
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-certificate>
  tls.key: <base64-encoded-private-key>
  ca.crt: <base64-encoded-ca-certificate>
```

#### Agent Orchestrator Deployment

```yaml
# agent-orchestrator.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: agent-orchestrator
  namespace: qilbee-os
  labels:
    app: agent-orchestrator
    component: qilbee-os
spec:
  replicas: 2
  selector:
    matchLabels:
      app: agent-orchestrator
  template:
    metadata:
      labels:
        app: agent-orchestrator
        component: qilbee-os
    spec:
      serviceAccountName: qilbee-os
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: agent-orchestrator
        image: qilbee-os/agent-orchestrator:1.0.0
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 50051
          name: grpc
        env:
        - name: QILBEE_CONFIG_PATH
          value: "/etc/qilbee/config.yaml"
        - name: ANTHROPIC_API_KEY
          valueFrom:
            secretKeyRef:
              name: qilbee-os-secrets
              key: anthropic-api-key
        - name: RABBITMQ_PASSWORD
          valueFrom:
            secretKeyRef:
              name: qilbee-os-secrets
              key: rabbitmq-password
        volumeMounts:
        - name: config
          mountPath: /etc/qilbee
          readOnly: true
        - name: tls-certs
          mountPath: /etc/qilbee/tls
          readOnly: true
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTPS
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
            scheme: HTTPS
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: qilbee-os-config
      - name: tls-certs
        secret:
          secretName: qilbee-os-tls

---
apiVersion: v1
kind: Service
metadata:
  name: agent-orchestrator
  namespace: qilbee-os
spec:
  selector:
    app: agent-orchestrator
  ports:
  - name: https
    port: 443
    targetPort: 8080
    protocol: TCP
  - name: grpc
    port: 50051
    targetPort: 50051
    protocol: TCP
  type: ClusterIP
```

#### Celery Worker Deployment for Swarm Mode

```yaml
# celery-workers.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-workers
  namespace: qilbee-os
  labels:
    app: celery-workers
    component: qilbee-os
spec:
  replicas: 3  # Horizontally scalable
  selector:
    matchLabels:
      app: celery-workers
  template:
    metadata:
      labels:
        app: celery-workers
        component: qilbee-os
    spec:
      serviceAccountName: qilbee-os
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: celery-worker
        image: qilbee-os/execution-engine:1.0.0
        command: ["celery", "worker"]
        args:
        - "--app=qilbee_os.celery_app"
        - "--loglevel=info"
        - "--concurrency=4"
        - "--pool=prefork"
        - "--queues=default,priority,tools"
        env:
        - name: CELERY_BROKER_URL
          value: "amqps://qilbee:$(RABBITMQ_PASSWORD)@rabbitmq:5671/qilbee"
        - name: CELERY_RESULT_BACKEND
          value: "redis+ssl://redis:6380/0"
        - name: RABBITMQ_PASSWORD
          valueFrom:
            secretKeyRef:
              name: qilbee-os-secrets
              key: rabbitmq-password
        volumeMounts:
        - name: config
          mountPath: /etc/qilbee
          readOnly: true
        - name: tls-certs
          mountPath: /etc/qilbee/tls
          readOnly: true
        - name: sandbox-tmp
          mountPath: /tmp/qilbee-sandboxes
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          exec:
            command:
            - celery
            - inspect
            - ping
            - --app=qilbee_os.celery_app
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          exec:
            command:
            - celery
            - inspect
            - active
            - --app=qilbee_os.celery_app
          initialDelaySeconds: 30
          periodSeconds: 15
      volumes:
      - name: config
        configMap:
          name: qilbee-os-config
      - name: tls-certs
        secret:
          secretName: qilbee-os-tls
      - name: sandbox-tmp
        emptyDir:
          sizeLimit: "10Gi"

---
# Horizontal Pod Autoscaler for Swarm scaling
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: celery-workers-hpa
  namespace: qilbee-os
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: celery-workers
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: External
    external:
      metric:
        name: rabbitmq_queue_messages_ready
        selector:
          matchLabels:
            queue: "default"
      target:
        type: AverageValue
        averageValue: "5"  # Scale up when >5 messages per worker
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 100  # Double workers when scaling up
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 600
      policies:
      - type: Percent
        value: 10   # Reduce by 10% when scaling down
        periodSeconds: 60
```

### 8.2.2. GUI Automation Configuration

To enable the direct execution of GUI automation tools as specified in Section 5.5, the Kubernetes Deployment manifest for the Qilbee OS instance must include specific configurations to grant access to the host's display server.

#### X11 Configuration

```yaml
# gui-automation-x11.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qilbee-gui-automation
  namespace: qilbee-os
spec:
  replicas: 1  # GUI automation should be singleton
  selector:
    matchLabels:
      app: qilbee-gui-automation
  template:
    metadata:
      labels:
        app: qilbee-gui-automation
    spec:
      hostNetwork: true  # Required for GUI access
      securityContext:
        runAsUser: 1000  # Match host user for X11 access
      containers:
      - name: gui-automation
        image: qilbee-os/gui-automation:1.0.0
        env:
        - name: DISPLAY
          value: ":0"
        - name: XAUTHORITY
          value: "/tmp/.X11-unix/.Xauth"
        volumeMounts:
        - name: x11-socket
          mountPath: /tmp/.X11-unix
          readOnly: false
        - name: x11-auth
          mountPath: /tmp/.X11-unix/.Xauth
          readOnly: true
        securityContext:
          capabilities:
            add:
            - SYS_ADMIN  # Required for GUI automation
          privileged: false
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: x11-socket
        hostPath:
          path: /tmp/.X11-unix
          type: Directory
      - name: x11-auth
        hostPath:
          path: /home/user/.Xauthority
          type: File
      nodeSelector:
        qilbee.io/gui-capable: "true"  # Only schedule on GUI-capable nodes
      tolerations:
      - key: "qilbee.io/gui-automation"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
```

#### Wayland Configuration

```yaml
# gui-automation-wayland.yaml  
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qilbee-gui-automation-wayland
  namespace: qilbee-os
spec:
  replicas: 1
  selector:
    matchLabels:
      app: qilbee-gui-automation-wayland
  template:
    metadata:
      labels:
        app: qilbee-gui-automation-wayland
    spec:
      hostNetwork: true
      securityContext:
        runAsUser: 1000
      containers:
      - name: gui-automation
        image: qilbee-os/gui-automation:1.0.0
        env:
        - name: WAYLAND_DISPLAY
          value: "wayland-0"
        - name: XDG_RUNTIME_DIR
          value: "/run/user/1000"
        volumeMounts:
        - name: wayland-runtime
          mountPath: /run/user/1000
          readOnly: false
        securityContext:
          capabilities:
            add:
            - SYS_ADMIN
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: wayland-runtime
        hostPath:
          path: /run/user/1000
          type: Directory
      nodeSelector:
        qilbee.io/gui-capable: "true"
        qilbee.io/display-server: "wayland"
```

## 8.3. Helm Chart for Deployment

The entire Qilbee OS application stack will be packaged as a Helm chart. Helm acts as the package manager for Kubernetes, allowing for templated, configurable, and repeatable deployments.

### 8.3.1. Helm Chart Structure

```
qilbee-os/
├── Chart.yaml
├── values.yaml
├── values-production.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secrets.yaml
│   ├── agent-orchestrator/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── task-scheduler/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── celery-workers/
│   │   ├── deployment.yaml
│   │   └── hpa.yaml
│   ├── gui-automation/
│   │   └── deployment.yaml
│   ├── ingress.yaml
│   └── servicemonitor.yaml
├── charts/
│   ├── rabbitmq/
│   ├── redis/
│   └── postgresql/
└── crds/
    └── qilbee-agents.yaml
```

#### Chart.yaml

```yaml
apiVersion: v2
name: qilbee-os
description: A Helm chart for Qilbee OS - Conversational Operating System
type: application
version: 1.0.0
appVersion: "1.0.0"
keywords:
  - ai
  - conversational
  - automation
  - enterprise
home: https://github.com/aicubeKruz/qilbee-os
sources:
  - https://github.com/aicubeKruz/qilbee-os
maintainers:
  - name: AICUBE Technology
    email: support@aicube.technology
dependencies:
  - name: rabbitmq
    version: "12.0.0"
    repository: "https://charts.bitnami.com/bitnami"
    condition: rabbitmq.enabled
  - name: redis
    version: "18.0.0"  
    repository: "https://charts.bitnami.com/bitnami"
    condition: redis.enabled
  - name: postgresql
    version: "12.0.0"
    repository: "https://charts.bitnami.com/bitnami"
    condition: postgresql.enabled
```

#### values.yaml

```yaml
# Default values for qilbee-os
global:
  imageRegistry: "docker.io"
  imagePullSecrets: []
  storageClass: ""

image:
  registry: docker.io
  repository: qilbee-os
  tag: "1.0.0"
  pullPolicy: IfNotPresent

nameOverride: ""
fullnameOverride: ""

# Agent Orchestrator configuration
agentOrchestrator:
  enabled: true
  replicaCount: 2
  image:
    repository: qilbee-os/agent-orchestrator
    tag: "1.0.0"
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"
  service:
    type: ClusterIP
    httpsPort: 443
    grpcPort: 50051

# Task Scheduler configuration  
taskScheduler:
  enabled: true
  replicaCount: 1
  image:
    repository: qilbee-os/task-scheduler
    tag: "1.0.0"
  resources:
    requests:
      memory: "256Mi"
      cpu: "125m"
    limits:
      memory: "512Mi"
      cpu: "250m"

# Celery Workers configuration
celeryWorkers:
  enabled: true
  replicaCount: 3
  image:
    repository: qilbee-os/execution-engine
    tag: "1.0.0"
  concurrency: 4
  queues: "default,priority,tools"
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi" 
      cpu: "1000m"
  
  # Horizontal Pod Autoscaler
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 20
    targetCPUUtilizationPercentage: 70
    targetQueueLength: 5

# GUI Automation
guiAutomation:
  enabled: false  # Disabled by default for security
  displayServer: "x11"  # or "wayland"
  nodeSelector:
    qilbee.io/gui-capable: "true"

# Configuration
config:
  server:
    host: "0.0.0.0"
    port: 8080
    debug: false
  
  anthropic:
    model: "claude-sonnet-4-20250514"
    # API key provided via secret
  
  security:
    tlsEnabled: true
    oauth:
      enabled: true
      tokenExpiry: 3600
  
  sandbox:
    defaultTimeout: 30
    defaultMemoryLimit: 256
    enableNetworking: false

# Secrets configuration
secrets:
  anthropicApiKey: ""  # Set in production values
  rabbitmqPassword: ""
  oauthClientSecret: ""
  jwtPrivateKey: ""

# TLS configuration
tls:
  enabled: true
  # Certificates provided via secrets

# Ingress configuration
ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: qilbee-os.local
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: qilbee-os-tls
      hosts:
        - qilbee-os.local

# Dependencies
rabbitmq:
  enabled: true
  auth:
    username: qilbee
    existingPasswordSecret: qilbee-os-secrets
    existingPasswordKey: rabbitmq-password
  tls:
    enabled: true
    existingSecret: qilbee-os-tls
  clustering:
    enabled: true
    replicaCount: 3

redis:
  enabled: true
  architecture: standalone
  auth:
    enabled: true
    existingSecret: qilbee-os-secrets
    existingSecretPasswordKey: redis-password
  tls:
    enabled: true
    existingSecret: qilbee-os-tls

postgresql:
  enabled: false  # Optional for advanced deployments
  auth:
    postgresPassword: ""
    database: qilbee_os

# Monitoring
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: monitoring
    labels:
      release: prometheus

# Resource quotas
resourceQuota:
  enabled: false
  requests:
    cpu: "4"
    memory: "8Gi"
  limits:
    cpu: "8"
    memory: "16Gi"

# Pod Security Standards
podSecurityPolicy:
  enabled: true

# Network Policies  
networkPolicy:
  enabled: true
  ingress:
    enabled: true
  egress:
    enabled: true
```

### 8.3.2. Helm Installation Commands

```bash
# Add required Helm repositories
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install Qilbee OS in development mode
helm install qilbee-os ./qilbee-os \
  --namespace qilbee-os \
  --create-namespace \
  --values values.yaml

# Install in production mode with custom values
helm install qilbee-os ./qilbee-os \
  --namespace qilbee-os-prod \
  --create-namespace \
  --values values-production.yaml \
  --set secrets.anthropicApiKey="sk-..." \
  --set ingress.hosts[0].host="qilbee.company.com"

# Upgrade deployment
helm upgrade qilbee-os ./qilbee-os \
  --namespace qilbee-os-prod \
  --values values-production.yaml

# Uninstall
helm uninstall qilbee-os --namespace qilbee-os-prod
```

## 8.4. The Web Gateway: noVNC and the WebSocket Proxy

To meet the requirement of browser-based access, a bridge between the native VNC protocol and modern web technologies is necessary.

### 8.4.1. noVNC Integration

```yaml
# novnc-gateway.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: novnc-gateway
  namespace: qilbee-os
spec:
  replicas: 1
  selector:
    matchLabels:
      app: novnc-gateway
  template:
    metadata:
      labels:
        app: novnc-gateway
    spec:
      containers:
      - name: novnc
        image: theasp/novnc:latest
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: DISPLAY_WIDTH
          value: "1024"
        - name: DISPLAY_HEIGHT
          value: "768"
        - name: VNC_PASSWORD
          valueFrom:
            secretKeyRef:
              name: vnc-secret
              key: password
        volumeMounts:
        - name: vnc-config
          mountPath: /etc/vnc
      - name: websockify
        image: novnc/websockify:latest
        ports:
        - containerPort: 6080
          name: websocket
        args:
        - "--web"
        - "/usr/share/novnc/"
        - "--cert"
        - "/etc/ssl/certs/server.crt"
        - "--key" 
        - "/etc/ssl/private/server.key"
        - "6080"
        - "localhost:5901"
        volumeMounts:
        - name: tls-certs
          mountPath: /etc/ssl/certs
          readOnly: true
        - name: tls-keys
          mountPath: /etc/ssl/private
          readOnly: true
      volumes:
      - name: vnc-config
        configMap:
          name: vnc-config
      - name: tls-certs
        secret:
          secretName: qilbee-os-tls
          items:
          - key: tls.crt
            path: server.crt
      - name: tls-keys
        secret:
          secretName: qilbee-os-tls
          items:
          - key: tls.key
            path: server.key

---
apiVersion: v1
kind: Service
metadata:
  name: novnc-gateway
  namespace: qilbee-os
spec:
  selector:
    app: novnc-gateway
  ports:
  - name: websocket-ssl
    port: 6080
    targetPort: 6080
    protocol: TCP
  type: ClusterIP

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: novnc-ingress
  namespace: qilbee-os
  annotations:
    nginx.ingress.kubernetes.io/websocket-services: "novnc-gateway"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - vnc.qilbee-os.local
    secretName: qilbee-os-tls
  rules:
  - host: vnc.qilbee-os.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: novnc-gateway
            port:
              number: 6080
```

### 8.4.2. Security Configuration for WebSocket Proxy

```bash
#!/bin/bash
# generate-vnc-certs.sh
# Generate self-signed certificates for VNC over WebSockets

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout vnc-server.key \
  -out vnc-server.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=vnc.qilbee-os.local"

# Create Kubernetes secret
kubectl create secret tls vnc-tls-secret \
  --cert=vnc-server.crt \
  --key=vnc-server.key \
  --namespace=qilbee-os
```

This comprehensive deployment strategy ensures that Qilbee OS can be reliably deployed in production Kubernetes environments with proper security, scalability, and maintainability features. The Helm chart provides flexibility for different deployment scenarios while maintaining enterprise-grade operational capabilities.