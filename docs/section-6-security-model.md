# Section 6: System-Wide Security Model and Identity Management

This section details the comprehensive, multi-layered security architecture designed to protect Qilbee OS. The model addresses authentication, authorization, and data-in-transit encryption across all system components, ensuring the integrity and confidentiality required for an enterprise environment.

## 6.1. Authentication and Authorization: OAuth 2.0 for Inter-Service Communication

All communication between Qilbee OS services and agents will be secured using the OAuth 2.0 framework, the industry-standard protocol for authorization. A central, dedicated Authorization Server (AS) will be a core component of any Qilbee OS deployment, responsible for authenticating clients and issuing JSON Web Tokens (JWTs) as Bearer Tokens.

### OAuth 2.0 Grant Flows

The system will leverage two distinct OAuth 2.0 grant flows, tailored to specific use cases:

#### Client Credentials Grant
This flow will be used exclusively for all internal, machine-to-machine (M2M) communication. This includes communication between the core services within a single Qilbee Instance and communication between different Qilbee agents across the network. In this flow, a service or agent authenticates itself directly with the AS using its client ID and secret to obtain an access token. This is the standard, secure pattern for server-to-server interactions where no end-user is present.

#### Authorization Code Grant with PKCE  
This flow is mandated for all user-facing applications (e.g., a web dashboard, a mobile client) that need to interact with the Qilbee OS API on behalf of a user. The Authorization Code flow ensures that the user's credentials are never exposed to the client application. The addition of the PKCE (Proof Key for Code Exchange) extension is a critical security enhancement that mitigates authorization code interception attacks, making it the current best practice for securing native and single-page web applications.

### OAuth 2.0 Implementation

```python
import jwt
import httpx
from datetime import datetime, timedelta
from typing import Dict, Any, Optional
import secrets
import hashlib
import base64

class OAuth2AuthorizationServer:
    def __init__(self, private_key: str, issuer: str):
        self.private_key = private_key
        self.issuer = issuer
        self.clients = {}  # In production, use database
        self.active_tokens = set()  # Token blacklist/whitelist
    
    def register_client(self, client_id: str, client_secret: str, grant_types: list, scopes: list):
        """Register a new OAuth client."""
        self.clients[client_id] = {
            "client_secret": client_secret,
            "grant_types": grant_types,
            "scopes": scopes,
            "created_at": datetime.utcnow()
        }
    
    async def handle_client_credentials_grant(self, client_id: str, client_secret: str, scope: str = None) -> Dict[str, Any]:
        """Handle client credentials grant for M2M authentication."""
        
        # Validate client credentials
        if not self._validate_client(client_id, client_secret, "client_credentials"):
            return {"error": "invalid_client"}
        
        # Generate access token
        token_payload = {
            "iss": self.issuer,
            "sub": client_id,
            "aud": "qilbee-os",
            "iat": datetime.utcnow(),
            "exp": datetime.utcnow() + timedelta(hours=1),
            "scope": scope or "default",
            "token_type": "access_token",
            "client_id": client_id
        }
        
        access_token = jwt.encode(token_payload, self.private_key, algorithm="RS256")
        self.active_tokens.add(access_token)
        
        return {
            "access_token": access_token,
            "token_type": "Bearer",
            "expires_in": 3600,
            "scope": token_payload["scope"]
        }
    
    async def handle_authorization_code_grant(self, 
                                            client_id: str,
                                            code: str, 
                                            redirect_uri: str,
                                            code_verifier: str = None) -> Dict[str, Any]:
        """Handle authorization code grant with PKCE support."""
        
        # Validate authorization code and PKCE
        if not self._validate_authorization_code(code, client_id, redirect_uri, code_verifier):
            return {"error": "invalid_grant"}
        
        # Generate tokens
        user_id = self._get_user_from_code(code)  # Implementation needed
        
        access_token_payload = {
            "iss": self.issuer,
            "sub": user_id,
            "aud": "qilbee-os",
            "iat": datetime.utcnow(),
            "exp": datetime.utcnow() + timedelta(hours=1),
            "scope": "user:read user:write",
            "token_type": "access_token",
            "client_id": client_id
        }
        
        refresh_token_payload = {
            "iss": self.issuer,
            "sub": user_id,
            "aud": "qilbee-os",
            "iat": datetime.utcnow(),
            "exp": datetime.utcnow() + timedelta(days=30),
            "token_type": "refresh_token",
            "client_id": client_id
        }
        
        access_token = jwt.encode(access_token_payload, self.private_key, algorithm="RS256")
        refresh_token = jwt.encode(refresh_token_payload, self.private_key, algorithm="RS256")
        
        self.active_tokens.add(access_token)
        self.active_tokens.add(refresh_token)
        
        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "Bearer",
            "expires_in": 3600,
            "scope": access_token_payload["scope"]
        }
    
    def _validate_client(self, client_id: str, client_secret: str, grant_type: str) -> bool:
        """Validate client credentials and grant type support."""
        client = self.clients.get(client_id)
        if not client:
            return False
        
        if client["client_secret"] != client_secret:
            return False
        
        if grant_type not in client["grant_types"]:
            return False
        
        return True
    
    def validate_token(self, token: str) -> Optional[Dict[str, Any]]:
        """Validate and decode JWT token."""
        try:
            if token not in self.active_tokens:
                return None
            
            # Decode and validate JWT
            payload = jwt.decode(
                token, 
                self.private_key, 
                algorithms=["RS256"],
                audience="qilbee-os",
                issuer=self.issuer
            )
            
            return payload
            
        except jwt.InvalidTokenError:
            return None
    
    def revoke_token(self, token: str) -> bool:
        """Revoke a token (add to blacklist)."""
        if token in self.active_tokens:
            self.active_tokens.remove(token)
            return True
        return False

class PKCEHelper:
    """Helper class for PKCE (Proof Key for Code Exchange) implementation."""
    
    @staticmethod
    def generate_code_verifier() -> str:
        """Generate a cryptographically random code verifier."""
        return base64.urlsafe_b64encode(secrets.token_bytes(32)).decode('utf-8').rstrip('=')
    
    @staticmethod
    def generate_code_challenge(code_verifier: str) -> str:
        """Generate code challenge from verifier using SHA256."""
        digest = hashlib.sha256(code_verifier.encode('utf-8')).digest()
        return base64.urlsafe_b64encode(digest).decode('utf-8').rstrip('=')
    
    @staticmethod
    def verify_code_challenge(code_verifier: str, code_challenge: str) -> bool:
        """Verify that code verifier matches the challenge."""
        expected_challenge = PKCEHelper.generate_code_challenge(code_verifier)
        return secrets.compare_digest(expected_challenge, code_challenge)
```

