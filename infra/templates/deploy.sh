#!/bin/bash
# /opt/notes/deploy.sh - pull and (re)start the containers at a given image tag.
# Called by user-data at first boot and by the CI/CD pipeline (via SSM Run Command).
#   usage: deploy.sh [image-tag]     (default: latest)
set -euo pipefail

TAG="${1:-latest}"
cd /opt/notes

# One deploy at a time per host: the first-boot retry loop and a pipeline deploy
# (or two pipeline runs) must not recreate each other's containers mid-rollout.
exec 9>/var/lock/notes-deploy.lock
flock -w 600 9
# shellcheck disable=SC1091
source ./registry.conf # REGISTRY, WEB_REPO, APP_REPO, AWS_REGION (non-secret)

echo "[deploy] $(date -Is) deploying tag ${TAG}"

# Point the compose env file at the requested images
sed -i \
  -e "s|^WEB_IMAGE=.*|WEB_IMAGE=${WEB_REPO}:${TAG}|" \
  -e "s|^APP_IMAGE=.*|APP_IMAGE=${APP_REPO}:${TAG}|" \
  .env

# Short-lived (12h) ECR token obtained with the instance role - no stored credentials
aws ecr get-login-password --region "${AWS_REGION}" |
  docker login --username AWS --password-stdin "${REGISTRY}"

docker compose pull
docker compose up -d --remove-orphans --wait --wait-timeout 120
docker image prune -f >/dev/null

echo "[deploy] done - running containers:"
docker compose ps
