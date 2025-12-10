use crate::rpc;

#[expect(clippy::large_enum_variant)]
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(untagged)]
pub enum EthProofsRequest {
    GetBlockDetails(rpc::blocks::GetBlockDetailsRequest),
    CreateCluster(rpc::clusters::CreateClusterRequest),
    ListClusters(rpc::clusters::ListClustersRequest),
    ListActiveClustersForATeam(rpc::clusters::ListActiveClustersForATeamRequest),
    CreateSingleMachine(rpc::single_machine::CreateSingleMachineRequest),
    DownloadProof(rpc::proofs::DownloadProofRequest),
    DownloadProofs(rpc::proofs::DownloadProofsRequest),
    ListProofs(rpc::proofs::ListProofsRequest),
    QueuedProof(rpc::proofs::QueuedProofRequest),
    ProvingProof(rpc::proofs::ProvingProofRequest),
    ProvedProof(rpc::proofs::ProvedProofRequest),
    ListCloudInstances(rpc::cloud_instances::ListCloudInstancesRequest),
    // UploadCSPBenchmarks(rpc::csp_benchmarks::UploadCSPBenchmarksRequest),
    // Add more request types as needed
}

impl EthProofsRequest {
    /// The HTTP method for the request (e.g., GET, POST).
    pub fn method(&self) -> reqwest::Method {
        match self {
            EthProofsRequest::GetBlockDetails(_) => reqwest::Method::GET,
            EthProofsRequest::CreateCluster(_) => reqwest::Method::POST,
            EthProofsRequest::ListClusters(_) => reqwest::Method::GET,
            EthProofsRequest::ListActiveClustersForATeam(_) => reqwest::Method::GET,
            EthProofsRequest::CreateSingleMachine(_) => reqwest::Method::POST,
            EthProofsRequest::DownloadProof(_) => reqwest::Method::GET,
            EthProofsRequest::DownloadProofs(_) => reqwest::Method::GET,
            EthProofsRequest::ListProofs(_) => reqwest::Method::GET,
            EthProofsRequest::QueuedProof(_) => reqwest::Method::POST,
            EthProofsRequest::ProvingProof(_) => reqwest::Method::POST,
            EthProofsRequest::ProvedProof(_) => reqwest::Method::POST,
            EthProofsRequest::ListCloudInstances(_) => reqwest::Method::GET,
        }
    }

    /// The API endpoint path (relative to the base URL), including any query parameters.
    pub fn endpoint(&self) -> String {
        match self {
            EthProofsRequest::GetBlockDetails(req) => {
                format!("/blocks/{}", req.block_number)
            }
            EthProofsRequest::CreateCluster(_) | EthProofsRequest::ListClusters(_) => {
                "/clusters".to_string()
            }
            EthProofsRequest::ListActiveClustersForATeam(req) => {
                format!("/clusters/active?team_id={}", req.team_id)
            }
            EthProofsRequest::CreateSingleMachine(_) => "/single-machine".to_string(),
            EthProofsRequest::DownloadProof(req) => {
                format!("/proofs/download/{}", req.proof_id)
            }
            EthProofsRequest::DownloadProofs(req) => {
                format!("/proofs/download/block/{}", req.block_hash)
            }
            EthProofsRequest::ListProofs(req) => {
                let mut endpoint = "/proofs".to_string();
                if let Some(block) = &req.block {
                    endpoint.push_str(&format!("?block={block}"));
                }
                if let Some(clusters) = &req.clusters {
                    let separator = if endpoint.contains('?') { '&' } else { '?' };
                    endpoint.push_str(&format!("{separator}clusters={clusters}"));
                }
                let separator = if endpoint.contains('?') { '&' } else { '?' };
                endpoint.push_str(&format!(
                    "{separator}limit={}&offset={}",
                    req.limit, req.offset
                ));
                endpoint
            }
            EthProofsRequest::QueuedProof(_) => "/proofs/queue".to_string(),
            EthProofsRequest::ProvingProof(_) => "/proofs/proving".to_string(),
            EthProofsRequest::ProvedProof(_) => "/proofs/proved".to_string(),
            EthProofsRequest::ListCloudInstances(req) => {
                let mut endpoint = "/cloud-instances".to_string();
                if let Some(provider) = &req.provider {
                    endpoint.push_str(&format!("?provider={provider}"));
                }
                endpoint
            }
        }
    }

