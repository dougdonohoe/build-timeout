# Makefile for slow build issue
#

# Root artifact registry and repository
GCP_PROJECT ?= my-project
REPO ?= slow-build-test
ARTIFACT_REGISTRY ?= us-central1-docker.pkg.dev/$(GCP_PROJECT)

# Setup repo paths
DOCKER_REPO = $(ARTIFACT_REGISTRY)/$(REPO)
CACHE_ROOT = $(DOCKER_REPO)/cache

# define docker to run using BUILDKIT features
DOCKER = DOCKER_BUILDKIT=1 docker

# If DRYRUN set, just echo docker commands
ifdef DRYRUN
DOCKER := echo "[dry-run] $(DOCKER)"
endif

# Platforms defaults to amd64 and arm64, but one can override at runtime (e.g., PLATFORMS=linux/amd64 make xxx)
PLATFORMS ?= linux/amd64,linux/arm64

# docker buildx name
BUILDER ?= builder-local

# Alpine
ALPINE_VERSION := 3.15

# Image used to do cloud builds - version should be kept in sync with docker-build.yaml
CLOUDBUILD_NAME = build/cloud-build:alpine$(ALPINE_VERSION)
CLOUDBUILD_TAG = $(DOCKER_REPO)/$(CLOUDBUILD_NAME)

# Runtime info
RUNTIME_VERSION = 4
RUNTIME_NAME = build/slow-build:$(RUNTIME_VERSION)
RUNTIME_TAG = $(DOCKER_REPO)/$(RUNTIME_NAME)
RUNTIME_CACHE_TAG = $(CACHE_ROOT)/$(RUNTIME_NAME)

# Auto-install crane tool if not already installed
$(GOPATH)/bin/crane:
	@echo "'crane' not found, attempting to install..."
	go install github.com/google/go-containerregistry/cmd/crane@latest

## thirdparty: copy thirdparty images from official sources to our artifactory
thirdparty: $(GOPATH)/bin/crane
	crane copy docker.io/alpine:$(ALPINE_VERSION) $(DOCKER_REPO)/thirdparty/alpine:$(ALPINE_VERSION)

## build-publish-cloud-builder: build + push the image used in GCP cloud builds (see _CLOUDBUILD_IMAGE in docker-build.yaml).
build-publish-cloud-builder:
	$(DOCKER) build --file Dockerfile-cloud-builder --pull \
		--platform linux/amd64 \
		--build-arg DOCKER_REPO=$(DOCKER_REPO) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--tag $(CLOUDBUILD_TAG) .
	$(DOCKER) push $(CLOUDBUILD_TAG)

# common setup for buildx tasks
buildx-setup:
	$(DOCKER) buildx ls
	@if ! $(DOCKER) buildx inspect --builder $(BUILDER) > /dev/null 2>&1; then \
  		echo "Creating new builder '$(BUILDER)'"; \
  		$(DOCKER) buildx create --name $(BUILDER); \
	else \
		echo "Using existing builder $(BUILDER)"; \
	fi

## buildx-publish-runtime-sleep: build and publish a multi-architecture runtime image (amd64|arm64) with sleep
# (this fails)
buildx-publish-runtime-sleep: buildx-setup
	@echo '=> Build and publish multi-arch image $(RUNTIME_TAG)...'
	$(DOCKER) buildx build --file Dockerfile-runtime-sleep \
		--platform $(PLATFORMS) \
		--builder $(BUILDER) \
		--progress plain \
		--build-arg DOCKER_REPO=$(DOCKER_REPO) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--cache-from type=registry,ref=$(RUNTIME_CACHE_TAG)-sleep \
		--cache-to type=registry,ref=$(RUNTIME_CACHE_TAG)-sleep,mode=max \
		--pull --push --tag $(RUNTIME_TAG)-sleep .

## buildx-publish-runtime-sleep-workaround: build and publish a multi-architecture runtime image (amd64|arm64) with sleep,
# but this time do build w/out --push/--cache-to, then stop builder, then build again (this works)
buildx-publish-runtime-sleep-workaround: buildx-setup
	@echo '=> Build and publish multi-arch image $(RUNTIME_TAG)...'
	$(DOCKER) buildx build --file Dockerfile-runtime-sleep \
		--platform $(PLATFORMS) \
		--builder $(BUILDER) \
		--progress plain \
		--build-arg DOCKER_REPO=$(DOCKER_REPO) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--cache-from type=registry,ref=$(RUNTIME_CACHE_TAG)-sleep-workaround \
		--pull --tag $(RUNTIME_TAG)-sleep-workaround .
	$(DOCKER) buildx stop $(BUILDER) # <--- key to the whole workaround
	$(DOCKER) buildx build --file Dockerfile-runtime-sleep \
		--platform $(PLATFORMS) \
		--builder $(BUILDER) \
		--progress plain \
		--build-arg DOCKER_REPO=$(DOCKER_REPO) \
		--build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
		--cache-from type=registry,ref=$(RUNTIME_CACHE_TAG)-sleep-workaround \
		--cache-to type=registry,ref=$(RUNTIME_CACHE_TAG)-sleep-workaround,mode=max \
		--pull --push --tag $(RUNTIME_TAG)-sleep-workaround .

## cloud-build-timeout: run cloud build timeout
cloud-build-timeout:
	gcloud builds submit --region=global --config docker-build.yaml \
 		--substitutions=_REPO=$(REPO),_CLOUDBUILD_IMAGE=$(CLOUDBUILD_TAG),_TARGET=buildx-publish-runtime-sleep \
		.

## cloud-build-timeout-workaround: run cloud build timeout with workaround
cloud-build-timeout-workaround:
	gcloud builds submit --region=global --config docker-build.yaml \
 		--substitutions=_REPO=$(REPO),_CLOUDBUILD_IMAGE=$(CLOUDBUILD_TAG),_TARGET=buildx-publish-runtime-sleep-workaround \
		.
