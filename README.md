# ethrex-ethproofs

EthProofs client written in Elixir, powered by ethrex.

## 🚀 Getting Started

> [!WARNING]
> The current version of this project only supports single-GPU ZisK proving using the `cargo-zisk prove` command under-the-hood. Support for distributed proving and server mode will be added in future releases.

### Requirements

- Erlang 28.2 (we recommend using [asdf](https://asdf-vm.com/), see instructions below. Alternatively, you can follow the [official instructions](https://www.erlang.org/downloads))
- Elixir 1.19.4-opt-28 (we recommend using [asdf](https://asdf-vm.com/), see instructions below. Alternatively, you can follow the [official instructions](https://elixir-lang.org/install.html))
- ZisK toolchain v0.14.0 (see instructions below)
- CUDA Toolkit 12.9 or 13.0 (install via [NVIDIA's guide](https://developer.nvidia.com/cuda-toolkit-archive))

### How to run

#### 0. (Optional) Install Erlang and Elixir using asdf 1.18.0

```shell
# Install Erlang
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
asdf install erlang 28.3
asdf set --home erlang 28.3
asdf current erlang

# Install Elixir
asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
asdf install elixir 1.19.4
asdf set --home elixir 1.19.4
asdf current elixir


# Copy the following lines into your ~/.bashrc or ~/.zshrc depending on your shell
export PATH="$HOME/.asdf/shims:$PATH"
. $HOME/.asdf/asdf.sh

# Then, reload your shell configuration
source ~/.bashrc # or source ~/.zshrc

asdf reshim
```

#### 1. Install ZisK GPU toolchain

> [!CAUTION]
> `export CUDA_ARCH=sm_86` if you have an NVIDIA RTX 30 series GPU.

1. Ensure you have the necessary dependencies and hardware (see [ZisK's installation guide](https://0xpolygonhermez.github.io/zisk/getting_started/installation.html#installation-guide)).
2. Install the ZisK toolchain for GPU proving (if you have any troubles during installation, please refer to the [ZisK installation guide](https://0xpolygonhermez.github.io/zisk/getting_started/installation.html#installation-guide)):

    ```bash
    # Clone the ZisK repository:
    git clone https://github.com/0xPolygonHermez/zisk
    cd zisk
    git checkout v0.14.0

    # Build ZisK tools:
    cargo build --release --features gpu

    # Copy the tools to ~/.zisk/bin directory:
    mkdir -p $HOME/.zisk/bin
    LIB_EXT=$([[ "$(uname)" == "Darwin" ]] && echo "dylib" || echo "so")
    cp target/release/cargo-zisk target/release/ziskemu target/release/riscv2zisk target/release/zisk-coordinator target/release/zisk-worker target/release/libzisk_witness.$LIB_EXT target/release/libziskclib.a $HOME/.zisk/bin

    # Copy required files for assembly rom setup (this is only needed on Linux x86_64):
    mkdir -p $HOME/.zisk/zisk/emulator-asm
    cp -r ./emulator-asm/src $HOME/.zisk/zisk/emulator-asm
    cp ./emulator-asm/Makefile $HOME/.zisk/zisk/emulator-asm
    cp -r ./lib-c $HOME/.zisk/zisk

    # Add ~/.zisk/bin to your system PATH:
    PROFILE=$([[ "$(uname)" == "Darwin" ]] && echo ".zshenv" || echo ".bashrc")
    echo >>$HOME/$PROFILE && echo "export PATH=\"\$PATH:$HOME/.zisk/bin\"" >> $HOME/$PROFILE
    source $HOME/$PROFILE
    ```

#### 2. Generate the ROM setup from the guest program

1. Download the GPU proving key:

    ```bash
    wget https://storage.googleapis.com/zisk-setup/zisk-provingkey-0.14.0.tar.gz

    tar -xzf zisk-provingkey-0.14.0.tar.gz

    mv provingKey $HOME/.zisk/provingKey
    ```

2. Run the following in the root of the project to generate the const tree files:

    ```bash
    cargo-zisk check-setup --proving-key $HOME/.zisk/provingKey -a
    ```

3. Run the following in the root of the project to generate the ROM setup:

    ```bash
    cargo-zisk rom-setup -e ethrex_guest_programs/ethrex-24d4b6404-zisk-0.14.0-guest.elf
    ```

#### 3. Run the EthProofs client application

In a terminal, run the following from the root of the project:

```bash
LOG_LEVEL=debug \
ETHPROOFS_API_KEY=<ETHPROOFS_API_KEY> \
ETHPROOFS_RPC_URL=<ETHPROOFS_RPC_URL> \
ETHPROOFS_CLUSTER_ID=<ETHPROOFS_CLUSTER_ID> \
ETH_RPC_URL=<ETH_RPC_URL> \
ELF_PATH=<ELF_PATH> \
iex -S mix
```

> [!NOTE]
>
> - Replace `<ETHPROOFS_API_TOKEN>` with your EthProofs API token.
> - Replace `<ETHPROOFS_API_URL>` with your EthProofs API (e.g. <https://staging--ethproofs.netlify.app/api/v0>).
> - Replace `<ETHPROOFS_CLUSTER_ID>` with your EthProofs cluster ID.
> - Replace `<RPC_URL>` with your Ethereum Mainnet node HTTP JSON-RPC URL.
> - Remove the `LOG_LEVEL=debug` part if you don't want debug logs (they're useful and not too verbose though).
> - Make sure the `ELF_PATH` points to the correct guest program ELF file. You can either generate the ELF file yourself from the [ethrex repository](https://github.com/lambdaclass/ethrex) by running `cargo c -r -p ethrex-prover -F zisk` from the root and getting the file generated in `crates/l2/prover/src/guest_program/src/zisk/target/riscv64ima-zisk-zkvm-elf/release/zkvm-zisk-program`, or download it from the [releases page](https://github.com/lambdaclass/ethrex/releases).
> - To do a quick non-proving run, set `ZISK_ACTION=execute`. This uses `cargo-zisk execute` under the hood and skips proof reporting, which is useful for testing when proving hardware (e.g. a high-end GPU) is unavailable.

> [!TIP]
> If you want to run the EthProofs client without sending requests to the EthProofs API (for testing purposes), you do this by not passing the `ETHPROOFS_` environment variables.

#### Troubleshooting

> [!NOTE]
> This is a placeholder for future troubleshooting tips. Please report any issues you encounter while running the integration tests to help us improve this section.

## 📖 Documentation

### Architecture Overview

The EthProofs client is built as an OTP application with a supervision tree that manages two main GenServer processes:

```
EthProofsClient.Supervisor (strategy: :rest_for_one)
├── EthProofsClient.TaskSupervisor (Task.Supervisor)
├── EthProofsClient.Prover (GenServer)
└── EthProofsClient.InputGenerator (GenServer)
```

#### Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│ Ethereum Network                                                    │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ eth_getBlockByNumber
                               │ debug_executionWitness
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│ InputGenerator                                                      │
│  • Polls latest block every 2 seconds                              │
│  • Triggers on blocks that are multiples of 100                    │
│  • Fetches block data + execution witness via RPC                  │
│  • Calls Rust NIF to generate serialized input (.bin file)         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ Prover.prove(block_number, input_path)
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Prover                                                              │
│  • Manages queue of blocks to prove                                │
│  • Spawns cargo-zisk process via Erlang Port                       │
│  • Monitors proving progress and handles crashes                   │
│  • Reads proof artifacts (result.json, proof.bin)                  │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ POST /proofs
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│ EthProofs API                                                       │
│  • Receives proof status updates (queued → proving → proved)       │
│  • Stores proof data for verification                              │
└─────────────────────────────────────────────────────────────────────┘
```

### Components

#### InputGenerator

A GenServer that monitors the Ethereum chain and generates ZK proof inputs.

**State Machine:**
- `:idle` - No generation in progress, ready to process next item
- `{:generating, block_number, task_ref}` - Currently generating input for a block

**Behavior:**
- Polls `eth_blockNumber` every 2 seconds
- When a block number is a multiple of 100, queues it for input generation
- Spawns supervised tasks via `Task.Supervisor.async_nolink`
- Deduplicates requests using O(1) MapSet lookups
- Handles task crashes gracefully via `{:DOWN, ...}` messages

**Public API:**
```elixir
# Manually trigger input generation for a specific block
EthProofsClient.InputGenerator.generate(block_number)

# Get current status (useful for debugging)
EthProofsClient.InputGenerator.status()
# => %{status: :idle, queue_length: 0, queued_blocks: [], processed_count: 5}
# => %{status: {:generating, 21500000}, queue_length: 2, queued_blocks: [21500100, 21500200], processed_count: 3}
```

#### Prover

A GenServer that manages a queue of blocks to prove using cargo-zisk.

**State Machine:**
- `:idle` - No proof in progress, ready to process next item
- `{:proving, block_number, port}` - Currently proving a block

**Behavior:**
- Receives proof requests from InputGenerator
- Manages sequential proof generation (one at a time due to GPU constraints)
- Spawns `cargo-zisk prove` as an Erlang Port for external process management
- Reports proof status to EthProofs API (queued → proving → proved)
- Handles prover crashes (OOM, GPU errors) gracefully
- Deduplicates requests using O(1) MapSet lookups

**Public API:**
```elixir
# Manually trigger proving for a specific block (input must already exist)
EthProofsClient.Prover.prove(block_number, "/path/to/input.bin")

# Get current status (useful for debugging)
EthProofsClient.Prover.status()
# => %{status: :idle, queue_length: 0, queued_blocks: []}
# => %{status: {:proving, 21500000}, queue_length: 2, queued_blocks: [21500100, 21500200]}
```

#### TaskSupervisor

A `Task.Supervisor` that supervises async tasks spawned by InputGenerator.

**Benefits:**
- Tasks are not linked to the GenServer (crashes don't propagate)
- Visible in `:observer` for debugging
- Proper OTP supervision structure

#### RPC Modules

- `EthProofsClient.EthRpc` - Ethereum JSON-RPC client (Tesla-based)
  - `get_latest_block_number/0`
  - `get_block_by_number/3`
  - `debug_execution_witness/2`

- `EthProofsClient.Rpc` - EthProofs API client (Tesla-based)
  - `queued_proof/1` - Report proof as queued
  - `proving_proof/1` - Report proof as in progress
  - `proved_proof/5` - Submit completed proof

### Configuration

| Environment Variable | Required | Description |
|---------------------|----------|-------------|
| `ETH_RPC_URL` | Yes | Ethereum JSON-RPC endpoint URL |
| `ELF_PATH` | Yes | Path to the ZisK guest program ELF binary |
| `ETHPROOFS_RPC_URL` | No | EthProofs API base URL |
| `ETHPROOFS_API_KEY` | No | EthProofs API authentication token |
| `ETHPROOFS_CLUSTER_ID` | No | EthProofs cluster identifier |
| `ZISK_ACTION` | No | ZisK action (`prove` or `execute`, default: `prove`) |
| `SLACK_WEBHOOK` | No | Slack incoming webhook URL for notifications |
| `LOG_LEVEL` | No | Logging level (`debug`, `info`, `warning`, `error`) |
| `HEALTH_PORT` | No | Port for health HTTP endpoint (default: 4000) |
| `PROVER_STUCK_THRESHOLD_SECONDS` | No | Seconds before prover is considered stuck (default: 3600). Increase for multi-GPU setups. |

> **Note:** If `ETHPROOFS_*` variables are not set, the client will still generate proofs but won't report them to the EthProofs API.

### Health Endpoint

The application exposes HTTP health endpoints for monitoring and orchestration (e.g., Kubernetes probes).

**Endpoints:**

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Full health status with component details |
| `GET /health/ready` | Readiness probe (200 if ready, 503 if not) |
| `GET /health/live` | Liveness probe (always 200 if server is up) |

**Status Levels:**

| Status | Meaning | HTTP Code |
|--------|---------|-----------|
| `healthy` | All components up and working normally | 200 |
| `degraded` | Components up but prover stuck (proving > threshold) | 503 |
| `unhealthy` | One or more components down | 503 |

**Example Response (`GET /health`):**

```json
{
  "status": "healthy",
  "timestamp": "2025-01-12T15:30:00Z",
  "uptime_seconds": 3600,
  "components": {
    "prover": {
      "status": "up",
      "state": "proving_21500000",
      "queue_length": 2,
      "queued_blocks": [21500100, 21500200],
      "proving_since": "2025-01-12T15:00:00Z",
      "proving_duration_seconds": 1800
    },
    "input_generator": {
      "status": "up",
      "state": "idle",
      "queue_length": 0,
      "queued_blocks": [],
      "processed_count": 15
    },
    "task_supervisor": {
      "status": "up",
      "pid": "#PID<0.250.0>",
      "active_tasks": 0
    }
  },
  "system": {
    "beam_memory_mb": 128.5,
    "process_count": 85,
    "scheduler_count": 8,
    "otp_release": "28"
  }
}
```

**Usage:**

```bash
# Check full health status
curl http://<host>:4000/health | jq

# Check readiness and liveness
curl -f http://<host>:4000/health/ready  # Returns 503 if not ready
curl -f http://<host>:4000/health/live   # Returns 200 if alive
```

### Output Files

Proof artifacts are written to the `output/` directory:

```
output/
└── {block_number}/
    ├── result.json                         # Proof metadata (cycles, time, verifier_id)
    └── vadcop_final_proof.compressed.bin   # Binary proof data
```

### Debugging

#### Using IEx

```elixir
# Check InputGenerator status
EthProofsClient.InputGenerator.status()

# Check Prover status
EthProofsClient.Prover.status()

# Manually trigger generation for a specific block
EthProofsClient.InputGenerator.generate(21500000)

# View supervision tree
:observer.start()
```

#### Using Observer

Start the Erlang observer to visualize the supervision tree and process states:

```elixir
:observer.start()
```

Navigate to the "Applications" tab and select `ethproofs_client` to see:
- Supervisor hierarchy
- TaskSupervisor with active tasks
- GenServer states and message queues

## 📚 References and acknowledgements

The following links, repos, companies and projects have been important in the development of this repo, we have learned a lot from them and want to thank and acknowledge them.

- [EthProofs Repo](https://github.com/ethproofs/ethproofs)
- [EthProofs API Documentation](https://ethproofs.org/api.html)
- [ZisK EthProofs](https://github.com/0xPolygonHermez/zisk-ethproofs)

If we forgot to include anyone, please file an issue so we can add you. We always strive to reference the inspirations and code we use, but as an organization with multiple people, mistakes can happen, and someone might forget to include a reference.
