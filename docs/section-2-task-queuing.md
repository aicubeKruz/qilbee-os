# Section 2: Distributed Task Queuing and Scheduling Service

This section provides a detailed technical specification for the asynchronous task processing subsystem of Qilbee OS. This service is a cornerstone of the system's architecture, enabling its distributed nature, scalability, and the advanced functionality of 'Swarm' mode. The design prioritizes reliability and fault tolerance, as is required for an enterprise-grade platform.

## 2.1. Framework Selection: Celery as the Core Asynchronous Execution Framework

Qilbee OS will standardize on the Celery framework for all distributed task queue operations. Celery will be integrated as a core dependency and will underpin the functionality of the Distributed Task Scheduler component.

The selection of Celery is based on its position as the de facto standard for asynchronous task processing in the Python ecosystem. It is a mature, feature-rich, and highly reliable distributed system designed specifically for processing vast volumes of messages. Its adoption provides Qilbee OS with a powerful, production-proven foundation, obviating the need to develop a custom task queuing solution. Key features of Celery that are critical to the Qilbee OS vision include its flexible task scheduling capabilities via the celery beat daemon, its support for designing complex, multi-step workflows using the Canvas primitives (such as chains and chords), and its extensive built-in monitoring and management tools. The large and active community ensures long-term maintenance and a wealth of available documentation and support.

## 2.2. Message Broker Architecture: RabbitMQ for Enterprise-Grade Reliability

The exclusive message broker for Qilbee OS shall be RabbitMQ. All task messages will be transmitted and queued via a RabbitMQ instance, which serves as the central communication bus between task producers (Qilbee Schedulers) and consumers (Celery workers).

This decision is driven by the core requirement for an "enterprise-grade" system, which places the highest premium on reliability, data integrity, and guaranteed task delivery. RabbitMQ is a full-featured, robust message broker that implements the Advanced Message Queuing Protocol (AMQP). It provides the strong guarantees necessary for critical workloads through several key mechanisms, including message persistence to disk, explicit message delivery confirmations (acknowledgements), and sophisticated, flexible routing strategies. These features ensure that once a task is submitted to the queue, it will not be lost, even in the event of a broker restart or a worker process crash.

### RabbitMQ vs Redis Comparison

While alternative brokers like Redis are often considered for their high speed and low latency, they are fundamentally unsuited for the primary task-queuing role in Qilbee OS. Redis, being an in-memory data store, does not offer the same level of durability or reliability as RabbitMQ. By default, it does not guarantee message delivery, and a worker crash after retrieving a task but before completing it can result in the task being permanently lost. Research and best practices clearly indicate that Redis is best suited for scenarios where occasional message loss is acceptable and raw speed is the paramount concern. This is a trade-off that is incompatible with the operational requirements of an enterprise system.

