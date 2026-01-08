# ethrex-ethproofs

EthProofs client written in Elixir, powered by ethrex.

## 🚀 Getting Started

> [!WARNING]
> The current version of this project only supports single-GPU ZisK proving using the `cargo-zisk prove` command under-the-hood. For quick local runs without proof generation, set `ZISK_ACTION=execute`. Support for distributed proving and server mode will be added in future releases.

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
ZISK_ACTION=prove \
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
> - To do a quick non-proving run, set `ZISK_ACTION=execute`. This uses `cargo-zisk execute` under the hood and skips proof reporting.

> [!TIP]
> If you want to run the EthProofs client without sending requests to the EthProofs API (for testing purposes), you do this by not passing the `ETHPROOFS_` environment variables.

#### Troubleshooting

> [!NOTE]
> This is a placeholder for future troubleshooting tips. Please report any issues you encounter while running the integration tests to help us improve this section.

## 📖 Documentation

TBD

## 📚 References and acknowledgements

The following links, repos, companies and projects have been important in the development of this repo, we have learned a lot from them and want to thank and acknowledge them.

- [EthProofs Repo](https://github.com/ethproofs/ethproofs)
- [EthProofs API Documentation](https://ethproofs.org/api.html)
- [ZisK EthProofs](https://github.com/0xPolygonHermez/zisk-ethproofs)

If we forgot to include anyone, please file an issue so we can add you. We always strive to reference the inspirations and code we use, but as an organization with multiple people, mistakes can happen, and someone might forget to include a reference.
