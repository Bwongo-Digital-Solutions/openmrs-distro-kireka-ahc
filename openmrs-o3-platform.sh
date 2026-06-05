#!/bin/bash

set -e

IMAGE_NAME="yourdockerhubuser/o3-emr"
VERSION_FILE=".version"
K8_NAMESPACE="openmrs"

# Restic config (EDIT THESE)
export RESTIC_REPOSITORY="/backup/restic-repo"
export RESTIC_PASSWORD="change-this-password"
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export AWS_DEFAULT_REGION="us-east-1"

echo "=============================================="
echo " OpenMRS 3 FULL PRODUCTION DEVOPS PLATFORM"
echo " (Docker + CI/CD + K8s + Restic Backup)"
echo "=============================================="

echo "1) Build Distro (Maven)"
echo "2) Build Docker Image"
echo "3) Run Local (Docker Compose)"
echo "4) Push to Docker Hub"
echo "5) Version Bump"
echo "6) Full Release (Build + Tag + Push)"
echo "7) Generate GitHub Actions CI/CD"
echo "8) Generate Docker Compose (Production)"
echo "9) Generate Kubernetes Manifests"
echo "10) Backup DB (MySQL dump)"
echo "11) Restore DB"
echo "12) Restic Init Repo"
echo "13) Restic Backup Full System"
echo "14) Restic Restore"
echo "15) Exit"
echo "=============================================="

read -p "Select option: " OPTION


# -------------------------
# VERSION SYSTEM
# -------------------------
init_version() {
    [ ! -f $VERSION_FILE ] && echo "1.0.0" > $VERSION_FILE
}

version() {
    cat $VERSION_FILE
}

bump_version() {
    init_version
    V=$(version)

    IFS='.' read MAJOR MINOR PATCH <<< "$V"

    echo "Current version: $V"
    echo "1) Patch"
    echo "2) Minor"
    echo "3) Major"
    read -p "Select: " T

    case $T in
        1) PATCH=$((PATCH+1)) ;;
        2) MINOR=$((MINOR+1)); PATCH=0 ;;
        3) MAJOR=$((MAJOR+1)); MINOR=0; PATCH=0 ;;
    esac

    NV="$MAJOR.$MINOR.$PATCH"
    echo $NV > $VERSION_FILE
    echo "New version: $NV"
}


# -------------------------
# BUILD
# -------------------------
build_distro() {
    mvn clean package -DskipTests
}

build_image() {
    V=$(version)

    cd target/distro/web
    docker build -t $IMAGE_NAME:$V .
    docker tag $IMAGE_NAME:$V $IMAGE_NAME:latest
    cd -
}


# -------------------------
# RUN LOCAL
# -------------------------
run_local() {
    docker compose up -d
}


# -------------------------
# PUSH DOCKER
# -------------------------
push_image() {
    V=$(version)

    docker login

    docker push $IMAGE_NAME:$V
    docker push $IMAGE_NAME:latest
}


# -------------------------
# FULL RELEASE PIPELINE
# -------------------------
release() {
    V=$(version)

    echo "🚀 RELEASE $V STARTING"

    build_distro
    build_image

    docker login

    docker push $IMAGE_NAME:$V
    docker push $IMAGE_NAME:latest

    git add .
    git commit -m "release $V" || true
    git tag v$V
    git push origin main
    git push origin v$V

    echo "✅ RELEASE COMPLETE"
}


# -------------------------
# DOCKER COMPOSE PROD
# -------------------------
gen_compose() {
    cat <<EOF > docker-compose.yml
version: "3.9"

services:
  openmrs:
    image: $IMAGE_NAME:latest
    ports:
      - "8080:8080"
    environment:
      DB_HOST: mysql
      DB_USERNAME: openmrs
      DB_PASSWORD: openmrs
      DB_DATABASE: openmrs
    depends_on:
      - mysql

  mysql:
    image: mysql:8
    restart: always
    environment:
      MYSQL_DATABASE: openmrs
      MYSQL_ROOT_PASSWORD: root
    volumes:
      - mysql_data:/var/lib/mysql

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"

volumes:
  mysql_data:
EOF

    echo "docker-compose.yml generated"
}