However, the distinct performance characteristics of RabbitMQ and Redis present an opportunity for a more nuanced, hybrid architecture. While RabbitMQ is non-negotiable for the message broker role due to its reliability, Redis is an excellent choice for the result backend role. The broker is responsible for the task queue itself, where loss is unacceptable. The result backend is responsible for storing the state and return value of a task, where the consequences of data loss are less severe (a task's status can be re-queried or the task can be re-run) and low-latency access is highly desirable for a responsive user interface. This architectural decision creates a tiered system that leverages the primary strength of each technology: RabbitMQ provides rock-solid reliability for task queuing, while Redis provides a high-performance, low-latency cache for task metadata and results.

### Feature Comparison Table

| Feature | RabbitMQ | Redis | Justification for Qilbee OS |
|---------|----------|-------|----------------------------|
| **Persistence** | High (Messages can be persisted to disk) | Low (In-memory by default; persistence is optional and adds overhead) | Required. Enterprise-grade systems must survive broker restarts without data loss. RabbitMQ's persistence is core to its design. |
| **Delivery Guarantee** | High (Supports acknowledgements and retries via AMQP) | Low (Pub/Sub model does not guarantee delivery; subscribers must be connected) | Required. Guarantees that tasks are processed at least once, even if workers fail. This is a non-negotiable feature for critical operations. |
| **Routing Capabilities** | Advanced (Direct, Topic, Fanout, Headers exchanges) | None (Simple Pub/Sub or List-based queues) | Highly Desirable. Enables sophisticated workflows, such as routing tasks to specific worker pools based on priority or type, and broadcasting system events. |
| **Performance** | Good (Tens of thousands of messages/sec) | Excellent (Millions of messages/sec) | Acceptable. While Redis is faster, RabbitMQ's throughput is more than sufficient for the target workload, and reliability is the primary concern. |
| **Operational Complexity** | High (Requires dedicated management and configuration) | Low (Often already present in tech stacks for caching) | Acceptable Overhead. The operational cost is justified by the significant gains in reliability and features necessary for an enterprise system. |

## 2.3. Task Definition and Serialization

Within the Qilbee OS codebase, all asynchronous tasks will be defined as standard Python functions decorated with Celery's `@app.task` decorator. This approach provides a clean, declarative syntax that is easy for developers to understand and maintain.

### Serialization Strategy

For the serialization of task messages, security and interoperability are the primary concerns. Therefore, the system-wide default serializer will be configured to `json`. This ensures that task payloads are human-readable and can be easily consumed by other systems or languages if necessary. The use of the `pickle` serializer will be explicitly and globally disabled. While powerful, pickle is known to have significant security vulnerabilities, as it can execute arbitrary code during deserialization, making it an unacceptable risk in a system that may process data from various sources.

To optimize network performance and reduce bandwidth consumption, especially in distributed or 'Swarm' mode deployments, all message bodies will be compressed using the `zlib` compression scheme before being sent to the broker.

### Example Task Definition

```python
from celery import Celery

app = Celery('qilbee_os')
app.conf.update(
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    timezone='UTC',
    enable_utc=True,
    task_compression='zlib',
    result_compression='zlib',
)

@app.task
def execute_tool(tool_name: str, tool_args: dict) -> dict:
    """Execute a tool within the secure sandbox."""
    # Implementation details in Section 4
    pass
```

## 2.4. Worker Configuration and Management

The configuration of the Celery worker processes is critical to the performance and stability of the system. The default execution pool for Qilbee OS workers will be the `prefork` pool. This model uses multiprocessing to spawn a configurable number of child processes, allowing Qilbee OS to bypass Python's Global Interpreter Lock (GIL) and achieve true parallelism on multi-core CPUs. This is particularly effective for the CPU-bound tasks that are common in data processing and AI workloads.

### Worker Pool Configuration

The number of concurrent child processes per worker will be a configurable parameter, allowing system administrators to tune performance based on the specific hardware of the host machine and the nature of the expected workload. In production environments, worker processes will be managed as containerized applications orchestrated by Kubernetes. Worker lifecycle management, including startup, health monitoring, and automatic restarts, will be handled by Kubernetes Deployments and ReplicaSets, ensuring high availability and resilience without manual intervention. The use of systemd is deprecated in favor of this cloud-native approach.

### Example Worker Configuration

```python
# celeryconfig.py
broker_url = 'amqp://guest@rabbitmq:5672//'
result_backend = 'redis://redis:6379/0'

worker_prefetch_multiplier = 1
task_acks_late = True
worker_max_tasks_per_child = 1000

# Pool configuration
worker_pool = 'prefork'
worker_concurrency = 4  # Configurable based on CPU cores

# Monitoring
worker_send_task_events = True
task_send_sent_event = True
```

## 2.5. 'Swarm' Mode Functional Specification

'Swarm' mode is a key operational capability of Qilbee OS, defined as a deployment topology where multiple, potentially geographically distributed, Qilbee Instances configure their Celery workers to consume tasks from a single, shared message queue. This queue will reside within a dedicated virtual host (vhost) on the RabbitMQ broker. In a Kubernetes environment, 'Swarm' mode is implemented by scaling the number of replicas in the Celery worker Deployment.

### Coordination Mechanisms

The coordination of work within the swarm is handled primarily by the guarantees of the AMQP protocol implemented by RabbitMQ. When a worker retrieves a message from the queue, RabbitMQ ensures it is not delivered to another worker. To handle the risk of worker failure during task execution, a critical configuration setting, `acks_late=True` (late acknowledgment), will be enabled for all tasks that are not idempotent. This setting instructs the worker to send its acknowledgment message to the broker only after the task has successfully completed. If the worker process crashes mid-execution, the acknowledgment is never sent, and RabbitMQ will re-queue the task to be picked up by another available worker in the swarm. This ensures an "at-least-once" delivery semantic, which is crucial for fault tolerance.

### Peer-to-Peer Communication

For internal coordination and state synchronization among workers in the swarm, Qilbee OS will leverage Celery's built-in peer-to-peer communication protocols. These include:

- **Mingle**: For discovering other workers at startup
- **Gossip**: For continuous state synchronization
- **Heartbeats**: For liveness checks

These protocols allow the swarm to operate as a cohesive unit, sharing information about revoked tasks and maintaining a consistent view of the cluster's health.

## 2.6. Result Backend Configuration for State Persistence

As established in Section 2.2, Redis will be configured as the primary result backend for the Celery system. The result backend is the datastore used to save the state (PENDING, SUCCESS, FAILURE) and return value of completed tasks. Using Redis for this purpose provides extremely fast, low-latency access to this metadata, which is essential for the Agent Orchestrator to quickly determine the status of ongoing tasks and for the TUI to provide a responsive, real-time user experience.

### TTL Policy for Memory Management

To ensure the long-term stability of the system and prevent the Redis instance from running out of memory, a global Time-To-Live (TTL) policy will be configured for all task results. By default, results will be set to expire after 24 hours. This ensures that the result backend acts as a transient cache for recent task information, rather than a permanent historical archive, which should be handled by a dedicated logging and auditing system. This TTL value will be a configurable parameter to allow administrators to adjust it based on their specific monitoring and retention requirements.

### Redis Configuration Example

```python
# Result backend configuration
result_backend = 'redis://redis:6379/0'
result_expires = 86400  # 24 hours in seconds
result_backend_transport_options = {
    'master_name': 'mymaster',
    'visibility_timeout': 3600,
    'retry_policy': {
        'timeout': 5.0
    }
}
```

## 2.7. Monitoring and Observability

The distributed task system will include comprehensive monitoring capabilities:

### Built-in Monitoring Tools

- **Celery Events**: Real-time monitoring of task execution
- **Flower**: Web-based monitoring and administration tool
- **Custom Metrics**: Integration with Prometheus for detailed metrics collection

### Key Metrics to Monitor

- Queue depth and processing rates
- Worker health and resource utilization
- Task success/failure rates
- Average task execution times
- System resource consumption

This monitoring infrastructure provides the visibility necessary for maintaining a healthy, performant distributed system.