### JWT Token Structure

```json
{
  "header": {
    "alg": "RS256",
    "typ": "JWT"
  },
  "payload": {
    "iss": "https://auth.qilbee-os.local",
    "sub": "qilbee_agent_001",
    "aud": "qilbee-os",
    "iat": 1691280000,
    "exp": 1691283600,
    "scope": "agent:execute task:create",
    "token_type": "access_token",
    "client_id": "qilbee_agent_001"
  }
}
```

## 6.2. Transport Layer Security: Mandatory TLS 1.3 for All Endpoints

All data in transit must be encrypted without exception. Every network-accessible API endpoint within the Qilbee OS ecosystem, including the external ACP REST interface and all internal gRPC services, MUST be served exclusively over HTTPS.

### TLS Configuration Requirements

The system will enforce the use of Transport Layer Security (TLS) version 1.3. Older versions of TLS and all versions of SSL are explicitly disallowed due to known vulnerabilities. Server configurations will be hardened to use only strong, modern cipher suites and will enforce Perfect Forward Secrecy (PFS).

### TLS Implementation

```python
import ssl
import aiohttp
from aiohttp import web
import grpc
from grpc import ssl_channel_credentials, ssl_server_credentials

class TLSConfigManager:
    def __init__(self):
        self.tls_context = self._create_secure_context()
    
    def _create_secure_context(self) -> ssl.SSLContext:
        """Create a secure TLS context with hardened settings."""
        
        # Create TLS 1.3 context
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        
        # Set minimum TLS version to 1.3
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        context.maximum_version = ssl.TLSVersion.TLSv1_3
        
        # Load certificate and private key
        context.load_cert_chain(
            certfile="/etc/qilbee/tls/server.crt",
            keyfile="/etc/qilbee/tls/server.key"
        )
        
        # Security hardening
        context.set_ciphers('TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256')
        context.check_hostname = False  # Handled by application layer
        context.verify_mode = ssl.CERT_REQUIRED
        
        # Load CA certificates for client verification
        context.load_verify_locations("/etc/qilbee/tls/ca.crt")
        
        return context
    
    def create_aiohttp_server(self, app: web.Application, host: str, port: int):
        """Create HTTPS server with secure TLS configuration."""
        return web.run_app(
            app,
            host=host,
            port=port,
            ssl_context=self.tls_context
        )
    
    def create_grpc_server_credentials(self):
        """Create gRPC server credentials with mutual TLS."""
        
        # Read certificate files
        with open("/etc/qilbee/tls/server.key", "rb") as f:
            private_key = f.read()
        
        with open("/etc/qilbee/tls/server.crt", "rb") as f:
            certificate_chain = f.read()
        
        with open("/etc/qilbee/tls/ca.crt", "rb") as f:
            root_certificates = f.read()
        
        # Create mutual TLS credentials
        return ssl_server_credentials(
            private_key_certificate_chain_pairs=[(private_key, certificate_chain)],
            root_certificates=root_certificates,
            require_client_auth=True
        )
    
    def create_grpc_client_credentials(self):
        """Create gRPC client credentials for mutual TLS."""
        
        with open("/etc/qilbee/tls/client.key", "rb") as f:
            private_key = f.read()
        
        with open("/etc/qilbee/tls/client.crt", "rb") as f:
            certificate_chain = f.read()
        
        with open("/etc/qilbee/tls/ca.crt", "rb") as f:
            root_certificates = f.read()
        
        return ssl_channel_credentials(
            root_certificates=root_certificates,
            private_key=private_key,
            certificate_chain=certificate_chain
        )

# Example usage
async def create_secure_rest_api():
    """Create secure REST API server."""
    tls_manager = TLSConfigManager()
    app = web.Application()
    
    # Add routes
    app.router.add_get('/v1/health', health_check)
    app.router.add_post('/v1/tasks', create_task)
    
    # Start HTTPS server
    await tls_manager.create_aiohttp_server(app, '0.0.0.0', 8443)

async def create_secure_grpc_server():
    """Create secure gRPC server with mTLS."""
    tls_manager = TLSConfigManager()
    
    server = grpc.aio.server()
    server.add_secure_port(
        '[::]:50051',
        tls_manager.create_grpc_server_credentials()
    )
    
    await server.start()
    await server.wait_for_termination()
```

