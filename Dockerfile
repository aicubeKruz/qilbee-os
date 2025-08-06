# Multi-stage Dockerfile for Qilbee OS
# Optimized for production deployment with security best practices

# Builder stage
FROM python:3.11-slim as builder

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    libffi-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy requirements first for better layer caching
COPY requirements.txt .
COPY pyproject.toml .
COPY README.md .

# Install Python dependencies
RUN pip install --user --no-warn-script-location -r requirements.txt

# Copy source code
COPY src/ ./src/

# Install the application
RUN pip install --user --no-warn-script-location .

# Production stage
FROM python:3.11-slim as production

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/home/qilbee/.local/bin:$PATH" \
    QILBEE_CONFIG_PATH="/etc/qilbee/config.yaml"

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    # Essential system packages
    curl \
    gnupg \
    ca-certificates \
    dumb-init \
    # GUI automation dependencies (optional)
    xvfb \
    x11-utils \
    scrot \
    xdotool \
    # Wayland support (optional)
    grim \
    ydotool \
    # Security and sandboxing
    nsjail \
    apparmor-utils \
    # Monitoring tools
    htop \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user and group
RUN groupadd -r qilbee --gid=1000 && \
    useradd -r -g qilbee --uid=1000 --home-dir=/home/qilbee --shell=/bin/bash qilbee && \
    mkdir -p /home/qilbee && \
    chown -R qilbee:qilbee /home/qilbee

# Copy Python packages from builder stage
COPY --from=builder --chown=qilbee:qilbee /root/.local /home/qilbee/.local

# Create necessary directories
RUN mkdir -p \
    /etc/qilbee/tls \
    /etc/qilbee/oauth \
    /etc/qilbee/plugins \
    /var/log/qilbee \
    /tmp/qilbee-sandboxes \
    /tmp/qilbee-chroot \
    && chown -R qilbee:qilbee \
        /etc/qilbee \
        /var/log/qilbee \
        /tmp/qilbee-sandboxes \
        /tmp/qilbee-chroot

# Copy configuration files
COPY --chown=qilbee:qilbee config/ /etc/qilbee/

# Copy additional scripts and configs
COPY --chown=qilbee:qilbee scripts/ /usr/local/bin/
COPY --chown=qilbee:qilbee deployment/docker/entrypoint.sh /usr/local/bin/
COPY --chown=qilbee:qilbee deployment/docker/healthcheck.sh /usr/local/bin/

# Make scripts executable
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# Set up default nsjail configuration
COPY --chown=qilbee:qilbee config/nsjail-default.cfg /etc/qilbee/

# Switch to non-root user
USER qilbee

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# Expose ports
EXPOSE 8080 50051 9090

# Set working directory
WORKDIR /home/qilbee

# Use dumb-init to handle signals properly
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Default command
CMD ["/usr/local/bin/entrypoint.sh"]

# Labels for better container management
LABEL maintainer="AICUBE Technology <support@aicube.technology>" \
      version="1.0.0" \
      description="Qilbee OS - Enterprise Conversational Operating System" \
      org.opencontainers.image.title="Qilbee OS" \
      org.opencontainers.image.description="Enterprise Conversational Operating System" \
      org.opencontainers.image.vendor="AICUBE Technology" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.source="https://github.com/aicubeKruz/qilbee-os" \
      org.opencontainers.image.licenses="MIT"