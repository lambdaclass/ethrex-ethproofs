use std::path::Path;

use ethrex_config::networks::{Network, PublicNetwork};
use ethrex_guest::input::ProgramInput;
use ethrex_rpc::{
    debug::execution_witness::{RpcExecutionWitness, execution_witness_from_rpc_chain_config},
    types::block::RpcBlock,
};

const CARGO_MANIFEST_DIR: &str = env!("CARGO_MANIFEST_DIR");

const MAINNET_ELASTICITY_MULTIPLIER: u64 = 2;

#[rustler::nif]
fn generate_input(rpc_block: String, rpc_execution_witness: String) -> Result<String, String> {
    let chain_config = Network::PublicNetwork(PublicNetwork::Mainnet)
        .get_genesis()
        .map_err(|e| format!("Failed to get genesis config for Mainnet: {}", e))?
        .config;

    let rpc_block: RpcBlock = serde_json::from_str(&rpc_block)
        .map_err(|e| format!("Failed to deserialize RPC block: {}", e))?;

    let rpc_execution_witness: RpcExecutionWitness =
        serde_json::from_str(&rpc_execution_witness)
            .map_err(|e| format!("Failed to deserialize RPC execution witness: {}", e))?;

    let block_number = rpc_block.header.number;

    let input = ProgramInput {
        blocks: vec![
            rpc_block
                .try_into()
                .map_err(|e| format!("Failed to convert RPC block to internal block: {}", e))?,
        ],
        execution_witness: execution_witness_from_rpc_chain_config(
            rpc_execution_witness,
            chain_config,
            block_number,
        )
        .map_err(|e| format!("Failed to create execution witness from RPC data: {}", e))?,
        elasticity_multiplier: MAINNET_ELASTICITY_MULTIPLIER,
        fee_configs: None,
    };

    let input_bytes = rkyv::to_bytes::<rkyv::rancor::Error>(&input)
        .map_err(|e| format!("Failed to serialize input to bytes: {}", e))?;

    let input_path = Path::new(CARGO_MANIFEST_DIR)
        .parent()
        .ok_or("Failed to get parent directory".to_string())?
        .parent()
        .ok_or("Failed to get grandparent directory".to_string())?
        .join(format!("{}.bin", block_number));

    std::fs::write(&input_path, input_bytes)
        .map_err(|e| format!("Failed to write input file: {}", e))?;

    input_path
        .to_str()
        .ok_or("Failed to convert input path to str".to_string())
        .map(|s| s.to_string())
}

rustler::init!("Elixir.EthProofsClient.InputGenerator");
