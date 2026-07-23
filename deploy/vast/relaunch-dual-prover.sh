#!/usr/bin/env bash
# Entrypoint for the ethrex-ethproofs DUAL prover (ZisK + Airbender) on a vast.ai instance.
# Runs in the FOREGROUND under supervisor (autorestart handles crash recovery).
# Secrets and endpoints come from ~/.ethproofs.env (chmod 600) — see ethproofs.env.example.
set -uo pipefail

export HOME="${HOME:-/root}"
export PATH="/usr/local/cuda/bin:$HOME/.asdf/shims:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
[ -f "$HOME/.asdf/asdf.sh" ] && . "$HOME/.asdf/asdf.sh"
export PATH="$PATH:$HOME/.zisk/bin:$HOME/.cargo/bin"

REPO_DIR="$HOME/ethrex-ethproofs"
cd "$REPO_DIR" || { echo "FATAL: $REPO_DIR missing" >&2; exit 1; }

# --- Secrets / endpoints (required: ETH_RPC_URL; recommended: ETHPROOFS_API_KEY) ---
if [ -f "$HOME/.ethproofs.env" ]; then
  set -a; . "$HOME/.ethproofs.env"; set +a
else
  echo "FATAL: $HOME/.ethproofs.env missing (see deploy/vast/ethproofs.env.example)" >&2
  exit 1
fi
[ -n "${ETH_RPC_URL:-}" ] || { echo "FATAL: ETH_RPC_URL not set in ~/.ethproofs.env" >&2; exit 1; }

# --- Prover config (guest artifacts are tracked in this repo) ---
export LOG_LEVEL="${LOG_LEVEL:-debug}"
export ZISK_ELF_PATH="$REPO_DIR/ethrex_guest_programs/ethrex-c5de3bd-zisk-0.16.1-guest.elf"
export ZISK_CLUSTER_ID="${ZISK_CLUSTER_ID:-3}"
export AIRBENDER_BIN_PATH="$REPO_DIR/ethrex_guest_programs/airbender-0f97ca8f/app.bin"
export AIRBENDER_CLUSTER_ID="${AIRBENDER_CLUSTER_ID:-4}"
export PROVING_TIMEOUT_SECONDS="${PROVING_TIMEOUT_SECONDS:-1200}"

if [ -n "${ETHPROOFS_API_KEY:-}" ]; then
  export ETHPROOFS_RPC_URL="${ETHPROOFS_RPC_URL:-https://ethproofs.org/api/v0}"
  echo "[relaunch] PROD mode -> $ETHPROOFS_RPC_URL (api_key_len=${#ETHPROOFS_API_KEY})"
else
  # NOTE: on the airbender-dual-prover branch the Prover GenServer currently CRASHES on every
  # 100th block when the key is absent (rpc.ex guard clauses fall through). Local-test only.
  echo "[relaunch] WARNING: no ETHPROOFS_API_KEY - submissions disabled (known crash bug, see README)"
fi

# --- Sanity checks on required artifacts ---
for f in "$ZISK_ELF_PATH" "$AIRBENDER_BIN_PATH" "$HOME/.zisk/provingKey"; do
  [ -e "$f" ] || { echo "FATAL: missing required artifact: $f" >&2; exit 1; }
done

# Pre-warm the ~50G ZisK proving key into page cache so the first proof isn't I/O-bound
# (vast.ai overlay disks read slowly cold; instances with large RAM hold the whole key).
( find "$HOME/.zisk/provingKey" -type f -exec cat {} + > /dev/null 2>&1 & )

echo "[relaunch] ZisK(cluster=$ZISK_CLUSTER_ID, elf=$(basename "$ZISK_ELF_PATH")) + Airbender(cluster=$AIRBENDER_CLUSTER_ID)"
exec mix phx.server
