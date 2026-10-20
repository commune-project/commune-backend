MYGO_ROOT ?= ../../mygo
BUILD_DIR ?= /tmp/commune-mygo-build
GOCACHE ?= /tmp/commune-mygo-gocache
GOMODCACHE ?= /tmp/commune-mygo-modcache
export GOCACHE GOMODCACHE

.PHONY: compiler generate build test test-postgres smoke-runbook verify-protocol verify clean

compiler:
	mkdir -p "$(BUILD_DIR)"
	cd "$(MYGO_ROOT)" && go build -o "$(abspath $(BUILD_DIR))/mygo" ./cmd/mygo

generate: compiler
	"$(BUILD_DIR)/mygo" sync internal/testsupport
	"$(BUILD_DIR)/mygo" sync internal/infrastructure
	"$(BUILD_DIR)/mygo" sync internal/config
	"$(BUILD_DIR)/mygo" sync internal/auth
	"$(BUILD_DIR)/mygo" sync internal/content
	"$(BUILD_DIR)/mygo" sync internal/storage
	"$(BUILD_DIR)/mygo" sync internal/federation
	"$(BUILD_DIR)/mygo" sync internal/delivery
	"$(BUILD_DIR)/mygo" sync internal/server
	"$(BUILD_DIR)/mygo" sync cmd/commune

build: generate
	go build -o "$(BUILD_DIR)/commune" ./cmd/commune

test: generate
	go test ./...

test-postgres: generate
	bash scripts/test-postgres.sh

smoke-runbook: build
	bash scripts/smoke-runbook.sh

verify-protocol:
	cd docs/protocol/snapshots && sha256sum --check SHA256SUMS

verify: verify-protocol build test-postgres smoke-runbook
	git diff --exit-code -- '**/zz_*.gen.go' '**/zz_*.gen_test.go'

clean:
	rm -f "$(BUILD_DIR)/commune" "$(BUILD_DIR)/mygo"
