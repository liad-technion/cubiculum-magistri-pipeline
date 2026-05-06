pipeline {
    agent any

    parameters {
        string(
            name: 'VERSION',
            defaultValue: '',
            description: 'Image tag to deploy (required for testing/staging/production)'
        )
    }

    environment {
        IMAGE = 'devtwist/cubiculum-magistri-app'
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Spell check') {
            when { branch 'develop' }
            steps {
                sh 'pip install --user --quiet codespell==2.3.0'
                sh 'python -m codespell app/'
            }
        }

        stage('Lint') {
            when { branch 'develop' }
            steps {
                sh 'pip install --user --quiet ruff==0.6.9'
                sh 'python -m ruff check app/'
            }
        }

        stage('Test') {
            when { branch 'develop' }
            steps {
                sh 'pip install --user --quiet -r requirements.txt'
                sh 'python -m pytest app/tests'
            }
        }

        stage('Build & push') {
            when { branch 'develop' }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DH_USER',
                    passwordVariable: 'DH_PASS'
                )]) {
                    sh '''
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        docker build \
                            --build-arg APP_VERSION=${BUILD_NUMBER} \
                            -t ${IMAGE}:${BUILD_NUMBER} .
                        docker push ${IMAGE}:${BUILD_NUMBER}
                    '''
                }
            }
        }

        stage('Pull image') {
            when {
                anyOf {
                    branch 'testing'
                    branch 'staging'
                    branch 'production'
                }
            }
            steps {
                script {
                    if (!params.VERSION?.trim()) {
                        error 'VERSION parameter is required on testing/staging/production'
                    }
                }
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DH_USER',
                    passwordVariable: 'DH_PASS'
                )]) {
                    sh '''
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        docker pull ${IMAGE}:${VERSION}
                    '''
                }
            }
        }

        stage('Approval') {
            when {
                anyOf {
                    branch 'staging'
                    branch 'production'
                }
            }
            steps {
                input message: "Deploy ${IMAGE}:${params.VERSION} to ${env.BRANCH_NAME}?"
            }
        }

        stage('Deploy & smoke test') {
            when {
                anyOf {
                    branch 'testing'
                    branch 'staging'
                    branch 'production'
                }
            }
            steps {
                sh '''
                    export IMAGE VERSION
                    export APP_ENV=${BRANCH_NAME}
                    docker compose up -d
                    bash smoke_test.sh
                '''
            }
            post {
                always {
                    sh 'docker compose down || true'
                }
            }
        }
    }
}