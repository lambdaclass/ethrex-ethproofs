/// Custom error type for the Ethproofs API
#[derive(Debug, thiserror::Error)]
pub enum EthProofsError {
    /// Invalid URL error
    #[error("Invalid URL: {0}")]
    InvalidURL(#[from] url::ParseError),
    /// HTTP request error
    #[error("Request error: {0}")]
    RequestError(#[from] reqwest::Error),
    /// API returned an error status
    #[error("API error (status: {status}): {message}")]
    ApiError { status: u16, message: String },
    /// Failed to parse response
    #[error("Failed to parse response: {0}")]
    ParseError(#[from] serde_json::Error),
}