### Perfect Forward Secrecy (PFS)

PFS ensures that even if a server's long-term private key is compromised, past session keys cannot be derived, thus protecting the confidentiality of previously recorded traffic. For deployments in high-security environments, the use of Certificate Pinning is recommended to protect against sophisticated man-in-the-middle (MITM) attacks by ensuring that clients will only connect to servers presenting a specific, expected certificate.

## 6.3. Securing the Message Bus: TLS Configuration for RabbitMQ

The message broker is a critical piece of infrastructure and must be secured to the same high standard as all other components. All connections from Celery workers and clients to the RabbitMQ broker MUST use the secure AMQPS protocol (AMQP over TLS).

### RabbitMQ TLS Configuration

```python
import pika
import ssl
from celery import Celery

class SecureMessageBroker:
    def __init__(self):
        self.connection_params = self._create_secure_connection_params()
    
    def _create_secure_connection_params(self):
        """Create secure RabbitMQ connection parameters."""
        
        # SSL context for client authentication
        ssl_context = ssl.create_default_context(cafile="/etc/qilbee/tls/ca.crt")
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_REQUIRED
        
        # Load client certificate for mutual TLS
        ssl_context.load_cert_chain(
            "/etc/qilbee/tls/client.crt",
            "/etc/qilbee/tls/client.key"
        )
        
        return pika.ConnectionParameters(
            host='rabbitmq.qilbee-os.local',
            port=5671,  # AMQPS port
            virtual_host='/qilbee',
            credentials=pika.PlainCredentials(
                username='qilbee_client',
                password='secure_password'  # From Kubernetes secret
            ),
            ssl_options=pika.SSLOptions(
                context=ssl_context,
                server_side=False
            ),
            heartbeat=600,
            blocked_connection_timeout=300
        )
    
    def create_secure_connection(self):
        """Create secure connection to RabbitMQ."""
        return pika.BlockingConnection(self.connection_params)
    
    def configure_celery_broker(self) -> str:
        """Generate secure Celery broker URL."""
        return (
            f"amqps://qilbee_client:secure_password@"
            f"rabbitmq.qilbee-os.local:5671/qilbee"
            f"?ssl_cert_reqs=required"
            f"&ssl_ca_certs=/etc/qilbee/tls/ca.crt"
            f"&ssl_certfile=/etc/qilbee/tls/client.crt"
            f"&ssl_keyfile=/etc/qilbee/tls/client.key"
        )

# Celery configuration with secure broker
def create_secure_celery_app():
    """Create Celery app with secure RabbitMQ connection."""
    
    broker_manager = SecureMessageBroker()
    
    app = Celery('qilbee_os')
    app.conf.update(
        broker_url=broker_manager.configure_celery_broker(),
        result_backend='redis+ssl://redis:6380/0',
        
        # SSL configuration for Redis result backend
        redis_backend_use_ssl={
            'ssl_cert_reqs': ssl.CERT_REQUIRED,
            'ssl_ca_certs': '/etc/qilbee/tls/ca.crt',
            'ssl_certfile': '/etc/qilbee/tls/client.crt',
            'ssl_keyfile': '/etc/qilbee/tls/client.key',
        },
        
        # Security settings
        task_serializer='json',
        accept_content=['json'],
        result_serializer='json',
        task_always_eager=False,
        task_acks_late=True,
        worker_prefetch_multiplier=1
    )
    
    return app
```

