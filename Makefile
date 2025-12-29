# Darkstar - Backend-less Internet Health Monitoring
# 🚀 The Dopest Makefile Ever

# Configuration
PROJECT_NAME := darkstar
BUILD_MODE   := ReleaseSafe
ZIG          := zig
PREFIX       ?= /usr/local
BINDIR       ?= $(PREFIX)/bin

# Colors
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
BLUE   := $(shell tput -Txterm setaf 4)
RESET  := $(shell tput -Txterm sgr0)

.PHONY: all build clean install uninstall run test help dep-check

all: help

## 📦 Build the binary
build: dep-check
	@echo "$(BLUE)🏗️  Building $(PROJECT_NAME) ($(BUILD_MODE))...$(RESET)"
	$(ZIG) build -Doptimize=$(BUILD_MODE)
	@echo "$(GREEN)✅ Build successful! Binary is at ./zig-out/bin/$(PROJECT_NAME)$(RESET)"

## 🧹 Clean up build artifacts
clean:
	@echo "$(YELLOW)🧹 Cleaning cache and artifacts...$(RESET)"
	rm -rf zig-out zig-cache .zig-cache
	@echo "$(GREEN)✨ Sparkly clean!$(RESET)"

## 🚀 install the binary to your path (Global)
install: build
	@echo "$(BLUE)🚀 Installing to $(BINDIR)...$(RESET)"
	@mkdir -p $(BINDIR)
	install -m 755 zig-out/bin/$(PROJECT_NAME) $(BINDIR)/$(PROJECT_NAME)
	@echo "$(GREEN)🎉 Installed! Run '$(PROJECT_NAME) health 3333' to test.$(RESET)"

## 👤 install the binary to local user (~/.local/bin)
install-local:
	@$(MAKE) install BINDIR=$(HOME)/.local/bin


## 🗑️  Uninstall the binary (Global)
uninstall:
	@echo "$(YELLOW)🗑️  Uninstalling from $(BINDIR)...$(RESET)"
	rm -f $(BINDIR)/$(PROJECT_NAME)
	@echo "$(GREEN)✌️  Uninstalled.$(RESET)"

## 👤 Uninstall from local user (~/.local/bin)
uninstall-local:
	@$(MAKE) uninstall BINDIR=$(HOME)/.local/bin

## 🏃 Run the health check (dev mode)
run:
	$(ZIG) build run -- health 3333

## 🧪 Run tests
test:
	@echo "$(BLUE)🧪 Running tests...$(RESET)"
	$(ZIG) build test
	@echo "$(GREEN)✅ All tests passed!$(RESET)"

## 👷 Check dependencies
dep-check:
	@command -v $(ZIG) >/dev/null 2>&1 || { echo >&2 "$(YELLOW)⚠️  Zig is not installed. Please install Zig 0.14.1+$(RESET)"; exit 1; }

## ❓ Show help
help:
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "  ${YELLOW}%-20s${RESET} ${GREEN}%s${RESET}\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)
