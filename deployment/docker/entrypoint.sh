#!/bin/bash

# Qilbee OS Docker Entrypoint Script
# This script handles container initialization and component startup

set -euo pipefail

# Default configuration
QILBEE_COMPONENT=${QILBEE_COMPONENT:-"full"}
QILBEE_CONFIG_PATH=${QILBEE_CONFIG_PATH:-"/etc/qilbee/config.yaml"}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC}  $(date '+%Y-%m-%d %H:%M:%S') $*" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  $(date '+%Y-%m-%d %H:%M:%S') $*" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" ;;
    esac
}

# Check if running as root
check_user() {
    if [[ $EUID -eq 0 ]]; then
        log ERROR "Do not run Qilbee OS as root user for security reasons"
        exit 1
    fi
}

# Validate environment
validate_environment() {
    log INFO "Validating environment..."
    
    # Check required environment variables based on component
    case $QILBEE_COMPONENT in
        "agent_orchestrator"|"full")
            if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
                log ERROR "ANTHROPIC_API_KEY environment variable is required"
                exit 1
            fi
            ;;
    esac
    
    # Check configuration file
    if [[ ! -f "$QILBEE_CONFIG_PATH" ]]; then
        log ERROR "Configuration file not found: $QILBEE_CONFIG_PATH"
        exit 1
    fi
    
    # Check required directories
    local required_dirs=(
        "/var/log/qilbee"
        "/tmp/qilbee-sandboxes"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log WARN "Creating missing directory: $dir"
            mkdir -p "$dir"
        fi
    done
    
    log INFO "Environment validation completed"
}

# Wait for dependencies
wait_for_dependencies() {
    log INFO "Waiting for dependencies..."
    
    # Wait for RabbitMQ if using Celery
    if [[ "$QILBEE_COMPONENT" =~ ^(task_scheduler|execution_engine|celery_worker|full)$ ]]; then
        local rabbitmq_host="${RABBITMQ_HOST:-rabbitmq}"
        local rabbitmq_port="${RABBITMQ_PORT:-5672}"
        
        log INFO "Waiting for RabbitMQ at $rabbitmq_host:$rabbitmq_port..."
        while ! nc -z "$rabbitmq_host" "$rabbitmq_port"; do
            log DEBUG "RabbitMQ not ready, waiting..."
            sleep 2
        done
        log INFO "RabbitMQ is ready"
    fi
    
    # Wait for Redis if using result backend
    if [[ "$QILBEE_COMPONENT" =~ ^(task_scheduler|execution_engine|celery_worker|full)$ ]]; then
        local redis_host="${REDIS_HOST:-redis}"
        local redis_port="${REDIS_PORT:-6379}"
        
        log INFO "Waiting for Redis at $redis_host:$redis_port..."
        while ! nc -z "$redis_host" "$redis_port"; do
            log DEBUG "Redis not ready, waiting..."
            sleep 2
        done
        log INFO "Redis is ready"
    fi
}

# Setup logging
setup_logging() {
    log INFO "Setting up logging..."
    
    # Ensure log directory exists and is writable
    if [[ ! -w "/var/log/qilbee" ]]; then
        log ERROR "Cannot write to log directory: /var/log/qilbee"
        exit 1
    fi
    
    # Create component-specific log file
    local log_file="/var/log/qilbee/${QILBEE_COMPONENT}.log"
    touch "$log_file"
    
    log INFO "Logging configured for component: $QILBEE_COMPONENT"
}

# Handle graceful shutdown
cleanup() {
    log INFO "Received shutdown signal, cleaning up..."
    
    # Kill any background processes
    jobs -p | xargs -r kill
    
    # Component-specific cleanup
    case $QILBEE_COMPONENT in
        "celery_worker")
            log INFO "Stopping Celery worker gracefully..."
            pkill -TERM celery || true
            ;;
    esac
    
    log INFO "Cleanup completed"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Start the appropriate component
start_component() {
    log INFO "Starting Qilbee OS component: $QILBEE_COMPONENT"
    
    case $QILBEE_COMPONENT in
        "agent_orchestrator")
            log INFO "Starting Agent Orchestrator..."
            exec python -m qilbee_os.agent_orchestrator.main \
                --config "$QILBEE_CONFIG_PATH"
            ;;
            
        "task_scheduler")
            log INFO "Starting Task Scheduler..."
            exec python -m qilbee_os.task_scheduler.main \
                --config "$QILBEE_CONFIG_PATH"
            ;;
            
        "execution_engine")
            log INFO "Starting Execution Engine..."
            exec python -m qilbee_os.execution_engine.main \
                --config "$QILBEE_CONFIG_PATH"
            ;;
            
        "celery_worker")
            log INFO "Starting Celery Worker..."
            exec celery worker \
                --app=qilbee_os.celery_app \
                --loglevel=info \
                --concurrency="${CELERY_CONCURRENCY:-4}" \
                --pool=prefork \
                --queues="${CELERY_QUEUES:-default,priority,tools}" \
                --hostname="worker@%h"
            ;;
            
        "celery_beat")
            log INFO "Starting Celery Beat Scheduler..."
            exec celery beat \
                --app=qilbee_os.celery_app \
                --loglevel=info \
                --schedule=/tmp/celerybeat-schedule \
                --pidfile=/tmp/celerybeat.pid
            ;;
            
        "gui_automation")
            log INFO "Starting GUI Automation Service..."
            # Start virtual display if needed
            if [[ "${DISPLAY:-}" == ":99" ]]; then
                log INFO "Starting virtual display..."
                Xvfb :99 -screen 0 1024x768x24 &
                export DISPLAY=:99
            fi
            exec python -m qilbee_os.gui_automation.main \
                --config "$QILBEE_CONFIG_PATH"
            ;;
            
        "tui")
            log INFO "Starting Terminal User Interface..."
            exec python -m qilbee_os.tui.main \
                --config "$QILBEE_CONFIG_PATH"
            ;;
            
        "full")
            log INFO "Starting full Qilbee OS instance..."
            exec python -m qilbee_os.main \
                --config "$QILBEE_CONFIG_PATH"
            ;;
            
        *)
            log ERROR "Unknown component: $QILBEE_COMPONENT"
            log INFO "Available components: agent_orchestrator, task_scheduler, execution_engine, celery_worker, celery_beat, gui_automation, tui, full"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    log INFO "Qilbee OS Container Starting..."
    log INFO "Component: $QILBEE_COMPONENT"
    log INFO "Config: $QILBEE_CONFIG_PATH"
    log INFO "User: $(whoami)"
    log INFO "Working Directory: $(pwd)"
    
    check_user
    validate_environment
    setup_logging
    wait_for_dependencies
    start_component
}

# Run main function
main "$@"