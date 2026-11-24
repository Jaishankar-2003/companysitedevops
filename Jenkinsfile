
pipeline {
    agent any

    tools {
        nodejs 'NodeJS-22'
    }

    options {
        timestamps()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Trivy Security Scan') {
            steps {
                sh '''
                    echo "Starting Trivy filesystem security scan..."

                    trivy fs \
                        --scanners vuln,misconfig,secret \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        --skip-dirs .git \
                        --skip-dirs node_modules \
                        --skip-dirs .next \
                        .
                '''
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    node --version
                    npm --version
                    npm ci
                '''
            }
        }

        stage('Next.js Production Build') {
            steps {
                sh 'npm run build'
            }
        }

        stage('Docker Image Build') {
            steps {
                sh """
                    echo "Building secured Alpine image..."

                    echo "===== Dockerfile Runtime Base ====="
                    grep -n "FROM node:" Dockerfile

                    echo "===== Runtime Tool Removal ====="
                    grep -n "npm\\|corepack\\|yarn" Dockerfile || true

                    docker build --pull --no-cache \
                        -t companysite:${BUILD_NUMBER} .

                    docker images companysite
                """
            }
        }

        stage('Trivy Docker Image Scan') {
            steps {
                sh """
                    echo "Scanning Docker image for vulnerabilities and secrets..."

                    trivy image \
                        --scanners vuln,secret \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        companysite:${BUILD_NUMBER}
                """
            }
        }

        stage('SonarQube Code Analysis') {
            steps {
                script {
                    def scannerHome = tool 'SonarScanner'

                    withSonarQubeEnv('SonarQube-Local') {
                        sh """
                            ${scannerHome}/bin/sonar-scanner \
                                -Dsonar.projectKey=CompanySite \
                                -Dsonar.projectName=CompanySite \
                                -Dsonar.sources=src \
                                -Dsonar.exclusions=**/node_modules/**,**/.next/** \
                                -Dsonar.sourceEncoding=UTF-8
                        """
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    script {
                        def qg = waitForQualityGate()

                        echo "Quality Gate Status: ${qg.status}"

                        if (qg.status != 'OK') {
                            error "Quality Gate failed: ${qg.status}"
                        }
                    }
                }
            }
        }

        stage('Push Docker Image to Amazon ECR') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'aws-ecr-companysite',
                    usernameVariable: 'AWS_ACCESS_KEY_ID',
                    passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    sh '''
                        set -eu

                        AWS_REGION="us-east-1"
                        ECR_REGISTRY="109389323424.dkr.ecr.us-east-1.amazonaws.com"
                        ECR_REPOSITORY="companysite"
                        IMAGE_TAG="build-$BUILD_NUMBER"

                        echo "Authenticating with Amazon ECR..."

                        aws ecr get-login-password \
                            --region "$AWS_REGION" | \
                            docker login \
                            --username AWS \
                            --password-stdin "$ECR_REGISTRY"

                        echo "Tagging Docker image..."

                        docker tag \
                            "companysite:$BUILD_NUMBER" \
                            "$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"

                        echo "Pushing image to ECR..."

                        docker push \
                            "$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"

                        echo "Successfully pushed: $IMAGE_TAG"

                        docker logout "$ECR_REGISTRY"
                    '''
                }
            }
        }

        stage('Deploy to EC2 - Blue Green') {
            steps {
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'companysite-ec2-ssh',
                        keyFileVariable: 'SSH_KEY',
                        usernameVariable: 'SSH_USER'
                    )
                ]) {
                    sh '''
                        set -eu

                        EC2_HOST="98.91.240.191"
                        IMAGE_TAG="build-$BUILD_NUMBER"

                        echo "===== CONNECTING TO EC2 ====="

                        ssh -i "$SSH_KEY" \
                            -o BatchMode=yes \
                            -o StrictHostKeyChecking=yes \
                            "$SSH_USER@$EC2_HOST" \
                            "IMAGE_TAG='$IMAGE_TAG' bash -s" <<'REMOTE'
                        set -eu

                        DEPLOY_DIR="/opt/companysite/deploy"
                        CONFIG="$DEPLOY_DIR/deployment.env"

                        source "$CONFIG"

                        echo "===== CHECKING ACTIVE PRODUCTION PORT ====="

                        ACTIVE_PORT=$(sudo grep -oE 'proxy_pass http://127\\.0\\.0\\.1:[0-9]+' \
                            /etc/nginx/conf.d/companysite.conf \
                            | grep -oE '[0-9]+$')

                        echo "Current production port: $ACTIVE_PORT"

                        if [ "$ACTIVE_PORT" = "$CANDIDATE_PORT" ]; then
                            echo "ERROR: Candidate port is currently serving production."
                            echo "The existing fixed-slot deploy.sh cannot safely replace it."
                            exit 1
                        fi

                        if [ "$ACTIVE_PORT" != "$PRODUCTION_PORT" ]; then
                            echo "ERROR: Unexpected Nginx production port."
                            exit 1
                        fi

                        echo "===== REMOVING OLD STANDBY CONTAINER ====="

                        if sudo docker container inspect "$CANDIDATE_CONTAINER" >/dev/null 2>&1; then
                            sudo docker rm -f "$CANDIDATE_CONTAINER"
                        fi

                        echo "===== DEPLOYING NEW IMAGE ====="

                        sudo "$DEPLOY_DIR/deploy.sh" "$IMAGE_TAG"

                        echo "===== SWITCHING TRAFFIC ====="

                        sudo "$DEPLOY_DIR/switch-traffic.sh" "$CANDIDATE_PORT"

                        echo "===== VERIFYING PRODUCTION ====="

                        sudo curl --fail --silent --show-error \
                            http://127.0.0.1/ \
                            -o /dev/null

                        echo "BLUE_GREEN_DEPLOYMENT_SUCCESSFUL"
                        REMOTE
                    '''
                }
            }
        }
    }
}
