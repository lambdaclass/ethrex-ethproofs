# Deploying the dual prover on vast.ai

This directory makes the production EthProofs setup (dual ZisK + Airbender prover,
proving every 100th mainnet block) reproducible on a fresh vast.ai instance. It exists
because vast.ai instances have **no persistent storage** unless a volume is attached —
a *recycle* or *destroy* wipes the container filesystem (*stop/start* is safe). With
this branch, a wiped instance is rebuilt in ~2 hours; the only thing not in the repo
is the secrets file (`~/.ethproofs.env`).

## What runs in production

```
mainnet RPC (debug_executionWitness capable)
   │ polled every ~2.5s
   ▼
ethrex-ethproofs (this repo, Phoenix app, mix phx.server)
   ├─ InputGenerator: block + execution witness → Rustler NIF encodes
   │    <block>.bin (ZisK) and <block>.hex (Airbender) at every 100th block
   ├─ Prover GenServer: sequentially on the single GPU
   │    cargo-zisk prove -e <ELF> -i <blk>.bin -o <out> -a -u        → ZisK cluster
   │    cargo-airbender prove <app.bin> --input <blk>.hex --backend gpu → Airbender cluster
   └─ submits queued/proving/proved to the EthProofs API; dashboard on :4000
```

Supervision: vast images manage long-running processes with **supervisor** (no systemd
in the container). `ethproofs-prover.supervisor.conf` restarts the app on any exit and
rotates its log (200 MB × 3).

## Instance requirements

| Resource | Minimum | Notes |
|---|---|---|
| GPU | RTX 5090 (32 GB VRAM) | Must match the hardware registered for the EthProofs clusters |
| RAM | 64 GB+ (more is better) | Provers use tens of GB; large RAM also page-caches the 50 GB proving key |
| Disk | 200 GB | 50 GB proving key + ~3 GB ROM cache + ~40 GB toolchains/builds + working room |
| Image | CUDA 13.x base (nvcc preinstalled) | Both GPU builds need the toolkit, not just the driver |

Keep the Phoenix port (4000) OFF the instance's external port mappings — reach the
dashboard through an SSH tunnel.

## Fresh-instance quickstart

```bash
git clone -b <this-branch> https://github.com/lambdaclass/ethrex-ethproofs.git ~/ethrex-ethproofs
cp ~/ethrex-ethproofs/deploy/vast/ethproofs.env.example ~/.ethproofs.env
chmod 600 ~/.ethproofs.env
# fill in ETH_RPC_URL and ETHPROOFS_API_KEY (ask the team; never commit them)
bash ~/ethrex-ethproofs/deploy/vast/bootstrap.sh 2>&1 | tee ~/bootstrap.log
supervisorctl status ethproofs-prover
```

Health check: `prover-service.log` shows `Latest block: N. Next multiple of 100: M`,
and at the next multiple of 100 both a `zisk proved block ...` and an
`airbender proved block ...` line appear, each followed by a `proofs/proved` submission.

## Operations

```bash
supervisorctl status ethproofs-prover      # state
supervisorctl tail -f ethproofs-prover     # live log
supervisorctl restart|stop ethproofs-prover
tail -f ~/ethrex-ethproofs/prover-service.log
```

Config changes: edit `~/.ethproofs.env`, then `supervisorctl restart ethproofs-prover`.
Restart between proving cycles (the app proves for ~10 min after each 100th block;
the remaining ~10 min of each cycle are idle).

## Files

| File | Installs to | Purpose |
|---|---|---|
| `bootstrap.sh` | — | One-shot rebuild of the entire stack on a fresh instance |
| `relaunch-dual-prover.sh` | runs from repo | Service entrypoint: PATH + env + artifact checks + `mix phx.server` |
| `ethproofs-prover.supervisor.conf` | `/etc/supervisor/conf.d/` | Service definition (autorestart, log rotation) |
| `ethproofs-cleanup.cron` | `/etc/cron.d/` | Prunes per-block input files >14 days old |
| `ethproofs.env.example` | `~/.ethproofs.env` (copy) | Template for secrets/endpoints |

Guest artifacts (tracked in `ethrex_guest_programs/`, the proving identity of the clusters):

| Artifact | Provenance |
|---|---|
| `ethrex-c5de3bd-zisk-0.16.1-guest.elf` | ethrex commit `c5de3bd`, ZisK toolchain 0.16.1 |
| `airbender-0f97ca8f/app.bin` (+ .elf/.text) | ethrex branch `airbender-integration` @ `0f97ca8f`, codec v0; sha256s in `manifest.toml` |

## Known issues / gotchas

- **No API key ⇒ crash loop**: on this branch the Prover GenServer crashes at every
  100th block if `ETHPROOFS_API_KEY`/`ETHPROOFS_RPC_URL` are absent — the guard clauses
  in `lib/ethproofs_client/rpc.ex` are bare `if` expressions whose values are discarded
  (no early return), so the request is built with a nil key. The README's "optional"
  only holds once that is fixed.
- **Per-invocation prover startup overhead** (~4 min each for cargo-zisk and
  cargo-airbender on vast instances, vs near-zero on the previous bare-metal host;
  actual proof compute is unaffected). Fits the 20-min cadence but inflates the
  latency EthProofs displays. Unresolved; suspects: container `/dev/shm` sizing,
  CUDA JIT cache, MPI/helper-service startup.
- **ziskup is CPU-only** — ZisK must be built from source with `--features gpu`
  (bootstrap does this).
- **GPU arch**: defaults target RTX 5090 (`CUDA_ARCH=sm_120`, `CUDAARCHS=100`).
  Override both when bootstrapping other GPUs; ROM cache (`~/.zisk/cache`) is
  GPU-specific and regenerates via `rom-setup`.
- **Codec coupling**: the input-generator NIF (this repo) and the guest binaries must
  come from the same ethrex revision family; mixing revisions causes codec errors.
- The proving-key tarball is the 0.16.0 release; it is the correct key for the 0.16.1
  toolchain (`check-setup -a` then regenerates const trees locally).