    /// The optional JSON body for the request (e.g., for POST/PUT).
    /// Returns `None` for requests without a body (e.g., GET).
    pub fn body(self) -> Option<serde_json::Value> {
        match self {
            // GET requests don't have bodies
            Self::GetBlockDetails(_)
            | Self::ListClusters(_)
            | Self::ListActiveClustersForATeam(_)
            | Self::DownloadProof(_)
            | Self::DownloadProofs(_)
            | Self::ListProofs(_)
            | Self::ListCloudInstances(_) => None,

            // POST requests have bodies
            Self::CreateCluster(req) => serde_json::to_value(req).ok(),
            Self::CreateSingleMachine(req) => serde_json::to_value(req).ok(),
            Self::QueuedProof(req) => serde_json::to_value(req).ok(),
            Self::ProvingProof(req) => serde_json::to_value(req).ok(),
            Self::ProvedProof(req) => serde_json::to_value(req).ok(),
        }
    }
}

impl From<rpc::blocks::GetBlockDetailsRequest> for EthProofsRequest {
    fn from(value: rpc::blocks::GetBlockDetailsRequest) -> Self {
        EthProofsRequest::GetBlockDetails(value)
    }
}

impl From<rpc::clusters::CreateClusterRequest> for EthProofsRequest {
    fn from(value: rpc::clusters::CreateClusterRequest) -> Self {
        EthProofsRequest::CreateCluster(value)
    }
}

impl From<rpc::clusters::ListClustersRequest> for EthProofsRequest {
    fn from(value: rpc::clusters::ListClustersRequest) -> Self {
        EthProofsRequest::ListClusters(value)
    }
}

impl From<rpc::clusters::ListActiveClustersForATeamRequest> for EthProofsRequest {
    fn from(value: rpc::clusters::ListActiveClustersForATeamRequest) -> Self {
        EthProofsRequest::ListActiveClustersForATeam(value)
    }
}

impl From<rpc::single_machine::CreateSingleMachineRequest> for EthProofsRequest {
    fn from(value: rpc::single_machine::CreateSingleMachineRequest) -> Self {
        EthProofsRequest::CreateSingleMachine(value)
    }
}

impl From<rpc::proofs::DownloadProofRequest> for EthProofsRequest {
    fn from(value: rpc::proofs::DownloadProofRequest) -> Self {
        EthProofsRequest::DownloadProof(value)
    }
}

impl From<rpc::proofs::DownloadProofsRequest> for EthProofsRequest {
    fn from(value: rpc::proofs::DownloadProofsRequest) -> Self {
        EthProofsRequest::DownloadProofs(value)
    }
}

impl From<rpc::proofs::ListProofsRequest> for EthProofsRequest {
    fn from(value: rpc::proofs::ListProofsRequest) -> Self {
        EthProofsRequest::ListProofs(value)
    }
}

impl From<rpc::proofs::QueuedProofRequest> for EthProofsRequest {
    fn from(value: rpc::proofs::QueuedProofRequest) -> Self {
        EthProofsRequest::QueuedProof(value)
    }
}

impl From<rpc::proofs::ProvingProofRequest> for EthProofsRequest {
    fn from(value: rpc::proofs::ProvingProofRequest) -> Self {
        EthProofsRequest::ProvingProof(value)
    }
}

impl From<rpc::proofs::ProvedProofRequest> for EthProofsRequest {
    fn from(value: rpc::proofs::ProvedProofRequest) -> Self {
        EthProofsRequest::ProvedProof(value)
    }
}

impl From<rpc::cloud_instances::ListCloudInstancesRequest> for EthProofsRequest {
    fn from(value: rpc::cloud_instances::ListCloudInstancesRequest) -> Self {
        EthProofsRequest::ListCloudInstances(value)
    }
}
