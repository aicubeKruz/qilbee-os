# Section 3: Inter-Agent Communication (IAC) Protocol

This section defines the suite of protocols that enable individual Qilbee Instances to communicate with each other and with external, third-party agents. The design of the Inter-Agent Communication (IAC) protocol is critical for enabling the collaborative, multi-agent workflows that are central to the Qilbee OS vision.

## 3.1. Protocol Design Philosophy: A Hybrid Approach for Performance and Interoperability

A single, one-size-fits-all communication protocol is insufficient to meet the diverse needs of an enterprise-grade distributed system. The communication requirements between tightly coupled internal services are fundamentally different from the requirements for communication with external, loosely coupled third-party systems. The former demands maximum performance, low latency, and a strongly typed interface, while the latter prioritizes standardization, ease of adoption, and interoperability.

Attempting to apply a single protocol to both use cases results in an unacceptable compromise. Using a high-performance binary protocol like gRPC for external communication would create a high barrier to entry, requiring third parties to generate specific client stubs and tightly coupling them to the system's internal definitions. Conversely, using a flexible, text-based protocol like REST for all internal communication would needlessly sacrifice performance and introduce overhead where it is not required.

Therefore, Qilbee OS will adopt a hybrid, two-tiered communication architecture. This approach strategically applies the best tool for each specific job. For all internal communication between the core components of a Qilbee Instance, the system will use gRPC. For all external communication with other Qilbee Instances or third-party agents, the system will expose a standardized, REST-based API compliant with the Agent Communication Protocol (ACP). This dual-protocol strategy ensures that the system is both highly performant internally and maximally open and interoperable externally.

## 3.2. Transport Layer: gRPC for High-Performance Internal Service Communication

All internal, service-to-service communication within a single Qilbee Instance (e.g., between the Agent Orchestrator and the Distributed Task Scheduler) will be implemented using gRPC.

The rationale for this choice is gRPC's superior performance characteristics in a microservices context. gRPC is built on HTTP/2, which enables advanced features like multiplexing and bidirectional streaming over a single TCP connection. It uses Protocol Buffers (Protobuf) as its interface definition language and serialization format. Protobuf is a binary format that is significantly more compact and faster to parse than text-based formats like JSON, resulting in lower network bandwidth usage and reduced CPU overhead for serialization and deserialization. This makes gRPC the ideal choice for the frequent, high-throughput communication expected between the core components of the OS.

### gRPC Service Definition Example

```protobuf
// qilbee_internal.proto
syntax = "proto3";

package qilbee.internal;

service TaskScheduler {
  rpc ScheduleTask(TaskRequest) returns (TaskResponse);
  rpc GetTaskStatus(TaskStatusRequest) returns (TaskStatusResponse);
  rpc CancelTask(CancelTaskRequest) returns (CancelTaskResponse);
}

message TaskRequest {
  string task_id = 1;
  string task_type = 2;
  map<string, string> parameters = 3;
  int32 priority = 4;
}

message TaskResponse {
  string task_id = 1;
  TaskStatus status = 2;
  string message = 3;
}

enum TaskStatus {
  PENDING = 0;
  RUNNING = 1;
  SUCCESS = 2;
  FAILURE = 3;
  REVOKED = 4;
}
```

The design is inherently service-oriented, allowing the Orchestrator to invoke specific, strongly-typed functions on the Scheduler (e.g., `ScheduleTask(task_object)`) as if it were a local method call, which simplifies development and reduces the likelihood of integration errors.

## 3.3. Semantic Layer: Adopting the Agent Communication Protocol (ACP) for Standardized Collaboration

For all external communication, the Agent Orchestrator component of each Qilbee Instance will expose a set of RESTful API endpoints that are fully compliant with the Agent Communication Protocol (ACP) specification.

The adoption of ACP is a strategic decision to foster an open and collaborative ecosystem around Qilbee OS. ACP is a modern, lightweight, and vendor-neutral standard designed specifically for agent interoperability. Its foundation on standard RESTful principles and HTTP conventions makes it exceptionally easy for third-party developers to integrate with. Unlike more complex protocols that require specialized SDKs or runtimes, an ACP-compliant agent can be interacted with using standard tools like `curl` or any basic HTTP client library. This low barrier to entry is critical for encouraging adoption and building a diverse ecosystem of compatible agents.

