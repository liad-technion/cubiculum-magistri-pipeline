# Jenkins multi-branch pipeline class task

As part of the devops team you are required to wire up CI/CD for a tiny Python service. The dev team leader wants a single Jenkins multi-branch pipeline that behaves differently per branch: on `develop` it spell-checks, lints, tests, builds and pushes a versioned Docker image to Docker Hub; on `testing`, `staging` and `production` it pulls a specific version of that image, runs it, and smoke-tests that the running container actually serves the version that was requested.

## Prerequisites

- A GitHub account.
- A Docker Hub account and a Docker Hub access token (Account Settings → Security → New Access Token).
- Access to a Jenkins instance with:
    - The "Pipeline", "Pipeline: Multibranch", "Git" and "Credentials Binding" plugins installed.
    - An agent that has `docker`, `docker compose`, `python3.12`, `pip`, `curl` and `jq` available on `PATH`.
- Local tools: `git`, `docker`, `docker compose`, `curl`, `jq`.

## Part 1 — Set up the repository

- Create a new empty repository under your user name in GitHub named: `cubiculum-magistri-pipeline`.
    - Do **not** initialize it with a README, `.gitignore` or license.
- On your machine, create the project directory and initialize it on the `develop` branch:
    - `mkdir cubiculum-magistri-pipeline && cd cubiculum-magistri-pipeline`
    - `git init -b develop`
- Configure your identity for this repo if you have not set it globally:
    - `git config user.name "<your name>"`
    - `git config user.email "<your github email>"`
- Connect the remote (do not push yet — there is nothing to push):
    - `git remote add origin git@github.com:<your-user>/cubiculum-magistri-pipeline.git`

## Part 2 — Build the Python application

- Inside the project create the following files with **exactly** this content:
    - `app/__init__.py` — empty file.
    - `app/main.py`
        ```python
        import os

        from flask import Flask, jsonify

        APP_NAME = "cubiculum-magistri-app"
        APP_VERSION = os.environ.get("APP_VERSION", "dev")
        APP_ENV = os.environ.get("APP_ENV", "local")

        app = Flask(__name__)


        @app.get("/")
        def index():
            return jsonify(app=APP_NAME, version=APP_VERSION, env=APP_ENV)


        if __name__ == "__main__":
            app.run(host="0.0.0.0", port=8000)
        ```
    - `app/tests/__init__.py` — empty file.
    - `app/tests/test_main.py`
        ```python
        from app.main import app


        def test_root_returns_200():
            client = app.test_client()
            response = client.get("/")
            assert response.status_code == 200


        def test_root_payload_has_required_keys():
            client = app.test_client()
            payload = client.get("/").get_json()
            assert payload["app"] == "cubiculum-magistri-app"
            assert "version" in payload
            assert "env" in payload
        ```
    - `requirements.txt`
        ```
        flask==3.0.3
        pytest==8.3.3
        ruff==0.6.9
        codespell==2.3.0
        ```
    - `.gitignore`
        ```
        __pycache__/
        *.pyc
        .pytest_cache/
        .ruff_cache/
        ```

## Part 3 — Containerise the application

- Create the following files with **exactly** this content:
    - `Dockerfile`
        ```dockerfile
        FROM python:3.12-slim

        WORKDIR /srv

        COPY requirements.txt ./
        RUN pip install --no-cache-dir -r requirements.txt

        COPY app ./app

        ARG APP_VERSION=dev
        ENV APP_VERSION=${APP_VERSION}

        EXPOSE 8000

        CMD ["python", "-m", "app.main"]
        ```
    - `docker-compose.yml`
        ```yaml
        services:
          app:
            image: ${IMAGE}:${VERSION}
            ports:
              - "8000:8000"
            environment:
              APP_ENV: ${APP_ENV}
        ```
    - `smoke_test.sh`
        ```bash
        #!/usr/bin/env bash
        set -euo pipefail

        : "${VERSION:?VERSION must be set}"

        for _ in $(seq 1 30); do
            if curl -sf http://localhost:8000/ >/dev/null; then
                break
            fi
            sleep 1
        done

        PAYLOAD=$(curl -s http://localhost:8000/)
        echo "Service responded: ${PAYLOAD}"

        ACTUAL=$(echo "${PAYLOAD}" | jq -r .version)
        if [ "${ACTUAL}" != "${VERSION}" ]; then
            echo "Version mismatch: expected ${VERSION}, got ${ACTUAL}" >&2
            exit 1
        fi

        echo "Smoke test passed: version=${ACTUAL}"
        ```
    - Make the script executable:
        - `chmod +x smoke_test.sh`
- Verify the image builds and runs locally:
    - `docker build --build-arg APP_VERSION=local-1 -t cubiculum-magistri-app:local-1 .`
    - `IMAGE=cubiculum-magistri-app VERSION=local-1 APP_ENV=local docker compose up -d`
    - `curl -s localhost:8000 | jq` should return JSON with `"version": "local-1"` and `"env": "local"`.
    - `VERSION=local-1 ./smoke_test.sh` should print `Smoke test passed: version=local-1`.
    - Tear down: `docker compose down`.

