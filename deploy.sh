#!/bin/bash
# ==============================================================================
# Manual / Standalone Remote Deployment Script
# ==============================================================================
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Or with custom arguments:
#   SERVER_IP="192.168.1.50" SERVER_USER="root" SERVER_PASS="secret" ./deploy.sh
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# Automatically load environment variables from .env file if it exists
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "Loading configuration from .env file..."
    set -a
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/.env"
    set +a
fi

# 1. Linux Server Variables (sourced from .env or environment)
SERVER_IP="${SERVER_IP:-}"
SERVER_PORT="${SERVER_PORT:-22}"
SERVER_USER="${SERVER_USER:-root}"
SERVER_PASS="${SERVER_PASSWORD:-${SERVER_PASS:-}}"
APP_PORT="${APP_PORT:-3000}"

# 2. SonarQube Variables (sourced from .env or environment)
ENABLE_SONAR="${ENABLE_SONAR_SCAN:-${ENABLE_SONAR:-false}}"
SONAR_HOST_URL="${SONAR_HOST_URL:-}"
SONAR_TOKEN="${SONAR_TOKEN:-}"
SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-simple-next-app}"

# Validation: ensure essential deployment credentials exist
if [ -z "$SERVER_IP" ] || [ -z "$SERVER_USER" ] || [ -z "$SERVER_PASS" ]; then
    echo "=========================================================================="
    echo "ERROR: Missing required server credentials!"
    echo "Please set SERVER_IP, SERVER_USER, and SERVER_PASSWORD in your .env file."
    echo "Example available in .env.example"
    echo "=========================================================================="
    exit 1
fi

IMAGE_NAME="simple-next-app"
CONTAINER_NAME="simple-next-app"
ARCHIVE_NAME="simple-next-app.tar.gz"

echo "=========================================="
echo "Starting Deployment to: ${SERVER_USER}@${SERVER_IP}:${SERVER_PORT}"
echo "=========================================="

# Optional SonarQube Scan
if [ "$ENABLE_SONAR" = "true" ]; then
    echo "--> Running SonarQube Code Scan..."
    if command -v sonar-scanner >/dev/null 2>&1; then
        sonar-scanner \
            -Dsonar.host.url="${SONAR_HOST_URL}" \
            -Dsonar.token="${SONAR_TOKEN}" \
            -Dsonar.projectKey="${SONAR_PROJECT_KEY}"
    else
        docker run --rm \
            -e SONAR_HOST_URL="${SONAR_HOST_URL}" \
            -e SONAR_TOKEN="${SONAR_TOKEN}" \
            -v "$(pwd):/usr/src" \
            sonarsource/sonar-scanner-cli \
            -Dsonar.host.url="${SONAR_HOST_URL}" \
            -Dsonar.token="${SONAR_TOKEN}" \
            -Dsonar.projectKey="${SONAR_PROJECT_KEY}"
    fi
fi

# 1. Build Docker image locally
echo "--> 1. Building Docker image..."
docker build -t ${IMAGE_NAME}:latest .

# 2. Save and compress image
echo "--> 2. Archiving Docker image to ${ARCHIVE_NAME}..."
docker save ${IMAGE_NAME}:latest | gzip > ${ARCHIVE_NAME}

# 3. Check for sshpass
if ! command -v sshpass >/dev/null 2>&1; then
    echo "Notice: 'sshpass' is required for password-based SSH."
    echo "Install it via: sudo apt-get install sshpass (Ubuntu/Debian) or brew install hudochenkov/sshpass/sshpass (Mac)"
fi

SSH_CMD="sshpass -p '${SERVER_PASS}' ssh -o StrictHostKeyChecking=no -p ${SERVER_PORT}"
SCP_CMD="sshpass -p '${SERVER_PASS}' scp -o StrictHostKeyChecking=no -P ${SERVER_PORT}"

# 4. Upload archive to Linux Server
echo "--> 3. Transferring archive to remote server..."
$SCP_CMD ${ARCHIVE_NAME} ${SERVER_USER}@${SERVER_IP}:/tmp/${ARCHIVE_NAME}

# 5. Remote load, stop old, run new container
echo "--> 4. Deploying container on remote server..."
$SSH_CMD ${SERVER_USER}@${SERVER_IP} "
    set -e
    echo 'Loading image...'
    docker load -i /tmp/${ARCHIVE_NAME}
    rm -f /tmp/${ARCHIVE_NAME}

    echo 'Replacing existing container...'
    docker stop ${CONTAINER_NAME} 2>/dev/null || true
    docker rm ${CONTAINER_NAME} 2>/dev/null || true

    docker run -d \\
        --name ${CONTAINER_NAME} \\
        --restart always \\
        -p ${APP_PORT}:3000 \\
        ${IMAGE_NAME}:latest

    echo 'Pruning unused images...'
    docker image prune -f || true

    echo 'Container status:'
    docker ps --filter 'name=${CONTAINER_NAME}'
"

# 6. Cleanup local archive
rm -f ${ARCHIVE_NAME}

echo "=========================================="
echo "Deployment Finished! App is accessible at:"
echo "http://${SERVER_IP}:${APP_PORT}"
echo "=========================================="
