# Qilbee OS - Conversational Operating System

Qilbee OS is a sophisticated multi-agent conversational operating system designed for enterprise-grade cloud-native deployment. This project implements a distributed, agent-oriented architecture that enables autonomous task execution and collaborative workflows.

## Architecture Overview

Qilbee OS is built on a multi-agent system (MAS) paradigm where each instance functions as a complete, self-sufficient agent capable of both independent operation and complex collaborative task execution.

### Core Components

1. **Agent Orchestrator** - The cognitive core managing natural language interpretation and task coordination
2. **Distributed Task Scheduler** - Handles reliable task execution across distributed environments
3. **Python Tool Execution Engine** - Secure, sandboxed execution of tools and plugins

## Project Structure

```
qilbee-os/
├── docs/                           # Technical documentation
│   ├── section-1-architecture.md   # System Architecture and Core Principles
│   ├── section-2-task-queuing.md   # Distributed Task Queuing
│   ├── section-3-iac-protocol.md   # Inter-Agent Communication Protocol
│   ├── section-4-conversational.md # Conversational Core and Tool Engine
│   ├── section-5-security.md       # Secure Execution Sandbox
│   ├── section-6-security-model.md # System-Wide Security Model
│   ├── section-7-ui.md            # Terminal User Interface
│   └── section-8-deployment.md     # Containerization and Deployment
├── src/                            # Source code
│   ├── agent_orchestrator/         # Agent Orchestrator implementation
│   ├── task_scheduler/             # Distributed Task Scheduler
│   ├── execution_engine/           # Python Tool Execution Engine
│   ├── security/                   # Security and sandboxing
│   ├── ui/                        # Terminal User Interface
│   └── common/                     # Shared utilities and schemas
├── config/                         # Configuration files
├── deployment/                     # Kubernetes and Docker configurations
├── tools/                         # Built-in tools and plugins
└── tests/                         # Test suites
```

## Technology Stack

- **Base OS**: Ubuntu 24.04 LTS
- **Language**: Python 3.11+
- **Task Queue**: Celery with RabbitMQ
- **Communication**: gRPC (internal), REST/ACP (external)
- **UI Framework**: Textual + Rich
- **LLM Integration**: Anthropic Claude Sonnet 4
- **Containerization**: Docker + Kubernetes
- **Security**: OAuth 2.0, TLS 1.3, nsjail sandboxing

## Quick Start

### Prerequisites

- Ubuntu 24.04 LTS
- Python 3.11+
- Docker and Kubernetes
- RabbitMQ and Redis

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd qilbee-os

# Install dependencies
pip install -r requirements.txt

# Configure the system
cp config/default.yaml config/local.yaml
# Edit config/local.yaml with your settings

# Start the system
python -m qilbee_os.main
```

## Key Features

- **Multi-Agent Architecture**: Decentralized coordination with swarm capabilities
- **Conversational Interface**: Natural language processing with Claude Sonnet 4
- **Secure Sandboxing**: nsjail-based isolation for tool execution
- **Cloud-Native**: Kubernetes-ready with auto-scaling support
- **Enterprise Security**: OAuth 2.0, TLS 1.3, RBAC
- **Extensible Tools**: Plugin architecture with dynamic discovery
- **Real-time UI**: Async Terminal User Interface

## Documentation

Detailed technical specifications are available in the `docs/` directory:

- **[Section 1: System Architecture](docs/section-1-architecture.md)** - Core principles, component overview, and technology stack
- **[Section 2: Task Queuing System](docs/section-2-task-queuing.md)** - Celery/RabbitMQ distributed processing and swarm mode
- **[Section 3: Inter-Agent Communication](docs/section-3-iac-protocol.md)** - gRPC/REST hybrid protocol and ACP compliance
- **[Section 4: Conversational Core](docs/section-4-conversational.md)** - Claude Sonnet 4 integration and tool plugin architecture
- **[Section 5: Security Sandbox](docs/section-5-security.md)** - nsjail process isolation and GUI automation security
- **[Section 6: Security Model](docs/section-6-security-model.md)** - OAuth 2.0, TLS 1.3, and comprehensive RBAC system
- **[Section 7: User Interface](docs/section-7-ui.md)** - Textual-based TUI with real-time monitoring
- **[Section 8: Deployment](docs/section-8-deployment.md)** - Docker containerization and Kubernetes orchestration

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Qilbee OS Architecture                   │
├─────────────────────────────────────────────────────────────────┤
│  Terminal UI (Textual)          Web Interface (noVNC)           │
├─────────────────────────────────────────────────────────────────┤
│                    Agent Orchestrator                           │
│                       (LLM LAYER)                               │
├─────────┬─────────────────────────────────┬─────────────────────┤
│ Task    │     Tool Execution Engine       │  Inter-Agent        │
│Scheduler│     (nsjail Sandbox)            │  Communication      │
│(Celery) │                                 │  (gRPC/REST)        │
├─────────┼─────────────────────────────────┼─────────────────────┤
│         │        Security Layer           │                     │
│         │  (OAuth 2.0, TLS 1.3, RBAC)     │                     │
├─────────┴─────────────────────────────────┴─────────────────────┤
│    Message Broker (RabbitMQ)    Result Backend (Redis)          │
└─────────────────────────────────────────────────────────────────┘
```

## Contributing

Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support and questions, please contact the development team or create an issue in the project repository.
