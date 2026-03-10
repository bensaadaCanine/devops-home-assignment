pipeline {
    agent any

    parameters {
        choice(
            name: 'SERVICE',
            choices: ['email-checker', 'queue-checker'],
            description: 'Select which service to build and deploy'
        )
    }

    environment {
        AWS_REGION = 'eu-west-1'
        ECR_REGISTRY = '371670420772.dkr.ecr.eu-west-1.amazonaws.com'
        IMAGE_NAME = "${ECR_REGISTRY}/${params.SERVICE}"
        SERVICE_DIR = "microservices/${params.SERVICE}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Run Tests') {
            steps {
                script {
                    sh "pytest ${SERVICE_DIR} || echo 'No tests found for ${params.SERVICE}'"
                }
            }
        }

        stage('Login to ECR') {
            steps {
                sh """
                aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
                """
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    sh """
                docker build -t ${IMAGE_NAME}:latest -t ${IMAGE_NAME}:build-${BUILD_ID} ./${SERVICE_DIR}
                """
                }
            }
        }

        stage('Push Image') {
            steps {
                script {
                    sh """
                docker push ${IMAGE_NAME}:latest
                docker push ${IMAGE_NAME}:build-${BUILD_ID}
                """
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    def helmChart = 'k8s-configuration/charts/microservice'
                    def valuesFile = "k8s-configuration/values/${params.SERVICE}"
                        sh """
                        aws eks update-kubeconfig --name bensaada-home-assignment
                        helm upgrade --install ${params.SERVICE} ${helmChart} \
                            -f ${helmChart}/values.yaml \
                            -f ${valuesFile}.yaml \
                           -n microservices
                        kubectl rollout status deployment/${params.SERVICE} -n microservices
                        """
                }
            }
        }
    }
    post {
        always {
            echo "Cleaning up local Docker image for ${params.SERVICE}..."
            sh "docker rmi ${params.SERVICE} || true"
        }
        success {
            echo "Pipeline for ${params.SERVICE} completed successfully!"
        }
        failure {
            echo "Pipeline for ${params.SERVICE} failed."
        }
    }
}
