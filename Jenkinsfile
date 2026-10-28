pipeline {
    agent any

    // ==============================================================================
    // [CREDENTIALS NOTICE]
    // All credentials and server IPs are loaded from your local '.env' file, which is
    // IGNORED by git (.gitignore) to keep all passwords and server IPs completely safe!
    //
    // If running in Jenkins without a .env file, you can optionally input or override
    // them via "Build with Parameters" below.
    // ==============================================================================
    parameters {
        // --------------------------------------------------------------------------
        // 0. JENKINS SECRET FILE CREDENTIAL (.env)
        // --------------------------------------------------------------------------
        string(
            name: 'ENV_CREDENTIAL_ID',
            defaultValue: 'app-env-file',
            description: 'Jenkins Secret File Credential ID containing .env (Leave blank if not using Secret File)'
        )

        // --------------------------------------------------------------------------
        // 1. LINUX DEPLOYMENT SERVER PARAMETERS (Overrides .env if specified)
        // --------------------------------------------------------------------------
        string(
            name: 'SERVER_IP',
            defaultValue: '', 
            description: 'Linux Server IP (Leave blank to use SERVER_IP from .env)'
        )
        string(
            name: 'SERVER_PORT',
            defaultValue: '', 
            description: 'SSH Port (Leave blank to use SERVER_PORT from .env, default 22)'
        )
        string(
            name: 'SERVER_USER',
            defaultValue: '', 
            description: 'SSH Username (Leave blank to use SERVER_USER from .env)'
        )
        password(
            name: 'SERVER_PASSWORD',
            defaultValue: '', 
            description: 'SSH Password (Leave blank to use SERVER_PASSWORD from .env)'
        )
        string(
            name: 'APP_PORT',
            defaultValue: '', 
            description: 'Target Application Port (Leave blank to use APP_PORT from .env, default 3000)'
        )

        // --------------------------------------------------------------------------
        // 2. SONARQUBE SERVER PARAMETERS (Overrides .env if specified)
        // --------------------------------------------------------------------------
        booleanParam(
            name: 'ENABLE_SONAR_SCAN',
            defaultValue: true, 
            description: 'Enable or disable SonarQube code scan'
        )
        string(
            name: 'SONAR_HOST_URL',
            defaultValue: '', 
            description: 'SonarQube Server URL (Leave blank to use SONAR_HOST_URL from .env)'
        )
        password(
            name: 'SONAR_TOKEN',
            defaultValue: '', 
            description: 'SonarQube Token (Leave blank to use SONAR_TOKEN from .env)'
        )
        string(
            name: 'SONAR_PROJECT_KEY',
            defaultValue: '', 
            description: 'SonarQube Project Key (Leave blank to use SONAR_PROJECT_KEY from .env, default simple-next-app)'
        )
    }

    // ==============================================================================
    // [BEST PRACTICE] PIPELINE CONTROLS & RESOURCE GUARDS
    // ==============================================================================
    options {
        // Keep only the last 10 builds to save Jenkins storage
        buildDiscarder(logRotator(numToKeepStr: '10'))
        // Abort pipeline if any step or SSH connection hangs over 30 minutes
        timeout(time: 30, unit: 'MINUTES')
        // Prevent simultaneous deployments from conflicting on the remote server
        disableConcurrentBuilds()
    }

    environment {
        // Application / Container Settings
        IMAGE_NAME         = 'simple-next-app'
        CONTAINER_NAME     = 'simple-next-app'
        IMAGE_ARCHIVE      = 'simple-next-app.tar.gz'
    }

    stages {
        stage('Checkout Source Code') {
            steps {
                echo "Fetching latest source code from repository..."
                checkout scm
            }
        }

        stage('Load Environment Config (.env)') {
            steps {
                script {
                    // 1. Try to fetch .env from Jenkins Secret File credential
                    def credId = (params.ENV_CREDENTIAL_ID?.trim()) ? params.ENV_CREDENTIAL_ID.trim() : 'app-env-file'
                    try {
                        withCredentials([file(credentialsId: credId, variable: 'SECRET_ENV_FILE')]) {
                            if (fileExists(SECRET_ENV_FILE)) {
                                echo "--> [SECRET FILE] Injected .env from Jenkins Credential ID: '${credId}'"
                                sh 'cp "$SECRET_ENV_FILE" .env'
                            }
                        }
                    } catch (Exception e) {
                        echo "--> [NOTICE] Jenkins Secret File '${credId}' not found in Credential store. Checking workspace or parameters..."
                    }

                    // 2. Check if local .env file exists in the workspace
                    def dotenv = [:]
                    if (fileExists('.env')) {
                        echo "--> Found .env file in workspace. Loading server credentials..."
                        def envFileContent = readFile('.env').replace('\uFEFF', '')
                        def lines = envFileContent.split('\\r?\\n')
                        for (int i = 0; i < lines.length; i++) {
                            def line = lines[i].trim()
                            if (line && !line.startsWith('#') && line.contains('=')) {
                                int eqIdx = line.indexOf('=')
                                def key = line.substring(0, eqIdx).trim()
                                def val = line.substring(eqIdx + 1).trim()
                                if (val.length() >= 2 && ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'")))) {
                                    val = val.substring(1, val.length() - 1)
                                }
                                dotenv[key] = val
                                env[key] = val
                            }
                        }
                        echo "--> Loaded ${dotenv.size()} configuration keys from .env: ${dotenv.keySet().join(', ')}"
                    } else {
                        echo "--> Notice: No .env file found in workspace. Using parameters/environment."
                    }

                    // Safely extract build parameters (note: Jenkins password() parameters return hudson.util.Secret,
                    // which is always truthy as an object even when empty, so convert via .toString() before checking)
                    def paramIp         = params.SERVER_IP ? params.SERVER_IP.toString().trim() : ''
                    def paramPort       = params.SERVER_PORT ? params.SERVER_PORT.toString().trim() : ''
                    def paramUser       = params.SERVER_USER ? params.SERVER_USER.toString().trim() : ''
                    def paramPass       = params.SERVER_PASSWORD ? params.SERVER_PASSWORD.toString().trim() : ''
                    def paramAppPort    = params.APP_PORT ? params.APP_PORT.toString().trim() : ''
                    def paramSonarHost  = params.SONAR_HOST_URL ? params.SONAR_HOST_URL.toString().trim() : ''
                    def paramSonarToken = params.SONAR_TOKEN ? params.SONAR_TOKEN.toString().trim() : ''
                    def paramSonarKey   = params.SONAR_PROJECT_KEY ? params.SONAR_PROJECT_KEY.toString().trim() : ''

                    // Resolve final target variables with priority: parameter (if filled) > .env > default
                    env.TARGET_IP          = paramIp ?: (dotenv['SERVER_IP'] ?: (env.SERVER_IP ?: ''))
                    env.TARGET_PORT        = paramPort ?: (dotenv['SERVER_PORT'] ?: (env.SERVER_PORT ?: '22'))
                    env.TARGET_USER        = paramUser ?: (dotenv['SERVER_USER'] ?: (env.SERVER_USER ?: 'root'))
                    env.TARGET_PASS        = paramPass ?: (dotenv['SERVER_PASSWORD'] ?: (env.SERVER_PASSWORD ?: ''))
                    env.SSHPASS            = env.TARGET_PASS
                    env.TARGET_APP_PORT    = paramAppPort ?: (dotenv['APP_PORT'] ?: (env.APP_PORT ?: '3000'))

                    env.TARGET_SONAR_HOST  = paramSonarHost ?: (dotenv['SONAR_HOST_URL'] ?: (env.SONAR_HOST_URL ?: ''))
                    env.TARGET_SONAR_TOKEN = paramSonarToken ?: (dotenv['SONAR_TOKEN'] ?: (env.SONAR_TOKEN ?: ''))
                    env.TARGET_SONAR_KEY   = (paramSonarKey && paramSonarKey != 'simple-next-app') ? paramSonarKey : (dotenv['SONAR_PROJECT_KEY'] ?: (paramSonarKey ?: 'simple-next-app'))
                    
                    def enableSonarParam = params.ENABLE_SONAR_SCAN != null ? params.ENABLE_SONAR_SCAN : true
                    def dotenvSonar = dotenv['ENABLE_SONAR_SCAN'] != null ? dotenv['ENABLE_SONAR_SCAN'] : env.ENABLE_SONAR_SCAN
                    env.SHOULD_SCAN_SONAR  = (dotenvSonar != null ? dotenvSonar.toString().toBoolean() : enableSonarParam).toString()

                    // Validate that deployment targets are available
                    if (!env.TARGET_IP || !env.TARGET_USER || !env.TARGET_PASS) {
                        error("CRITICAL: Missing server credentials! Resolved TARGET_IP='${env.TARGET_IP}', TARGET_USER='${env.TARGET_USER}', TARGET_PASS_SET=${env.TARGET_PASS ? 'true' : 'false'}. Please ensure .env exists with SERVER_IP, SERVER_USER, and SERVER_PASSWORD, or supply them as build parameters.")
                    }

                    echo "Configuration resolved:"
                    echo "  - Linux Server: ${env.TARGET_USER}@${env.TARGET_IP}:${env.TARGET_PORT}"
                    echo "  - Target Port : ${env.TARGET_APP_PORT}"
                    echo "  - SonarQube   : ${env.TARGET_SONAR_HOST ? env.TARGET_SONAR_HOST + ' (Project: ' + env.TARGET_SONAR_KEY + ')' : 'Disabled/Not configured'}"
                }
            }
        }

        stage('SonarQube Code Analysis') {
            when {
                expression { 
                    return env.SHOULD_SCAN_SONAR == 'true' && env.TARGET_SONAR_HOST != ''
                }
            }
            steps {
                echo "=========================================="
                echo "Running SonarQube Code Quality Scan"
                echo "SonarQube Server : ${TARGET_SONAR_HOST}"
                echo "Project Key      : ${TARGET_SONAR_KEY}"
                echo "=========================================="
                sh """
                    # 1. If sonar-scanner is installed on the Jenkins agent, use it
                    if command -v sonar-scanner >/dev/null 2>&1; then
                        echo "Using local sonar-scanner CLI..."
                        sonar-scanner \\
                            -Dsonar.host.url="${TARGET_SONAR_HOST}" \\
                            -Dsonar.token="${TARGET_SONAR_TOKEN}" \\
                            -Dsonar.projectKey="${TARGET_SONAR_KEY}"
                    else
                        # 2. Otherwise run official SonarSource Docker CLI (no local installation required!)
                        echo "Local sonar-scanner CLI not found. Running via Docker (sonarsource/sonar-scanner-cli)..."
                        docker run --rm \\
                            -e SONAR_HOST_URL="${TARGET_SONAR_HOST}" \\
                            -e SONAR_TOKEN="${TARGET_SONAR_TOKEN}" \\
                            -v "\$(pwd):/usr/src" \\
                            sonarsource/sonar-scanner-cli \\
                            -Dsonar.host.url="${TARGET_SONAR_HOST}" \\
                            -Dsonar.token="${TARGET_SONAR_TOKEN}" \\
                            -Dsonar.projectKey="${TARGET_SONAR_KEY}"
                    fi
                """
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "=========================================="
                echo "Building Docker image: ${IMAGE_NAME}:${BUILD_NUMBER}"
                echo "=========================================="
                sh """
                    docker build -t ${IMAGE_NAME}:${BUILD_NUMBER} -t ${IMAGE_NAME}:latest .
                """
            }
        }

        stage('Archive Image for Transfer') {
            steps {
                echo "=========================================="
                echo "Saving Docker image to archive: ${IMAGE_ARCHIVE}"
                echo "=========================================="
                sh """
                    docker save ${IMAGE_NAME}:latest | gzip > ${IMAGE_ARCHIVE}
                    ls -lh ${IMAGE_ARCHIVE}
                """
            }
        }

        stage('Deploy to Linux Server') {
            steps {
                echo "=========================================="
                echo "Deploying to Linux Server: ${TARGET_USER}@${TARGET_IP}:${TARGET_PORT}"
                echo "Target Application URL: http://${TARGET_IP}:${TARGET_APP_PORT}"
                echo "=========================================="

                sh """
                    # Ensure sshpass and openssh-client are installed on Jenkins agent
                    if ! command -v sshpass >/dev/null 2>&1; then
                        echo "sshpass not found. Attempting installation on Jenkins runner..."
                        if command -v apt-get >/dev/null 2>&1; then
                            apt-get update && apt-get install -y sshpass openssh-client
                        elif command -v apk >/dev/null 2>&1; then
                            apk add --no-cache sshpass openssh-client
                        elif command -v yum >/dev/null 2>&1; then
                            yum install -y sshpass openssh-clients
                        else
                            echo "ERROR: Please install 'sshpass' on your Jenkins agent machine."
                            exit 1
                        fi
                    fi

                    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

                    echo "1. Testing SSH connectivity to ${TARGET_USER}@${TARGET_IP}..."
                    sshpass -e ssh \$SSH_OPTS -p "${TARGET_PORT}" "${TARGET_USER}@${TARGET_IP}" "echo 'SSH connection successful! Remote host:' \$(hostname)"

                    echo "2. Checking Docker availability on remote server..."
                    sshpass -e ssh \$SSH_OPTS -p "${TARGET_PORT}" "${TARGET_USER}@${TARGET_IP}" "docker --version || { echo 'Docker is not installed or not running on remote server!'; exit 1; }"

                    echo "3. Transferring compressed Docker image to /tmp on remote server..."
                    sshpass -e scp \$SSH_OPTS -P "${TARGET_PORT}" "${IMAGE_ARCHIVE}" "${TARGET_USER}@${TARGET_IP}:/tmp/${IMAGE_ARCHIVE}"

                    echo "4. Loading Docker image and restarting container on remote server..."
                    sshpass -e ssh \$SSH_OPTS -p "${TARGET_PORT}" "${TARGET_USER}@${TARGET_IP}" "
                        set -e
                        echo '--> Loading image from /tmp/${IMAGE_ARCHIVE}...'
                        docker load -i /tmp/${IMAGE_ARCHIVE}
                        rm -f /tmp/${IMAGE_ARCHIVE}

                        echo '--> Stopping and removing old container if exists...'
                        docker stop ${CONTAINER_NAME} 2>/dev/null || true
                        docker rm ${CONTAINER_NAME} 2>/dev/null || true

                        echo '--> Starting new container on port ${TARGET_APP_PORT}...'
                        docker run -d \\
                            --name ${CONTAINER_NAME} \\
                            --restart always \\
                            -p ${TARGET_APP_PORT}:3000 \\
                            ${IMAGE_NAME}:latest

                        echo '--> Cleaning up old dangling Docker images...'
                        docker image prune -f || true
                    "
                """
            }
        }

        stage('Verify Remote Container & Health Check') {
            steps {
                echo "=========================================="
                echo "Verifying container status and HTTP response"
                echo "=========================================="
                sh """
                    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
                    
                    echo "1. Checking container running status:"
                    sshpass -e ssh \$SSH_OPTS -p "${TARGET_PORT}" "${TARGET_USER}@${TARGET_IP}" "docker ps --filter 'name=${CONTAINER_NAME}' --format 'table {{.ID}}\\t{{.Names}}\\t{{.Status}}\\t{{.Ports}}'"
                    
                    echo "2. Polling HTTP health check on port ${TARGET_APP_PORT} (up to 30 seconds)..."
                    sshpass -e ssh \$SSH_OPTS -p "${TARGET_PORT}" "${TARGET_USER}@${TARGET_IP}" "
                        for i in \$(seq 1 15); do
                            HTTP_CODE=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${TARGET_APP_PORT} || true)
                            if [ \"\$HTTP_CODE\" = \"200\" ] || [ \"\$HTTP_CODE\" = \"304\" ]; then
                                echo \"--> [HEALTH CHECK PASSED] App responded with HTTP \$HTTP_CODE\"
                                exit 0
                            fi
                            echo \"Waiting for application to start... (attempt \$i/15, status: \$HTTP_CODE)\"
                            sleep 2
                        done
                        echo \"--> [WARNING] Health check probe timed out. Displaying last 30 container logs:\"
                        docker logs --tail 30 ${CONTAINER_NAME}
                    "
                """
            }
        }
    }

    post {
        always {
            echo "--> [CLEANUP] Cleaning temporary image archives and workspace secrets..."
            sh "rm -f ${IMAGE_ARCHIVE} .env || true"
        }
        success {
            echo "=========================================================================="
            echo "SUCCESS: App successfully deployed & verified at http://${TARGET_IP}:${TARGET_APP_PORT}"
            echo "=========================================================================="
        }
        failure {
            echo "=========================================================================="
            echo "PIPELINE FAILED. Please review the logs above."
            echo "=========================================================================="
        }
    }
}
