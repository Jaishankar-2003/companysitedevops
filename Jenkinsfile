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
    }
}