This choice represents a deliberate move away from older, semantically rigid, and complex standards like FIPA-ACL, which, while powerful, have historically struggled with widespread adoption due to their complexity. By embracing a simple, pragmatic, and open standard, Qilbee OS positions itself as a cooperative participant in the emerging landscape of multi-agent systems.

### ACP Endpoint Examples

```http
# Agent capabilities discovery
GET /v1/agent/capabilities
Accept: application/json

# Task submission
POST /v1/tasks
Content-Type: application/json
{
  "input": "Analyze the quarterly sales data",
  "additional_input": {
    "data_source": "sales_db",
    "quarters": ["Q1", "Q2", "Q3", "Q4"]
  }
}

# Task status check
GET /v1/tasks/{task_id}
Accept: application/json

# Task results retrieval
GET /v1/tasks/{task_id}/artifacts
Accept: application/json
```

## 3.4. IAC Message Schemas and Core Payloads

To ensure consistency across both the internal gRPC and external ACP communication layers, the system will standardize on a common set of core data objects. These schemas are based on the foundational concepts defined in the Agent Protocol specification, a well-regarded open standard in the agent community and a precursor to some of the concepts in ACP.

### Primary Data Objects

The primary data objects are:

#### Task Object
The highest-level object representing a complete unit of work assigned to an agent. It contains a unique ID, the initial input, and collections of its constituent steps and resulting artifacts.

```json
{
  "task_id": "task_12345",
  "input": "Generate a quarterly report",
  "additional_input": {
    "quarter": "Q4",
    "year": 2024,
    "format": "pdf"
  },
  "status": "running",
  "created_at": "2024-08-06T02:30:00Z",
  "updated_at": "2024-08-06T02:35:00Z",
  "steps": ["step_001", "step_002"],
  "artifacts": ["report_draft.pdf"]
}
```

#### Step Object
A discrete action or stage within a task. A task is typically composed of one or more steps. Each step has its own ID, input, output, status, and can produce artifacts.

```json
{
  "step_id": "step_001",
  "task_id": "task_12345",
  "name": "data_collection",
  "input": {
    "query": "SELECT * FROM sales WHERE quarter = 'Q4'",
    "database": "sales_db"
  },
  "output": {
    "records_count": 15420,
    "status": "completed"
  },
  "status": "completed",
  "artifacts": ["raw_data.csv"],
  "is_last": false
}
```

#### Artifact Object
A persistent data object, typically a file, created by or provided to an agent during the execution of a task or step. Each artifact has a unique ID, a filename, and a relative path within the agent's workspace.

```json
{
  "artifact_id": "artifact_001",
  "task_id": "task_12345",
  "step_id": "step_001",
  "created_at": "2024-08-06T02:32:00Z",
  "modified_at": "2024-08-06T02:32:00Z",
  "file_name": "quarterly_report.pdf",
  "relative_path": "outputs/reports/quarterly_report.pdf",
  "file_size": 2048576,
  "mime_type": "application/pdf"
}
```

These objects will be defined once using Protocol Buffers (.proto files). These definitions will be used to automatically generate the necessary Python classes for the internal gRPC services. For the external ACP/REST interface, these Protobuf definitions will be mapped to corresponding JSON schemas to ensure the structure of the JSON payloads is consistent with the internal data models.

## 3.5. Interaction Patterns: Request-Reply, Publish-Subscribe, and Long-Running Task Handshakes

The IAC protocol will support several fundamental interaction patterns to accommodate a variety of use cases:

### 3.5.1. Synchronous Request-Reply

This pattern is used for simple, quick interactions where the client blocks and waits for an immediate response. It is suitable for status queries or actions that can be completed in a very short amount of time. This mode is supported by both gRPC (as a standard unary RPC) and ACP's synchronous communication option.

```python
# gRPC synchronous call example
response = task_scheduler_stub.GetTaskStatus(
    TaskStatusRequest(task_id="task_12345")
)
print(f"Task status: {response.status}")
```

```http
# ACP synchronous request example
GET /v1/tasks/task_12345
Accept: application/json

# Immediate response
HTTP/1.1 200 OK
Content-Type: application/json
{
  "task_id": "task_12345",
  "status": "running",
  "progress": 45
}
```

