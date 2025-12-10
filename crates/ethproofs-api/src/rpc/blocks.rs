use crate::rpc::common::BlockNumber;

#[derive(Debug, thiserror::Error)]
pub enum GetBlockDetailsRequestError {
    #[error("Missing field: {0}")]
    MissingField(&'static str),
    #[error("Invalid field {0}: {1}")]
    InvalidField(String, &'static str),
    #[error("Malformed request: {0}")]
    MalformedRequest(&'static str),
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct GetBlockDetailsRequest {
    /// The block number to retrieve
    ///
    /// * Required
    /// * Integer or string
    #[serde(rename = "block")]
    pub block_number: BlockNumber,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct GetBlockDetailsResponse {
    pub block_number: u64,
    pub timestamp: String,
    pub gas_used: u64,
    pub transaction_count: u32,
    pub hash: String,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
}
