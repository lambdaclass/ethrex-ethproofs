use std::path::Path;

use ethrex_common::types::block_execution_witness::RpcExecutionWitness;
use ethrex_config::networks::{Network, PublicNetwork};
use ethrex_guest::input::ProgramInput;
use ethrex_rpc::types::block::RpcBlock;

const CARGO_MANIFEST_DIR: &str = env!("CARGO_MANIFEST_DIR");

#[rustler::nif]
fn generate_input(
    rpc_block: String,
    rpc_execution_witness: String,
) -> Result<(String, String), String> {
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

    let input = ProgramInput::new(
        vec![
            rpc_block
                .try_into()
                .map_err(|e| format!("Failed to convert RPC block to internal block: {}", e))?,
        ],
        rpc_execution_witness
            .into_execution_witness(chain_config, block_number)
            .map_err(|e| format!("Failed to create execution witness from RPC data: {}", e))?,
    );

    let input_bytes = rkyv::to_bytes::<rkyv::rancor::Error>(&input)
        .map_err(|e| format!("Failed to serialize input to bytes: {}", e))?;

    let base_dir = Path::new(CARGO_MANIFEST_DIR)
        .parent()
        .ok_or("Failed to get parent directory".to_string())?
        .parent()
        .ok_or("Failed to get grandparent directory".to_string())?;

    // --- ZisK format: [8-byte LE length][data][zero-padding to 8-byte alignment] ---
    let data_len = input_bytes.len();
    let total_len = 8 + data_len;
    let padding = (8 - (total_len % 8)) % 8;
    let mut zisk_buf = Vec::with_capacity(total_len + padding);
    zisk_buf.extend_from_slice(&data_len.to_le_bytes());
    zisk_buf.extend_from_slice(&input_bytes);
    zisk_buf.extend(std::iter::repeat(0u8).take(padding));

    let zisk_path = base_dir.join(format!("{}.bin", block_number));
    std::fs::write(&zisk_path, &zisk_buf)
        .map_err(|e| format!("Failed to write ZisK input file: {}", e))?;

    // --- Airbender format: bincode v2 Vec<u8> + u32 word framing, one word per line ---
    let config = bincode::config::standard();
    let bincode_payload = bincode::encode_to_vec(input_bytes.as_ref(), config)
        .map_err(|e| format!("Failed to encode Airbender payload: {}", e))?;

    let payload_len = bincode_payload.len() as u32;
    let word_count = bincode_payload.len().div_ceil(4);
    let mut words: Vec<u32> = Vec::with_capacity(1 + word_count);
    words.push(payload_len);
    for chunk in bincode_payload.chunks(4) {
        let mut padded = [0u8; 4];
        padded[..chunk.len()].copy_from_slice(chunk);
        words.push(u32::from_be_bytes(padded));
    }

    let hex: String = words.iter().map(|w| format!("{w:08x}\n")).collect();
    let airbender_path = base_dir.join(format!("{}.hex", block_number));
    std::fs::write(&airbender_path, &hex)
        .map_err(|e| format!("Failed to write Airbender input file: {}", e))?;

    let zisk_str = zisk_path
        .to_str()
        .ok_or("Failed to convert ZisK path to str".to_string())?
        .to_string();
    let airbender_str = airbender_path
        .to_str()
        .ok_or("Failed to convert Airbender path to str".to_string())?
        .to_string();

    Ok((zisk_str, airbender_str))
}

rustler::init!("Elixir.EthProofsClient.InputGenerator");
