.PHONY: help deps setup build assets test lint format clean run dev server

# Default target
help:
	@echo "EthProofs Client - Available commands:"
	@echo ""
	@echo "  Setup & Build:"
	@echo "    make deps      - Install Elixir dependencies"
	@echo "    make setup     - Full setup (deps + assets)"
	@echo "    make build     - Compile the project"
	@echo "    make assets    - Build frontend assets (CSS/JS)"
	@echo ""
	@echo "  Development:"
	@echo "    make dev       - Start in development mode with IEx"
	@echo "    make server    - Start the Phoenix server"
	@echo "    make run       - Alias for 'make server'"
	@echo ""
	@echo "  Quality:"
	@echo "    make test      - Run all tests"
	@echo "    make lint      - Run Credo linter"
	@echo "    make format    - Format code with mix format"
	@echo "    make check     - Run format check, lint, and tests"
	@echo ""
	@echo "  Cleanup:"
	@echo "    make clean     - Remove build artifacts"
	@echo ""
	@echo "  Environment Variables (for run/dev/server):"
	@echo "    ETH_RPC_URL              - Ethereum JSON-RPC endpoint (required)"
	@echo "    ELF_PATH                 - Path to guest program ELF (required)"
	@echo "    ETHPROOFS_RPC_URL        - EthProofs API URL (optional)"
	@echo "    ETHPROOFS_API_KEY        - EthProofs API key (optional)"
	@echo "    ETHPROOFS_CLUSTER_ID     - EthProofs cluster ID (optional)"
	@echo "    LOG_LEVEL                - Log level: debug|info|warning|error (default: info)"

# Install dependencies
deps:
	mix deps.get

# Full setup: deps + compile + assets
setup: deps
	mix compile
	mix assets.setup
	mix assets.build
	@echo ""
	@echo "Setup complete! Run 'make dev' to start the application."

# Compile the project
build:
	mix compile

# Build frontend assets
assets:
	mix assets.build

# Run tests
test:
	mix test

# Run Credo linter
lint:
	mix credo --strict

# Format code
format:
	mix format

# Check formatting (CI mode)
format-check:
	mix format --check-formatted

# Run all checks (for CI or pre-commit)
check: format-check lint test

# Start Phoenix server
server:
	mix phx.server

# Start in development mode with IEx shell
dev:
	iex -S mix phx.server

# Alias for server
run: server

# Clean build artifacts
clean:
	rm -rf _build deps priv/static/assets
	mix clean

# Production build
prod-build:
	MIX_ENV=prod mix compile
	MIX_ENV=prod mix assets.deploy
