
pipeline {
    agent any

    tools {
        nodejs 'NodeJS-22'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    stages {

        // 1. CHECKOUT SOURCE CODE
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // 2. FILESYSTEM SECURITY SCAN
        stage('Trivy Security Scan') {
            steps {
                sh '''
                    set -eu

                    echo "===== TRIVY FILESYSTEM SCAN ====="

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

        // 3. INSTALL DEPENDENCIES
        stage('Install Dependencies') {
            steps {
                sh '''
                    set -eu

                    echo "===== NODE VERSION ====="
                    node --version
                    npm --version

                    echo "===== INSTALLING DEPENDENCIES ====="
                    npm ci
                '''
            }
        }

        // 4. NEXT.JS BUILD
        stage('Next.js Production Build') {
            steps {
                sh '''
                    set -eu

                    echo "===== NEXT.JS PRODUCTION BUILD ====="
                    npm run build
                '''
            }
        }

        // 5. DOCKER IMAGE BUILD
        stage('Docker Image Build') {
            steps {
                sh """
                    set -eu

                    echo "===== DOCKERFILE RUNTIME BASE ====="
                    grep -n "FROM node:" Dockerfile

                    echo "===== RUNTIME TOOL REMOVAL ====="
                    grep -n "npm\\|corepack\\|yarn" Dockerfile || true

                    echo "===== BUILDING DOCKER IMAGE ====="

                    docker build --pull --no-cache \
                        -t companysite:${BUILD_NUMBER} .

                    docker images companysite
                """
            }
        }

        // 6. DOCKER IMAGE SECURITY SCAN
        stage('Trivy Docker Image Scan') {
            steps {
                sh """
                    set -eu

                    echo "===== TRIVY IMAGE SCAN ====="

                    trivy image \
                        --scanners vuln,secret \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        companysite:${BUILD_NUMBER}
                """
            }
        }

        // 7. SONARQUBE CODE ANALYSIS
        stage('SonarQube Code Analysis') {
            steps {
                script {
                    def scannerHome = tool 'SonarScanner'

                    withSonarQubeEnv('SonarQube-Local') {
                        sh """
                            set -eu

                            echo "===== SONARQUBE ANALYSIS ====="

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

        // 8. SONARQUBE QUALITY GATE
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

        // 9. PUSH IMAGE TO AMAZON ECR
        stage('Push Docker Image to Amazon ECR') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-ecr-companysite',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        set -eu

                        AWS_REGION="us-east-1"
                        ECR_REGISTRY="109389323424.dkr.ecr.us-east-1.amazonaws.com"
                        ECR_REPOSITORY="companysite"
                        IMAGE_TAG="build-$BUILD_NUMBER"

                        echo "===== ECR AUTHENTICATION ====="

                        aws ecr get-login-password \
                            --region "$AWS_REGION" | \
                            docker login \
                                --username AWS \
                                --password-stdin "$ECR_REGISTRY"

                        echo "===== TAGGING IMAGE ====="

                        docker tag \
                            "companysite:$BUILD_NUMBER" \
                            "$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"

                        echo "===== PUSHING IMAGE TO ECR ====="

                        docker push \
                            "$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"

                        echo "ECR_PUSH_SUCCESSFUL: $IMAGE_TAG"

                        docker logout "$ECR_REGISTRY"
                    '''
                }
            }
        }

        // 10. DYNAMIC BLUE-GREEN DEPLOYMENT
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

                        echo "======================================"
                        echo "       BLUE-GREEN DEPLOYMENT"
                        echo "======================================"

                        echo "Image: $IMAGE_TAG"
                        echo "EC2: $EC2_HOST"

                        echo "===== CONNECTING TO EC2 ====="

                        ssh -i "$SSH_KEY" \
                            -o BatchMode=yes \
                            -o IdentitiesOnly=yes \
                            -o StrictHostKeyChecking=yes \
                            -o ConnectTimeout=15 \
                            -o ServerAliveInterval=30 \
                            "$SSH_USER@$EC2_HOST" \
                            "sudo -n /opt/companysite/deploy/bluegreen-deploy.sh '$IMAGE_TAG'"

                        echo "===== BLUE-GREEN DEPLOYMENT COMPLETED ====="
                    '''
                }
            }
        }
    }

    post {
        success {
            echo '''
            ======================================
                  CI/CD PIPELINE SUCCESS
            ======================================
            Security scan: PASSED
            Next.js build: PASSED
            Docker build: PASSED
            SonarQube: PASSED
            ECR push: PASSED
            Blue-Green deployment: PASSED
            ======================================
            '''
        }

        failure {
            echo '''
            ======================================
                  CI/CD PIPELINE FAILED
            ======================================
            Check the failed stage in Jenkins.
            Production traffic is not assumed to
            have changed if deployment failed.
            ======================================
            '''
        }

        always {
            echo "Pipeline execution completed."
        }
    }
}
