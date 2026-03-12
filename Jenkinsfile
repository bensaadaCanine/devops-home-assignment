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
                    sh """
                    if find ${SERVICE_DIR} -name "*test*" | grep -q .; then
                        pip3 install -r ${SERVICE_DIR}/requirements.txt
                        pytest ${SERVICE_DIR} -v
                    else
                        echo "No tests found for ${params.SERVICE}, skipping..."
                    fi
                    """
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
                    def helmChart = './k8s-configuration/charts/microservices-chart'
                    def valuesFile = "./k8s-configuration/values/${params.SERVICE}"
                        sh """
                        aws eks update-kubeconfig \
                          --region eu-west-1 \
                          --name bensaada-home-assignment \
                          --kubeconfig kubeconfig

                        export KUBECONFIG=$WORKSPACE/kubeconfig

                        helm upgrade --install ${params.SERVICE} ${helmChart} \
                            --set image.tag="build-${BUILD_ID}" \
                            -f ${helmChart}/values.yaml \
                            -f ${valuesFile}.yaml \
                           -n microservices
                        kubectl rollout status deployment/${params.SERVICE} -n microservices --timeout=300s
                        """
                }
            }
        }
    }
    post {
        always {
            echo "Cleaning up local Docker image for ${params.SERVICE}..."
            sh "docker rmi  ${IMAGE_NAME}:latest || true"
            sh "docker rmi  ${IMAGE_NAME}:build-${BUILD_ID} || true"
            sh "rm -f $WORKSPACE/kubeconfig"
        }
        success {
            echo "Pipeline for ${params.SERVICE} completed successfully!"
        }
        failure {
            echo "Pipeline for ${params.SERVICE} failed."
        }
    }
}
