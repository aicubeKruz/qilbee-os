#!/bin/bash

# Qilbee OS Health Check Script
# This script performs health checks for different components

set -euo pipefail

COMPONENT=${QILBEE_COMPONENT:-"full"}
HEALTH_CHECK_PORT=${HEALTH_CHECK_PORT:-8081}
TIMEOUT=${HEALTH_CHECK_TIMEOUT:-10}

# Health check functions for different components
check_agent_orchestrator() {
    local port=${QILBEE_AGENT_PORT:-8080}
    curl -f -m "$TIMEOUT" "http://localhost:$port/health" >/dev/null 2>&1
}

check_task_scheduler() {
    local port=${QILBEE_SCHEDULER_PORT:-8082}
    curl -f -m "$TIMEOUT" "http://localhost:$port/health" >/dev/null 2>&1
}

check_execution_engine() {
    local port=${QILBEE_ENGINE_PORT:-8083}
    curl -f -m "$TIMEOUT" "http://localhost:$port/health" >/dev/null 2>&1
}

check_celery_worker() {
    # Check if celery worker is responsive
    celery inspect ping --app=qilbee_os.celery_app --timeout="$TIMEOUT" >/dev/null 2>&1
}

check_celery_beat() {
    # Check if beat scheduler is running
    pgrep -f "celery beat" >/dev/null 2>&1
}

check_gui_automation() {
    local port=${QILBEE_GUI_PORT:-8084}
    curl -f -m "$TIMEOUT" "http://localhost:$port/health" >/dev/null 2>&1
}

check_full_system() {
    # For full system, check main health endpoint
    curl -f -m "$TIMEOUT" "http://localhost:$HEALTH_CHECK_PORT/health" >/dev/null 2>&1
}

# Main health check logic
case $COMPONENT in
    "agent_orchestrator")
        check_agent_orchestrator
        ;;
    "task_scheduler")
        check_task_scheduler
        ;;
    "execution_engine")
        check_execution_engine
        ;;
    "celery_worker")
        check_celery_worker
        ;;
    "celery_beat")
        check_celery_beat
        ;;
    "gui_automation")
        check_gui_automation
        ;;
    "full")
        check_full_system
        ;;
    *)
        echo "Unknown component: $COMPONENT"
        exit 1
        ;;
esac

exit $?