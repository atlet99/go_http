.PHONY: help fix fix-all analyze format format-check check check-all test examples example-main example-simple-get example-cancel example-retry example-download example-upload example-top-level-get bump-version tag check-version release

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Files
PUBSPEC := pubspec.yaml
README := README.md

help: ## Show help message with available commands
	@echo "$(GREEN)Available commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'

fix: ## Preview dart fixes (dry-run)
	@echo "$(GREEN)Running dart fix --dry-run...$(NC)"
	@dart fix --dry-run

fix-all: ## Apply all dart fixes and format
	@echo "$(GREEN)Applying dart fixes...$(NC)"
	@dart fix --apply
	@echo "$(GREEN)Formatting code...$(NC)"
	@dart format .

analyze: ## Run dart analyze
	@echo "$(GREEN)Running dart analyze...$(NC)"
	@dart analyze

format: ## Format code with dart format
	@echo "$(GREEN)Formatting code...$(NC)"
	@dart format .

format-check: ## Check code formatting without making changes
	@echo "$(GREEN)Checking code formatting...$(NC)"
	@dart format --set-exit-if-changed .

test: ## Run all tests
	@echo "$(GREEN)Running tests...$(NC)"
	@dart test

check: format-check analyze ## Check formatting and run code analysis

check-all: format-check analyze test ## Full pipeline: formatting → analysis → tests

# Examples
example-post-json: ## Run example/post_json.dart
	@echo "$(GREEN)Running example/post_json.dart...$(NC)"
	@dart run example/post_json.dart

example-simple-get: ## Run example/simple_get.dart
	@echo "$(GREEN)Running example/simple_get.dart...$(NC)"
	@dart run example/simple_get.dart

example-cancel: ## Run example/cancel_request.dart
	@echo "$(GREEN)Running example/cancel_request.dart...$(NC)"
	@dart run example/cancel_request.dart

example-retry: ## Run example/retry_policy.dart
	@echo "$(GREEN)Running example/retry_policy.dart...$(NC)"
	@dart run example/retry_policy.dart

example-download: ## Run example/download_progress.dart
	@echo "$(GREEN)Running example/download_progress.dart...$(NC)"
	@dart run example/download_progress.dart

example-upload: ## Run example/upload_progress.dart
	@echo "$(GREEN)Running example/upload_progress.dart...$(NC)"
	@dart run example/upload_progress.dart

example-top-level-get: ## Run example/top_level_get.dart
	@echo "$(GREEN)Running example/top_level_get.dart...$(NC)"
	@dart run example/top_level_get.dart

example-batch-config: ## Run example/batch_config.dart
	@echo "$(GREEN)Running example/batch_config.dart...$(NC)"
	@dart run example/batch_config.dart

examples: example-simple-get example-post-json example-cancel example-retry example-download example-upload example-top-level-get ## Run all examples

# Versioning
check-version: ## Show current version from pubspec.yaml
	@echo "$(GREEN)Current version:$(NC)"
	@grep '^version:' $(PUBSPEC) | sed 's/version: //'

bump-version: ## Bump patch version (up to 9), then bump minor version
	@echo "$(GREEN)Bumping version...$(NC)"
	@current_version=$$(grep '^version:' $(PUBSPEC) | sed 's/version: //'); \
	if [ -z "$$current_version" ]; then \
		echo "$(RED)Error: failed to find version in $(PUBSPEC)$(NC)"; \
		exit 1; \
	fi; \
	echo "$(YELLOW)Current version: $$current_version$(NC)"; \
	major=$$(echo $$current_version | cut -d. -f1); \
	minor=$$(echo $$current_version | cut -d. -f2); \
	patch=$$(echo $$current_version | cut -d. -f3); \
	if [ $$patch -lt 9 ]; then \
		new_patch=$$((patch + 1)); \
		new_version="$$major.$$minor.$$new_patch"; \
		echo "$(YELLOW)Bumping patch version...$(NC)"; \
	else \
		new_minor=$$((minor + 1)); \
		new_version="$$major.$$new_minor.0"; \
		echo "$(YELLOW)Bumping minor version (patch reached 9)...$(NC)"; \
	fi; \
	echo "$(YELLOW)New version: $$new_version$(NC)"; \
	sed -i '' "s/^version: $$current_version/version: $$new_version/" $(PUBSPEC); \
	sed -i '' "s/go_http: \^$$current_version/go_http: ^$$new_version/" $(README); \
	echo "$(GREEN)✓ Version updated in $(PUBSPEC)$(NC)"; \
	echo "$(GREEN)✓ Version updated in $(README)$(NC)"; \
	echo "$(GREEN)New version: $$new_version$(NC)"

tag: ## Create git tag from pubspec.yaml version and push to origin
	@echo "$(GREEN)Creating tag...$(NC)"
	@version=$$(grep '^version:' $(PUBSPEC) | sed 's/version: //'); \
	if [ -z "$$version" ]; then \
		echo "$(RED)Error: failed to find version in $(PUBSPEC)$(NC)"; \
		exit 1; \
	fi; \
	tag_name="v$$version"; \
	echo "$(YELLOW)Creating tag: $$tag_name$(NC)"; \
	if git rev-parse "$$tag_name" >/dev/null 2>&1; then \
		echo "$(RED)Tag $$tag_name already exists!$(NC)"; \
		exit 1; \
	fi; \
	git tag -a "$$tag_name" -m "[UPD] - release $$version"; \
	echo "$(GREEN)✓ Tag $$tag_name created$(NC)"; \
	echo "$(YELLOW)Pushing tag to origin...$(NC)"; \
	git push origin "$$tag_name"; \
	echo "$(GREEN)✓ Tag $$tag_name pushed to origin$(NC)"

release: bump-version tag ## Bump version and create tag (full release workflow)

