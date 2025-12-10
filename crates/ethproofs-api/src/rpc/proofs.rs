use crate::rpc::common::{ClusterMachine, NumberOrString};

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct DownloadProofRequest {
    /// The unique proof ID (UUID)
    ///
    /// * Required
    /// * Example: `550e8400-e29b-41d4-a716-446655440000`
    #[serde(rename = "id")]
    pub proof_id: String,
}

/// Download a single proved proof by its proof ID.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct DownloadProofResponse {
    /// Proof binary file
    pub proof_binary_file: String,
}

/// Download all proved proofs for a specific block as a ZIP file.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct DownloadProofsRequest {
    /// The block hash (0x-prefixed 64 hex characters)
    ///
    /// * Required
    /// * String matching pattern `^0x[a-fA-F0-9]{64}$`
    /// * Example: `0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef`
    #[serde(rename = "block")]
    pub block_hash: String,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct DownloadProofsResponse {
    /// ZIP file containing all proofs for the block
    pub proofs_zip_file: String,
}

/// Retrieve a filtered and paginated list of proofs
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ListProofsRequest {
    /// Filter by block number or block hash (0x-prefixed 64 hex characters)
    ///
    /// * Optional
    /// * Example: `block=123456`
    #[serde(default)]
    pub block: Option<NumberOrString>,
    /// Filter by comma-separated cluster UUIDs (e.g., `uuid1,uuid2,uuid3`)
    ///
    /// * Optional
    /// * Example: `clusters=550e8400-e29b-41d4-a716-446655440000,660e8400-e29b-41d4-a716-446655440001`
    #[serde(default)]
    pub clusters: Option<String>,
    /// Number of proofs to return (default: `100`, max: `1000`)
    ///
    /// * Optional
    /// * Integer in range `1..=1000`
    /// * Default: `100`
    #[serde(default = "default_limit")]
    pub limit: u64,
    /// Number of proofs to skip for pagination (default: `0`)
    ///
    /// * Optional
    /// * Integer greater than or equal to `0`
    /// * Default: `0`
    #[serde(default = "default_offset")]
    pub offset: u64,
}

fn default_limit() -> u64 {
    100
}

fn default_offset() -> u64 {
    0
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
pub struct ListProofsResponse {
    pub proofs: Vec<ProofRecord>,
    pub total_count: u64,
    pub limit: u64,
    pub offset: u64,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
pub struct ProofRecord {
    pub block_number: u64,
    // Note: cluster_id should be a number, but in practice it's a string UUID
    pub cluster_id: String,
    pub proof_id: u64,
    pub proof_status: ProofStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proving_cycles: Option<u64>,
    pub team_id: String,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proved_timestamp: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proving_timestamp: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub queued_timestamp: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proving_time: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub program_id: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub team: Option<Team>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub block: Option<Block>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cluster_version: Option<ClusterVersion>,
    // The following fields are retrieved in practice but not specified in the API docs
    pub cluster_version_id: u64,
    // The following fields are retrieved in practice but not specified in the API docs
    pub updated_at: String,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub enum ProofStatus {
    #[serde(rename = "queued")]
    Queued,
    #[serde(rename = "proving")]
    Proving,
    #[serde(rename = "proved")]
    Proved,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Team {
    pub id: String,
    pub name: String,
    pub slug: String,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    // The following fields are retrieved in practice but not specified in the API docs
    pub github_org: String,
    pub logo_url: Option<String>,
    pub storage_quota_bytes: Option<u64>,
    pub twitter_handle: Option<String>,
    pub website_url: Option<String>,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Block {
    #[serde(rename = "block_number")]
    pub number: u64,
    pub hash: String,
    pub timestamp: String,
    pub gas_used: u64,
    pub transaction_count: u64,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
pub struct ClusterVersion {
    pub id: u64,
    pub cluster_id: String,
    // Note: version field is specified in the API docs but appears to be missing in practice
    // pub version: String,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    pub cluster: ClusterRecord,
    pub zkvm_version: ZkvmVersion,
    pub cluster_machines: Vec<ClusterMachine>,
    // The following fields are retrieved in practice but not specified in the API docs
    pub is_active: bool,
    pub vk_path: Option<String>,
    pub index: u64,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ClusterRecord {
    pub id: String,
    // Note: name field is specified in the API docs but appears to be missing in practice
    // pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub nickname: Option<String>,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    // The following fields are retrieved in practice but not specified in the API docs
    pub cycle_type: String,
    pub description: String,
    pub hardware: String,
    pub index: u64,
    pub is_active: bool,
    pub is_multi_machine: bool,
    pub is_open_source: bool,
    pub proof_type: String,
    pub software_link: Option<String>,
    pub team_id: String,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ZkvmVersion {
    pub id: u64,
    pub version: String,
    pub zkvm_id: u64,
    // Note: release_date field is not specified as optional in the API docs but appears to be optional in practice
    pub release_date: Option<String>,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    pub zkvm: ZkvmRecord,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ZkvmRecord {
    pub id: u64,
    pub name: String,
    pub slug: String,
    pub isa: String,
    pub team_id: String,
    pub created_at: String,
    // The following fields are retrieved in practice but not specified in the API docs
    pub continuations: bool,
    pub dual_licenses: bool,
    pub frontend: String,
    pub is_open_source: bool,
    pub is_proving_mainnet: bool,
    pub parallelizable_proving: bool,
    pub precompiles: bool,
    pub repo_url: String,
}

/// The prover indicates they'll prove a block, but they haven't started proving yet.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct QueuedProofRequest {
    pub block_number: u64,
    pub cluster_id: u64,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct QueuedProofResponse {
    pub proof_id: u64,
}

/// The prover indicates they've started proving a block.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ProvingProofRequest {
    pub block_number: u64,
    pub cluster_id: u64,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ProvingProofResponse {
    pub proof_id: u64,
}

/// The prover indicates they've started proving a block.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ProvedProofRequest {
    pub block_number: u64,
    pub cluster_id: u64,
    /// Time in milliseconds taken to generate the proof including witness generation. It excludes time taken for data fetching and any latency to submit the proof.
    pub proving_time: u64,
    /// Number of cycles taken to generate the proof.
    pub proving_cycles: Option<u64>,
    /// Proof in base64 format.
    pub proof: String,
    /// vkey/image-id.
    pub verifier_id: Option<String>,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ProvedProofResponse {
    pub proof_id: u64,
}