# -------------------------
# KUBERNETES
# -------------------------
gen_k8s() {
    mkdir -p k8s

    cat <<EOF > k8s/openmrs-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openmrs
  namespace: $K8_NAMESPACE
spec:
  replicas: 3
  selector:
    matchLabels:
      app: openmrs
  template:
    metadata:
      labels:
        app: openmrs
    spec:
      containers:
      - name: openmrs
        image: $IMAGE_NAME:latest
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: mysql
EOF

    cat <<EOF > k8s/openmrs-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: openmrs-service
  namespace: $K8_NAMESPACE
spec:
  type: LoadBalancer
  selector:
    app: openmrs
  ports:
    - port: 80
      targetPort: 8080
EOF

    echo "K8s manifests generated"
}


# -------------------------
# MYSQL BACKUP
# -------------------------
backup_db() {
    mkdir -p backups
    docker exec mysql mysqldump -u root -proot openmrs > backups/openmrs_$(date +%F_%H-%M).sql
    echo "DB backup complete"
}

restore_db() {
    read -p "Backup file: " FILE
    cat $FILE | docker exec -i mysql mysql -u root -proot openmrs
}


# -------------------------
# RESTIC INIT
# -------------------------
restic_init() {
    restic init
    echo "Restic repo initialized"
}


# -------------------------
# RESTIC BACKUP (FULL SYSTEM)
# -------------------------
restic_backup() {
    echo "Starting full backup..."

    restic backup \
        target/distro \
        docker-compose.yml \
        k8s \
        backups

    echo "Restic backup complete"
}


# -------------------------
# RESTIC RESTORE
# -------------------------
restic_restore() {
    echo "Available snapshots:"
    restic snapshots

    read -p "Snapshot ID: " SNAP

    restic restore $SNAP --target ./restore

    echo "Restore complete in ./restore"
}


# -------------------------
# CI/CD GENERATOR
# -------------------------
gen_ci() {
    mkdir -p .github/workflows

    cat <<EOF > .github/workflows/openmrs.yml
name: OpenMRS O3 CI/CD

on:
  push:
    tags:
      - "v*"

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - uses: actions/setup-java@v4
      with:
        distribution: temurin
        java-version: 17

    - run: mvn clean package -DskipTests

    - name: Docker build
      run: |
        cd target/distro/web
        docker build -t \${{ secrets.DOCKER_USERNAME }}/o3-emr:\${GITHUB_REF_NAME} .

    - name: Login
      run: echo "\${{ secrets.DOCKER_PASSWORD }}" | docker login -u "\${{ secrets.DOCKER_USERNAME }}" --password-stdin

    - name: Push
      run: |
        docker push \${{ secrets.DOCKER_USERNAME }}/o3-emr:\${GITHUB_REF_NAME}
        docker tag \${{ secrets.DOCKER_USERNAME }}/o3-emr:\${GITHUB_REF_NAME} \${{ secrets.DOCKER_USERNAME }}/o3-emr:latest
        docker push \${{ secrets.DOCKER_USERNAME }}/o3-emr:latest
EOF

    echo "CI/CD generated"
}


# -------------------------
# MENU
# -------------------------
case $OPTION in
    1) build_distro ;;
    2) build_image ;;
    3) run_local ;;
    4) push_image ;;
    5) bump_version ;;
    6) release ;;
    7) gen_ci ;;
    8) gen_compose ;;
    9) gen_k8s ;;
    10) backup_db ;;
    11) restore_db ;;
    12) restic_init ;;
    13) restic_backup ;;
    14) restic_restore ;;
    15) exit 0 ;;
    *) echo "Invalid option" ;;
esac