### 3.5.2. Asynchronous Task Submission

This is the primary and default interaction pattern for all non-trivial tasks. The client submits a task to an agent via a POST request and immediately receives a response containing a unique `task_id`. The connection is then closed. The client can use this `task_id` to later poll a status endpoint to check on the task's progress or retrieve its final result. This decoupled, asynchronous approach is the default mode for ACP and is essential for handling long-running tasks without forcing clients to maintain persistent connections.

```http
# Submit task
POST /v1/tasks
Content-Type: application/json
{
  "input": "Process financial data for Q4 analysis"
}

# Immediate response with task ID
HTTP/1.1 201 Created
Content-Type: application/json
{
  "task_id": "task_67890",
  "status": "pending"
}

# Later status check
GET /v1/tasks/task_67890
Accept: application/json

# Response with current status
HTTP/1.1 200 OK
Content-Type: application/json
{
  "task_id": "task_67890",
  "status": "completed",
  "artifacts": ["analysis_report.pdf"]
}
```

### 3.5.3. Event Streaming (Publish-Subscribe)

To facilitate system-wide situational awareness and reactive behavior, Qilbee Instances will use the publish-subscribe capabilities of the RabbitMQ message broker. Each instance will publish significant lifecycle and state-change events (e.g., `agent.online`, `agent.offline`, `task.completed`, `task.failed`) to a dedicated fanout exchange. Other Qilbee Instances can create queues bound to this exchange to subscribe to this stream of events. This allows agents to react dynamically to changes in the overall system state, such as an important task completing or a new agent with a required capability joining the network.

#### Event Schema Example

```json
{
  "event_type": "task.completed",
  "timestamp": "2024-08-06T02:45:00Z",
  "source_agent_id": "qilbee_instance_001",
  "task_id": "task_12345",
  "metadata": {
    "execution_time_seconds": 120,
    "artifacts_generated": 3,
    "success": true
  }
}
```

#### RabbitMQ Exchange Configuration

```python
# Event publishing setup
import pika

connection = pika.BlockingConnection(
    pika.ConnectionParameters('rabbitmq')
)
channel = connection.channel()

# Declare fanout exchange for system events
channel.exchange_declare(
    exchange='qilbee.events',
    exchange_type='fanout',
    durable=True
)

# Publish an event
event = {
    "event_type": "agent.online",
    "timestamp": "2024-08-06T02:45:00Z",
    "source_agent_id": "qilbee_instance_002",
    "metadata": {
        "capabilities": ["data_analysis", "report_generation"],
        "load_factor": 0.2
    }
}

channel.basic_publish(
    exchange='qilbee.events',
    routing_key='',
    body=json.dumps(event),
    properties=pika.BasicProperties(
        delivery_mode=2,  # Make message persistent
        timestamp=int(time.time())
    )
)
```

## 3.6. Authentication and Security in IAC

All IAC communications, both internal gRPC and external ACP, will be secured according to the security model defined in Section 6. Key security considerations include:

### 3.6.1. Internal gRPC Security

- **Mutual TLS (mTLS)**: All gRPC connections use client and server certificates
- **Service Authentication**: Each service authenticates using OAuth 2.0 client credentials
- **Encryption**: All data in transit encrypted with TLS 1.3

### 3.6.2. External ACP Security

- **HTTPS Only**: All ACP endpoints served exclusively over HTTPS
- **Bearer Token Authentication**: OAuth 2.0 access tokens required for all requests
- **Rate Limiting**: Protection against DoS attacks and resource exhaustion

### Security Configuration Example

```python
# gRPC server with TLS
import grpc
from grpc import ssl_channel_credentials

credentials = ssl_channel_credentials(
    root_certificates=None,  # Use system root certificates
    private_key=private_key_bytes,
    certificate_chain=certificate_chain_bytes
)

channel = grpc.secure_channel('scheduler:50051', credentials)
```

This comprehensive IAC protocol design ensures that Qilbee OS can operate effectively both as a standalone system and as part of a larger multi-agent ecosystem, maintaining high performance for internal operations while providing maximum interoperability for external collaboration.