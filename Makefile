# Copyright 2016 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Use the native vendor/ dependency system
#export GO15VENDOREXPERIMENT=1
export GO111MODULE := on
export CGO_ENABLED := 0

# Bump this on release
VERSION ?= v0.0.1

GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
BUILD_DIR ?= ./out
ORG := github.com/jimmidyson
REPOPATH ?= $(ORG)/configmap-reload
DOCKER_IMAGE_NAME ?= jimmidyson/configmap-reload
DOCKER_IMAGE_TAG ?= latest

#GOPATH := $(shell pwd)/_gopath

LDFLAGS := -s -w -extldflags '-static'

MKGOPATH := if [ ! -e $(GOPATH)/src/$(ORG) ]; then mkdir -p $(GOPATH)/src/$(ORG) && ln -s -f $(shell pwd) $(GOPATH)/src/$(ORG); fi

SRCFILES := go list  -f '{{join .Deps "\n"}}' ./configmap-reload.go | grep $(REPOPATH) | xargs go list -f '{{ range $$file := .GoFiles }} {{$$.Dir}}/{{$$file}}{{"\n"}}{{end}}'

ALL_ARCH=amd64 arm arm64 ppc64le s390x
ML_PLATFORMS=$(addprefix linux/,$(ALL_ARCH))
ALL_BINARIES ?= $(addprefix out/configmap-reload-, \
									$(addprefix linux-,$(ALL_ARCH)) \
									darwin-amd64 \
									windows-amd64.exe)

DEFAULT_BASEIMAGE_amd64   := busybox
DEFAULT_BASEIMAGE_arm     := armhf/busybox
DEFAULT_BASEIMAGE_arm64   := aarch64/busybox
DEFAULT_BASEIMAGE_ppc64le := ppc64le/busybox
DEFAULT_BASEIMAGE_s390x   := s390x/busybox

BASEIMAGE ?= $(DEFAULT_BASEIMAGE_$(GOARCH))

BINARY=configmap-reload-linux-$(GOARCH)

out/configmap-reload: out/configmap-reload-$(GOOS)-$(GOARCH)
	cp $(BUILD_DIR)/configmap-reload-$(GOOS)-$(GOARCH) $(BUILD_DIR)/configmap-reload

out/configmap-reload-darwin-amd64: configmap-reload.go $(shell $(SRCFILES))
	$(MKGOPATH)
	cd $(GOPATH)/src/$(REPOPATH) && CGO_ENABLED=0 GOARCH=amd64 GOOS=darwin go build --installsuffix cgo -ldflags="$(LDFLAGS)" -a -o $(BUILD_DIR)/configmap-reload-darwin-amd64 configmap-reload.go

out/configmap-reload-linux-arm64: configmap-reload.go $(shell $(SRCFILES))
	GOARCH=arm64 GOOS=linux go build --installsuffix cgo -ldflags="$(LDFLAGS)" -a -o $(BUILD_DIR)/configmap-reload-linux-arm64 configmap-reload.go

out/configmap-reload-linux-amd64: configmap-reload.go $(shell $(SRCFILES))
	$(MKGOPATH)
	cd $(GOPATH)/src/$(REPOPATH) && CGO_ENABLED=0 GOARCH=amd64 GOOS=linux go build --installsuffix cgo -ldflags="$(LDFLAGS)" -a -o $(BUILD_DIR)/configmap-reload-linux-amd64 configmap-reload.go

out/configmap-reload-windows-amd64.exe: configmap-reload.go $(shell $(SRCFILES))
	$(MKGOPATH)
	cd $(GOPATH)/src/$(REPOPATH) && CGO_ENABLED=0 GOARCH=amd64 GOOS=windows go build --installsuffix cgo -ldflags="$(LDFLAGS)" -a -o $(BUILD_DIR)/configmap-reload-windows-amd64.exe configmap-reload.go

.PHONY: cross
cross: out/configmap-reload-linux-amd64 out/configmap-reload-darwin-amd64 out/configmap-reload-windows-amd64.exe

.PHONE: checksum
checksum:
	for f in out/localkube out/configmap-reload-linux-amd64 out/configmap-reload-darwin-amd64 out/configmap-reload-windows-amd64.exe ; do \
		if [ -f "$${f}" ]; then \
			openssl sha256 "$${f}" | awk '{print $$2}' > "$${f}.sha256" ; \
		fi ; \
	done

.PHONY: clean
clean:
	rm -rf $(GOPATH)
	rm -rf $(BUILD_DIR)

.PHONY: docker
docker: out/configmap-reload-$(GOOS)-$(GOARCH) Dockerfile
	docker build --build-arg BASEIMAGE=$(BASEIMAGE) --build-arg BINARY=$(BINARY) -t $(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)-$(GOARCH) .
