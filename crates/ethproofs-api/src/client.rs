use crate::{
    EthProofsError, EthProofsRequest, EthProofsResponse,
    constants::{PRODUCTION_URL, STAGING_URL},
    rpc,
};

pub struct EthProofsClient {
    client: reqwest::Client,
    base_url: reqwest::Url,
    api_key: String,
}

impl EthProofsClient {
    /// Create a new client with the given API key (uses production URL by default)
    pub fn new(api_key: impl Into<String>) -> Result<Self, EthProofsError> {
        Self::with_base_url(reqwest::Url::parse(PRODUCTION_URL)?, api_key)
    }

    /// Create a new client with a custom base URL
    pub fn with_base_url(
        base_url: reqwest::Url,
        api_key: impl Into<String>,
    ) -> Result<Self, EthProofsError> {
        let eth_proofs_client = Self {
            client: reqwest::Client::new(),
            base_url,
            api_key: api_key.into(),
        };

        Ok(eth_proofs_client)
    }

    /// Create a new client pointing to the staging environment
    pub fn staging(api_key: impl Into<String>) -> Result<Self, EthProofsError> {
        Self::with_base_url(reqwest::Url::parse(STAGING_URL)?, api_key)
    }

    /// Helper method to build authorization headers
    fn auth_header(&self) -> String {
        format!("Bearer {}", self.api_key)
    }

    /// Generic method to handle any request implementing the Request trait.
    pub async fn call<R>(&self, request: impl Into<EthProofsRequest>) -> Result<R, EthProofsError>
    where
        R: for<'de> serde::Deserialize<'de>,
    {
        let request = request.into();

        let url = format!("{}{}", self.base_url, request.endpoint());

        let mut req_builder = self
            .client
            .request(request.method(), &url)
            .header("Authorization", self.auth_header());

        if let Some(body) = request.body() {
            req_builder = req_builder.json(&body);
        }

        let response = req_builder.send().await?;

        // Check for error status codes
        let status = response.status();
        if !status.is_success() {
            let message = response
                .text()
                .await
                .unwrap_or_else(|_| "Unknown error".to_string());
            return Err(EthProofsError::ApiError {
                status: status.as_u16(),
                message,
            });
        }

        let res = response.json::<serde_json::Value>().await?;

        let eth_proofs_response = serde_json::from_value::<R>(res)?;

        Ok(eth_proofs_response)
    }

    pub fn handle_response(&self, response: EthProofsResponse) {
        match response {
            EthProofsResponse::GetBlockDetails(_get_block_details_response) => todo!(),
            EthProofsResponse::CreateCluster(_create_cluster_request) => todo!(),
            EthProofsResponse::ListClusters(_list_clusters_response) => todo!(),
            EthProofsResponse::ListActiveClustersForATeam(
                _list_active_clusters_for_ateam_response,
            ) => todo!(),
            EthProofsResponse::CreateSingleMachine(_create_single_machine_response) => todo!(),
            EthProofsResponse::DownloadProof(_download_proof_response) => todo!(),
            EthProofsResponse::DownloadProofs(_download_proofs_response) => todo!(),
            EthProofsResponse::ListProofs(_list_proofs_response) => todo!(),
            EthProofsResponse::QueuedProof(_queued_proof_response) => todo!(),
            EthProofsResponse::ProvingProof(_proving_proof_response) => todo!(),
            EthProofsResponse::ProvedProof(_proved_proof_response) => todo!(),
            EthProofsResponse::ListCloudInstances(_list_cloud_instances_response) => todo!(),
        }
    }

    // Convenience methods for specific endpoints

    pub async fn get_block_details(
        &self,
        block_number: rpc::common::BlockNumber,
    ) -> Result<rpc::blocks::GetBlockDetailsResponse, EthProofsError> {
        self.call(rpc::blocks::GetBlockDetailsRequest { block_number })
            .await
    }

    pub async fn create_cluster(
        &self,
        request: rpc::clusters::CreateClusterRequest,
    ) -> Result<rpc::clusters::CreateClusterResponse, EthProofsError> {
        self.call(request).await
    }

    pub async fn list_clusters(
        &self,
        request: rpc::clusters::ListClustersRequest,
    ) -> Result<rpc::clusters::ListClustersResponse, EthProofsError> {
        self.call(request).await
    }

    pub async fn list_active_clusters_for_team(
        &self,
        request: rpc::clusters::ListActiveClustersForATeamRequest,
    ) -> Result<rpc::clusters::ListActiveClustersForATeamResponse, EthProofsError> {
        self.call(request).await
    }

    pub async fn create_single_machine(
        &self,
        request: rpc::single_machine::CreateSingleMachineRequest,
    ) -> Result<rpc::single_machine::CreateSingleMachineResponse, EthProofsError> {
        self.call(request).await
    }

    pub async fn download_proof(
        &self,
        proof_id: &str,
    ) -> Result<rpc::proofs::DownloadProofResponse, EthProofsError> {
        self.call(rpc::proofs::DownloadProofRequest {
            proof_id: proof_id.to_string(),
        })
        .await
    }

    pub async fn list_proofs(
        &self,
        request: rpc::proofs::ListProofsRequest,
    ) -> Result<rpc::proofs::ListProofsResponse, EthProofsError> {
        self.call(request).await
    }

    pub async fn queue_proof(
        &self,
        request: rpc::proofs::QueuedProofRequest,
    ) -> Result<rpc::proofs::QueuedProofResponse, EthProofsError> {
        self.call(request).await
    }

    pub async fn list_cloud_instances(
        &self,
        request: rpc::cloud_instances::ListCloudInstancesRequest,
    ) -> Result<rpc::cloud_instances::ListCloudInstancesResponse, EthProofsError> {
        self.call(request).await
    }
}
