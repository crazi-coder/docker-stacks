# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.
.PHONY: docs help test

SHELL:=bash
REGISTRY?=docker.io
OWNER?=abhijo89
NB_USER?="jovyan"
NB_UID?="1000"
NB_GID?="100"
BUILDER_NAME?="Jupyter"
PLATFORM?=linux/amd64,linux/arm64
TAG?=dev#latest

# Function to get directory name from a target name
get_dir_name = $(notdir $1)

# Enable BuildKit for Docker build
export DOCKER_BUILDKIT:=1

# All the images listed in the build dependency order
ALL_IMAGES:= \
	docker-stacks-foundation \
	base-notebook \
	minimal-notebook \
	r-notebook \
	julia-notebook \
	scipy-notebook \
	tensorflow-notebook \
	pytorch-notebook \
	datascience-notebook \
	pyspark-notebook \
	all-spark-notebook



# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help:
	@echo "jupyter/docker-stacks"
	@echo "====================="
	@echo "Replace % with a stack directory name (e.g., make build/minimal-notebook)"
	@echo
	@grep -E '^[a-zA-Z0-9_%/-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'



build/%: DOCKER_BUILD_ARGS?=
build/%: ROOT_CONTAINER?=ubuntu:24.04
build/%: ## build the latest image for a stack using the system's architecture
	@if ! docker buildx ls | grep -qw ${BUILDER_NAME}; then \
		echo "Creating and using builder ${BUILDER_NAME}..."; \
		docker buildx create --use --name ${BUILDER_NAME}; \
	else \
		echo "Using existing builder ${BUILDER_NAME}..."; \
		docker buildx use ${BUILDER_NAME}; \
	fi
	docker buildx build $(DOCKER_BUILD_ARGS) --platform="${PLATFORM}" --tag "$(REGISTRY)/$(OWNER)/$(notdir $@):${TAG}" "./images/$(notdir $@)" --build-arg REGISTRY="$(REGISTRY)" --build-arg OWNER="$(OWNER)" --build-arg TAG="$(TAG)"
	@echo -n "Built image size: "
	@docker images "$(REGISTRY)/$(OWNER)/$(notdir $@):${TAG}" --format "{{.Size}}"

build-all: $(foreach I, $(ALL_IMAGES), build/$(I)) ## build all stacks



check-outdated/%: ## check the outdated mamba/conda packages in a stack and produce a report
	@TEST_IMAGE="$(REGISTRY)/$(OWNER)/$(notdir $@)" pytest tests/docker-stacks-foundation/test_outdated.py
check-outdated-all: $(foreach I, $(ALL_IMAGES), check-outdated/$(I)) ## check all the stacks for outdated packages



cont-stop-all: ## stop all containers
	@echo "Stopping all containers ..."
	-docker stop --time 0 $(shell docker ps --all --quiet) 2> /dev/null
cont-rm-all: ## remove all containers
	@echo "Removing all containers ..."
	-docker rm --force $(shell docker ps --all --quiet) 2> /dev/null
cont-clean-all: cont-stop-all cont-rm-all ## clean all containers (stop + rm)



docs: ## build HTML documentation
	sphinx-build -W --keep-going --color docs/ docs/_build/
linkcheck-docs: ## check broken links
	sphinx-build -W --keep-going --color -b linkcheck docs/ docs/_build/



hook/%: VARIANT?=default
hook/%: ## run post-build hooks for an image
	python3 -m tagging.write_tags_file --short-image-name "$(notdir $@)" --tags-dir /tmp/jupyter/tags/ --registry "$(REGISTRY)" --owner "$(OWNER)" --variant "$(VARIANT)" && \
	python3 -m tagging.write_manifest --short-image-name "$(notdir $@)" --hist-lines-dir /tmp/jupyter/hist_lines/ --manifests-dir /tmp/jupyter/manifests/ --registry "$(REGISTRY)" --owner "$(OWNER)" --variant "$(VARIANT)" && \
	python3 -m tagging.apply_tags --short-image-name "$(notdir $@)" --tags-dir /tmp/jupyter/tags/ --platform "$(shell uname -m)" --variant "$(VARIANT)" --registry "$(REGISTRY)" --owner "$(OWNER)"
hook-all: $(foreach I, $(ALL_IMAGES), hook/$(I)) ## run post-build hooks for all images



img-list: ## list jupyter images
	@echo "Listing $(OWNER) images ..."
	docker images "$(OWNER)/*"
	docker images "*/$(OWNER)/*"
img-rm-dang: ## remove dangling images (tagged None)
	@echo "Removing dangling images ..."
	-docker rmi --force $(shell docker images -f "dangling=true" --quiet) 2> /dev/null
img-rm-jupyter: ## remove jupyter images
	@echo "Removing $(OWNER) images ..."
	-docker rmi --force $(shell docker images --quiet "$(OWNER)/*") 2> /dev/null
	-docker rmi --force $(shell docker images --quiet "*/$(OWNER)/*") 2> /dev/null
img-rm: img-rm-dang img-rm-jupyter ## remove dangling and jupyter images



pull/%: ## pull a jupyter image
	docker pull "$(REGISTRY)/$(OWNER)/$(notdir $@)"
pull-all: $(foreach I, $(ALL_IMAGES), pull/$(I)) ## pull all images
push/%: ## push all tags for a jupyter image
	docker buildx build $(DOCKER_BUILD_ARGS) --platform="${PLATFORM}" --tag "$(REGISTRY)/$(OWNER)/$(call get_dir_name,$@):${TAG}" "./images/$(call get_dir_name,$@)" --build-arg REGISTRY="$(REGISTRY)" --build-arg OWNER="$(OWNER)" --build-arg TAG="$(TAG)" --push
push-all: $(foreach I, $(ALL_IMAGES), push/$(I)) ## push all tagged images



run-shell/%: ## run a bash in interactive mode in a stack
	docker run -it --rm "$(REGISTRY)/$(OWNER)/$(notdir $@)" $(SHELL)
run-sudo-shell/%: ## run bash in interactive mode as root in a stack
	docker run -it --rm --user root "$(REGISTRY)/$(OWNER)/$(notdir $@)" $(SHELL)

test/%: ## run tests against a stack
	python3 -m tests.run_tests --short-image-name "$(notdir $@)" --registry "$(REGISTRY)" --owner "$(OWNER)" --tag "$(TAG)"
test-all: $(foreach I, $(ALL_IMAGES), test/$(I)) ## test all stacks