### RabbitMQ Server Configuration

```bash
# /etc/rabbitmq/rabbitmq.conf
listeners.ssl.default = 5671

ssl_options.cacertfile = /etc/qilbee/tls/ca.crt
ssl_options.certfile   = /etc/qilbee/tls/server.crt
ssl_options.keyfile    = /etc/qilbee/tls/server.key

ssl_options.verify     = verify_peer
ssl_options.fail_if_no_peer_cert = true

# TLS 1.3 only
ssl_options.versions.1 = tlsv1.3

# Strong cipher suites
ssl_options.ciphers.1 = TLS_AES_256_GCM_SHA384
ssl_options.ciphers.2 = TLS_CHACHA20_POLY1305_SHA256
ssl_options.ciphers.3 = TLS_AES_128_GCM_SHA256

# Disable insecure plain AMQP
listeners.tcp = none

# Management plugin over HTTPS only
management.ssl.port       = 15671
management.ssl.cacertfile = /etc/qilbee/tls/ca.crt
management.ssl.certfile   = /etc/qilbee/tls/server.crt
management.ssl.keyfile    = /etc/qilbee/tls/server.key
```

## 6.4. Role-Based Access Control (RBAC) for System Administration and Tool Usage

An integral part of the Qilbee OS security model is a granular Role-Based Access Control (RBAC) system. This system will govern authorization for all significant actions within the OS, from high-level administrative functions to the execution of individual tools.

### RBAC Implementation

