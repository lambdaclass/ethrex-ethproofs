#!/usr/bin/env bash
# One-shot rebuild of the ethrex-ethproofs dual prover on a FRESH vast.ai instance.
#
# vast.ai instances have NO persistent storage unless a volume is attached: a "recycle"
# or "destroy" wipes the container filesystem. This script rebuilds everything from
# public sources + this repo. Total time ~2h, dominated by the ZisK proving-key
# download (~50 GB) and the GPU builds.
#
# Prerequisites:
#   - vast.ai instance: RTX 5090 class GPU (32 GB VRAM), >=64 GB RAM, >=200 GB disk,
#     CUDA 13.x base image (nvcc preinstalled at /usr/local/cuda).
#   - This repo cloned at $HOME/ethrex-ethproofs (branch with deploy/vast + guest artifacts).
#   - ~/.ethproofs.env created from deploy/vast/ethproofs.env.example (do this BEFORE
#     the final supervisor step, or restart the service after creating it).
#
# Usage: bash $HOME/ethrex-ethproofs/deploy/vast/bootstrap.sh 2>&1 | tee $HOME/bootstrap.log
#
# GPU arch overrides (defaults target RTX 5090 / Blackwell):
#   CUDA_ARCH   for the ZisK build       (default sm_120)
#   CUDAARCHS   for cargo-airbender      (default 100; 89=RTX4090, 90=H100, or "native")
set -euo pipefail

REPO_DIR="$HOME/ethrex-ethproofs"
ZISK_TAG="v0.16.1"
ZISK_PK_URL="https://storage.googleapis.com/zisk-setup/zisk-provingkey-0.16.0.tar.gz"
RUST_NIGHTLY="nightly-2026-02-10"
ZISK_ELF="$REPO_DIR/ethrex_guest_programs/ethrex-c5de3bd-zisk-0.16.1-guest.elf"
: "${CUDA_ARCH:=sm_120}"
: "${CUDAARCHS:=100}"

phase() { echo; echo "########## $(date -u +%T) $* ##########"; }

[ -d "$REPO_DIR" ] || { echo "FATAL: clone this repo at $REPO_DIR first" >&2; exit 1; }
[ -x /usr/local/cuda/bin/nvcc ] || { echo "FATAL: CUDA toolkit not found at /usr/local/cuda" >&2; exit 1; }
export PATH="/usr/local/cuda/bin:$PATH"

phase "1/9 apt build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential clang libclang-dev nasm git curl jq xz-utils \
  pkg-config libssl-dev libomp-dev libgmp-dev nlohmann-json3-dev protobuf-compiler \
  uuid-dev libgrpc++-dev libsecp256k1-dev libsodium-dev libpqxx-dev libopenmpi-dev \
  openmpi-bin libgfortran5 libgomp1 autoconf automake m4 libncurses-dev unzip rsync tmux

phase "2/9 Rust toolchains"
if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
fi
source "$HOME/.cargo/env"
rustup toolchain install "$RUST_NIGHTLY"
rustup component add rust-src llvm-tools-preview --toolchain "$RUST_NIGHTLY"
cargo install cargo-binutils

phase "3/9 ZisK $ZISK_TAG from source with GPU support (ziskup installs CPU-only builds - do not use it)"
if [ ! -d "$HOME/zisk" ]; then git clone https://github.com/0xPolygonHermez/zisk "$HOME/zisk"; fi
cd "$HOME/zisk" && git checkout "$ZISK_TAG"
CUDA_ARCH="$CUDA_ARCH" cargo build --release --features gpu
mkdir -p "$HOME/.zisk/bin"
cp target/release/{cargo-zisk,ziskemu,riscv2zisk,zisk-coordinator,zisk-worker,libzisk_witness.so,libziskclib.a} "$HOME/.zisk/bin/"
mkdir -p "$HOME/.zisk/zisk/emulator-asm"
cp -r ./emulator-asm/src "$HOME/.zisk/zisk/emulator-asm/"
cp ./emulator-asm/Makefile "$HOME/.zisk/zisk/emulator-asm/"
cp -r ./lib-c "$HOME/.zisk/zisk/"
export PATH="$PATH:$HOME/.zisk/bin"
cargo-zisk sdk install-toolchain

phase "4/9 ZisK proving key (~50 GB download; skipped if already present)"
if [ ! -d "$HOME/.zisk/provingKey" ]; then
  cd "$HOME/.zisk" && curl -s "$ZISK_PK_URL" | tar -xz
fi
cargo-zisk check-setup --proving-key "$HOME/.zisk/provingKey" -a

phase "5/9 ROM setup for the production guest ELF"
cargo-zisk rom-setup -e "$ZISK_ELF"

phase "6/9 cargo-airbender (GPU)"
if [ ! -d /tmp/airbender-platform ]; then
  git clone --depth 1 https://github.com/matter-labs/airbender-platform.git /tmp/airbender-platform
fi
cd /tmp/airbender-platform
CUDAARCHS="$CUDAARCHS" cargo "+$RUST_NIGHTLY" install --path crates/cargo-airbender

phase "7/9 Erlang/Elixir via asdf"
if [ ! -d "$HOME/.asdf" ]; then
  git clone https://github.com/asdf-vm/asdf.git "$HOME/.asdf" --branch v0.15.0
fi
. "$HOME/.asdf/asdf.sh"
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git || true
asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git || true
export KERL_CONFIGURE_OPTIONS="--without-javac --without-wx --without-odbc"
asdf install erlang 28.3 && asdf global erlang 28.3
asdf install elixir 1.19.4 && asdf global elixir 1.19.4

phase "8/9 build the app (deps + assets + Rustler input-generator NIF)"
cd "$REPO_DIR"
export PATH="$HOME/.asdf/shims:$PATH"
mix local.hex --force && mix local.rebar --force
make setup

phase "9/9 install service (supervisor) + input-cleanup cron"
cp "$REPO_DIR/deploy/vast/ethproofs-prover.supervisor.conf" /etc/supervisor/conf.d/ethproofs-prover.conf
cp "$REPO_DIR/deploy/vast/ethproofs-cleanup.cron" /etc/cron.d/ethproofs-cleanup
chmod 644 /etc/cron.d/ethproofs-cleanup
chmod +x "$REPO_DIR/deploy/vast/relaunch-dual-prover.sh"
if [ ! -f "$HOME/.ethproofs.env" ]; then
  echo "WARNING: $HOME/.ethproofs.env missing - create it from deploy/vast/ethproofs.env.example,"
  echo "         then: supervisorctl restart ethproofs-prover"
fi
supervisorctl reread && supervisorctl update

echo
echo "BOOTSTRAP DONE. Verify with: supervisorctl status ethproofs-prover"
echo "Health = prover-service.log shows 'Latest block: N. Next multiple of 100: M'"