## Part 4 — Write the Jenkinsfile

- Create `Jenkinsfile` at the repository root with **exactly** this content (replace `your-dockerhub-user` with your actual Docker Hub username):
    ```groovy
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
            IMAGE = 'your-dockerhub-user/cubiculum-magistri-app'
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
    ```
- Stage everything and commit on `develop`:
    - `git add .`
    - `git commit -m "initial pipeline"`
    - `git push -u origin develop`
- Create the three downstream branches off `develop` and push them — at this point all four branches contain the same files (including the same `Jenkinsfile`):
    - `git checkout -b testing && git push -u origin testing`
    - `git checkout -b staging && git push -u origin staging`
    - `git checkout -b production && git push -u origin production`
    - `git checkout develop`
- Verify on GitHub that all four branches (`develop`, `testing`, `staging`, `production`) exist and that the `Jenkinsfile` is present on each.

## Part 5 — Configure Jenkins

- In Jenkins, open **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**:
    - Kind: **Username with password**.
    - Username: your Docker Hub username.
    - Password: your Docker Hub access token (not your account password).
    - ID: `dockerhub-creds` (must match the `credentialsId` in the `Jenkinsfile`).
    - Save.
- From the Jenkins dashboard click **New Item**:
    - Name: `cubiculum-magistri-pipeline`.
    - Type: **Multibranch Pipeline**.
    - OK.
- In the job configuration:
    - **Branch Sources → Add source → Git** (or **GitHub** if your Jenkins has the GitHub plugin):
        - Project Repository: `https://github.com/<your-user>/cubiculum-magistri-pipeline.git`.
        - Credentials: add a Git credential if the repo is private; leave empty for a public repo.
    - **Build Configuration**: Mode `by Jenkinsfile`, Script Path `Jenkinsfile`.
    - Save.
- Jenkins will run **Scan Multibranch Pipeline Now** automatically. Verify that all four branches (`develop`, `testing`, `staging`, `production`) appear under the job and that an initial build kicks off for each.

## Part 6 — Run the develop pipeline

- The first scan in Part 5 already triggered a build on `develop`. Open the build for `develop` and confirm that these stages ran in order and all passed:
    - Checkout → Spell check → Lint → Test → Build & push.
- Verify on Docker Hub that the image `your-dockerhub-user/cubiculum-magistri-app:1` now exists.
- Push a trivial change to `develop` to confirm the pipeline re-runs:
    - Edit `app/main.py` and add a comment line at the top.
    - `git add app/main.py && git commit -m "trivial change" && git push origin develop`.
    - In Jenkins, watch the new build run end-to-end and confirm a new tag `:2` appears on Docker Hub.

## Part 7 — Promote a build to testing

- In Jenkins, navigate to `cubiculum-magistri-pipeline → testing`.
- Click **Build with Parameters**.
    - `VERSION`: `1`
    - Click **Build**.
- Watch the build run. The active stages on `testing` are:
    - Checkout → Pull image → Deploy & smoke test.
- The build log should end with `Smoke test passed: version=1`.
- Confirm on the Jenkins agent (or wherever the build ran) that the container has been torn down — `docker compose down` runs in the `post { always }` block.

## Part 8 — Promote to staging and production

- Trigger `cubiculum-magistri-pipeline → staging` with `VERSION=1`:
    - The build will pause at the **Approval** stage with the prompt "Deploy your-dockerhub-user/cubiculum-magistri-app:1 to staging?".
    - Click **Proceed**.
    - Confirm the smoke test passes.
- Trigger `cubiculum-magistri-pipeline → production` with `VERSION=1` and approve in the same way. Confirm the smoke test passes.
- Now demonstrate that the smoke test really verifies the version:
    - Trigger `testing` again with `VERSION=999` (a tag that does not exist on Docker Hub).
    - Confirm the **Pull image** stage fails with a `manifest unknown` error from Docker Hub — the pipeline never reaches the smoke test because the image cannot be pulled.
    - Trigger `testing` once more with `VERSION=1` to leave the branch in a healthy state.

## Part 9 — Cleanup

- On the Jenkins agent, clean up any leftover containers and images:
    - `docker compose down`
    - `docker image prune -f`
- Optionally, delete the multibranch pipeline job in Jenkins (**Configure → Delete Multibranch Pipeline**).
- Optionally, delete the Docker Hub repository for `cubiculum-magistri-app` from the Docker Hub web UI.

## What you should be able to explain at the end

- Why the same `Jenkinsfile` lives on all four branches even though only some stages run on each.
- How the Jenkins built-in `BUILD_NUMBER` becomes the immutable version tag on Docker Hub, and how that same tag is requested back by the `VERSION` parameter on `testing`, `staging` and `production`.
- Why the version is baked into the image at build time (via `--build-arg APP_VERSION`) rather than read from an external source — this is what lets the smoke test verify that the deployed container is exactly the requested version.
- Why staging and production have an explicit manual approval gate but testing does not.