```python
from typing import Dict, List, Set, Optional
from dataclasses import dataclass
from enum import Enum
import json

class Permission(Enum):
    # System administration
    SYSTEM_ADMIN = "system.admin"
    SYSTEM_CONFIG = "system.config"
    SYSTEM_MONITOR = "system.monitor"
    
    # Agent management
    AGENT_CREATE = "agent.create"
    AGENT_DELETE = "agent.delete"
    AGENT_MODIFY = "agent.modify"
    AGENT_VIEW = "agent.view"
    
    # Task management
    TASK_CREATE = "task.create"
    TASK_EXECUTE = "task.execute"
    TASK_CANCEL = "task.cancel"
    TASK_VIEW = "task.view"
    
    # Tool capabilities
    TOOL_NETWORK_ACCESS = "tool.capability.network.access"
    TOOL_FILESYSTEM_READ = "tool.capability.filesystem.read"
    TOOL_FILESYSTEM_WRITE = "tool.capability.filesystem.write"
    TOOL_SYSTEM_COMMAND = "tool.capability.system.command"
    
    # GUI automation
    GUI_SCREENSHOT = "gui.screenshot.capture"
    GUI_MOUSE_CLICK = "gui.mouse.click"
    GUI_KEYBOARD_TYPE = "gui.keyboard.type"
    GUI_WINDOW_CONTROL = "gui.window.control"

@dataclass
class Role:
    name: str
    description: str
    permissions: Set[Permission]
    created_at: str
    is_system_role: bool = False

@dataclass
class User:
    user_id: str
    username: str
    email: str
    roles: Set[str]
    is_active: bool = True
    created_at: str

class RBACSystem:
    def __init__(self):
        self.roles: Dict[str, Role] = {}
        self.users: Dict[str, User] = {}
        self._initialize_system_roles()
    
    def _initialize_system_roles(self):
        """Initialize default system roles."""
        
        # System Administrator - full access
        self.roles["SystemAdmin"] = Role(
            name="SystemAdmin",
            description="Full administrative privileges over the Qilbee deployment",
            permissions={
                Permission.SYSTEM_ADMIN,
                Permission.SYSTEM_CONFIG,
                Permission.SYSTEM_MONITOR,
                Permission.AGENT_CREATE,
                Permission.AGENT_DELETE,
                Permission.AGENT_MODIFY,
                Permission.AGENT_VIEW,
                Permission.TASK_CREATE,
                Permission.TASK_EXECUTE,
                Permission.TASK_CANCEL,
                Permission.TASK_VIEW,
                Permission.TOOL_NETWORK_ACCESS,
                Permission.TOOL_FILESYSTEM_READ,
                Permission.TOOL_FILESYSTEM_WRITE,
                Permission.TOOL_SYSTEM_COMMAND,
                Permission.GUI_SCREENSHOT,
                Permission.GUI_MOUSE_CLICK,
                Permission.GUI_KEYBOARD_TYPE,
                Permission.GUI_WINDOW_CONTROL
            },
            created_at="2024-08-06T00:00:00Z",
            is_system_role=True
        )
        
        # Tool Developer - can manage tools and plugins
        self.roles["ToolDeveloper"] = Role(
            name="ToolDeveloper",
            description="Permissions to register and manage tool plugins",
            permissions={
                Permission.AGENT_VIEW,
                Permission.TASK_CREATE,
                Permission.TASK_EXECUTE,
                Permission.TASK_VIEW,
                Permission.TOOL_FILESYSTEM_READ,
                Permission.SYSTEM_MONITOR
            },
            created_at="2024-08-06T00:00:00Z",
            is_system_role=True
        )
        
        # End User - basic interaction capabilities
        self.roles["EndUser"] = Role(
            name="EndUser",
            description="Basic permissions to interact with the conversational agent",
            permissions={
                Permission.TASK_CREATE,
                Permission.TASK_VIEW,
                Permission.AGENT_VIEW
            },
            created_at="2024-08-06T00:00:00Z",
            is_system_role=True
        )
        
        # GUI Operator - can perform GUI automation
        self.roles["GUIOperator"] = Role(
            name="GUIOperator",
            description="Permissions for GUI automation and desktop interaction",
            permissions={
                Permission.TASK_CREATE,
                Permission.TASK_EXECUTE,
                Permission.TASK_VIEW,
                Permission.GUI_SCREENSHOT,
                Permission.GUI_MOUSE_CLICK,
                Permission.GUI_KEYBOARD_TYPE,
                Permission.GUI_WINDOW_CONTROL
            },
            created_at="2024-08-06T00:00:00Z",
            is_system_role=True
        )
    
    def create_role(self, name: str, description: str, permissions: Set[Permission]) -> bool:
        """Create a new custom role."""
        if name in self.roles:
            return False
        
        self.roles[name] = Role(
            name=name,
            description=description,
            permissions=permissions,
            created_at=datetime.utcnow().isoformat(),
            is_system_role=False
        )
        return True
    
    def create_user(self, user_id: str, username: str, email: str, roles: Set[str]) -> bool:
        """Create a new user with assigned roles."""
        if user_id in self.users:
            return False
        
        # Validate that all roles exist
        for role_name in roles:
            if role_name not in self.roles:
                raise ValueError(f"Role '{role_name}' does not exist")
        
        self.users[user_id] = User(
            user_id=user_id,
            username=username,
            email=email,
            roles=roles,
            created_at=datetime.utcnow().isoformat()
        )
        return True
    
    def assign_role_to_user(self, user_id: str, role_name: str) -> bool:
        """Assign a role to an existing user."""
        if user_id not in self.users or role_name not in self.roles:
            return False
        
        self.users[user_id].roles.add(role_name)
        return True
    
    def remove_role_from_user(self, user_id: str, role_name: str) -> bool:
        """Remove a role from a user."""
        if user_id not in self.users:
            return False
        
        self.users[user_id].roles.discard(role_name)
        return True
    
    def user_has_permission(self, user_id: str, permission: Permission) -> bool:
        """Check if a user has a specific permission."""
        user = self.users.get(user_id)
        if not user or not user.is_active:
            return False
        
        # Check all user's roles for the permission
        for role_name in user.roles:
            role = self.roles.get(role_name)
            if role and permission in role.permissions:
                return True
        
        return False
    
    def get_user_permissions(self, user_id: str) -> Set[Permission]:
        """Get all permissions for a user."""
        user = self.users.get(user_id)
        if not user or not user.is_active:
            return set()
        
        permissions = set()
        for role_name in user.roles:
            role = self.roles.get(role_name)
            if role:
                permissions.update(role.permissions)
        
        return permissions
    
    def check_tool_capability_permissions(self, user_id: str, tool_manifest: Dict) -> bool:
        """Check if user has permissions for tool's declared capabilities."""
        
        required_capabilities = tool_manifest.get("required_capabilities", [])
        
        capability_permission_map = {
            "network_access": Permission.TOOL_NETWORK_ACCESS,
            "filesystem_read": Permission.TOOL_FILESYSTEM_READ,
            "filesystem_write": Permission.TOOL_FILESYSTEM_WRITE,
            "system_command": Permission.TOOL_SYSTEM_COMMAND
        }
        
        for capability in required_capabilities:
            required_permission = capability_permission_map.get(capability)
            if required_permission and not self.user_has_permission(user_id, required_permission):
                return False
        
        return True
    
    def audit_user_action(self, user_id: str, action: str, resource: str, success: bool):
        """Log user action for security audit."""
        import logging
        
        audit_logger = logging.getLogger('qilbee.rbac.audit')
        audit_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "user_id": user_id,
            "action": action,
            "resource": resource,
            "success": success,
            "user_permissions": [p.value for p in self.get_user_permissions(user_id)]
        }
        
        audit_logger.info(f"RBAC_AUDIT: {json.dumps(audit_entry)}")

# Example usage
def example_rbac_usage():
    """Example of how to use the RBAC system."""
    
    rbac = RBACSystem()
    
    # Create users
    rbac.create_user(
        user_id="alice_123",
        username="alice",
        email="alice@company.com",
        roles={"SystemAdmin"}
    )
    
    rbac.create_user(
        user_id="bob_456", 
        username="bob",
        email="bob@company.com",
        roles={"EndUser", "GUIOperator"}
    )
    
    # Check permissions
    can_alice_admin = rbac.user_has_permission("alice_123", Permission.SYSTEM_ADMIN)  # True
    can_bob_admin = rbac.user_has_permission("bob_456", Permission.SYSTEM_ADMIN)      # False
    can_bob_screenshot = rbac.user_has_permission("bob_456", Permission.GUI_SCREENSHOT)  # True
    
    # Check tool capabilities
    tool_manifest = {
        "name": "network_scanner",
        "required_capabilities": ["network_access", "filesystem_write"]
    }
    
    alice_can_use_tool = rbac.check_tool_capability_permissions("alice_123", tool_manifest)  # True
    bob_can_use_tool = rbac.check_tool_capability_permissions("bob_456", tool_manifest)      # False
```

### RBAC Integration with Tool Execution

The RBAC system integrates directly with the tool execution pipeline to ensure that only authorized users can execute tools with elevated capabilities:

```python
class SecureToolExecutor:
    def __init__(self, rbac_system: RBACSystem, sandbox_manager: SecureSandboxManager):
        self.rbac = rbac_system
        self.sandbox = sandbox_manager
    
    async def execute_tool(self, user_id: str, tool_name: str, tool_args: Dict) -> Dict[str, Any]:
        """Execute tool with RBAC permission checks."""
        
        # Load tool manifest
        tool_manifest = self._load_tool_manifest(tool_name)
        if not tool_manifest:
            return {"error": f"Tool '{tool_name}' not found"}
        
        # Check RBAC permissions
        if not self.rbac.check_tool_capability_permissions(user_id, tool_manifest):
            self.rbac.audit_user_action(user_id, "tool_execute", tool_name, False)
            return {"error": "Insufficient permissions for tool capabilities"}
        
        # Execute with appropriate sandbox profile
        sandbox_profile = self._determine_sandbox_profile(tool_manifest)
        
        try:
            result = await self.sandbox.execute_tool_sandboxed(
                tool_code=self._load_tool_code(tool_name),
                tool_args=tool_args,
                sandbox_profile=sandbox_profile
            )
            
            self.rbac.audit_user_action(user_id, "tool_execute", tool_name, True)
            return result
            
        except Exception as e:
            self.rbac.audit_user_action(user_id, "tool_execute", tool_name, False)
            return {"error": f"Tool execution failed: {str(e)}"}
```

This comprehensive RBAC system ensures that potentially dangerous operations can only be triggered by trusted principals, providing a crucial administrative control layer over the sandbox's security policy and all system operations.