use crate::{EthProofsError, rpc};

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
#[serde(untagged)]
pub enum EthProofsResponse {
    GetBlockDetails(rpc::blocks::GetBlockDetailsResponse),
    CreateCluster(rpc::clusters::CreateClusterResponse),
    ListClusters(rpc::clusters::ListClustersResponse),
    ListActiveClustersForATeam(rpc::clusters::ListActiveClustersForATeamResponse),
    CreateSingleMachine(rpc::single_machine::CreateSingleMachineResponse),
    DownloadProof(rpc::proofs::DownloadProofResponse),
    DownloadProofs(rpc::proofs::DownloadProofsResponse),
    ListProofs(rpc::proofs::ListProofsResponse),
    QueuedProof(rpc::proofs::QueuedProofResponse),
    ProvingProof(rpc::proofs::ProvingProofResponse),
    ProvedProof(rpc::proofs::ProvedProofResponse),
    ListCloudInstances(rpc::cloud_instances::ListCloudInstancesResponse),
    // UploadCSPBenchmarks(rpc::csp_benchmarks::UploadCSPBenchmarksResponse),
    // Add more response types as needed
}

impl EthProofsResponse {
    pub fn into_inner<T>(self) -> Result<T, EthProofsError>
    where
        Self: TryInto<T, Error = EthProofsError>,
    {
        self.try_into()
    }
}

impl TryFrom<EthProofsResponse> for rpc::blocks::GetBlockDetailsResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::GetBlockDetails(response) = value else {
            return Err(EthProofsError::ParseError(
                "GetBlockDetailsResponse".to_string(),
            ));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::clusters::CreateClusterResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::CreateCluster(response) = value else {
            return Err(EthProofsError::ParseError(
                "CreateClusterResponse".to_string(),
            ));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::clusters::ListClustersResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::ListClusters(response) = value else {
            return Err(EthProofsError::ParseError(
                "ListClustersResponse".to_string(),
            ));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::clusters::ListActiveClustersForATeamResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::ListActiveClustersForATeam(response) = value else {
            return Err(EthProofsError::ParseError(
                "ListActiveClustersForATeamResponse".to_string(),
            ));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::single_machine::CreateSingleMachineResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::CreateSingleMachine(response) = value else {
            return Err(EthProofsError::ParseError(
                "CreateSingleMachineResponse".to_string(),
            ));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::proofs::DownloadProofResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::DownloadProof(response) = value else {
            return Err(EthProofsError::ParseError(
                "DownloadProofResponse".to_string(),
            ));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::proofs::DownloadProofsResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::DownloadProofs(response) = value else {
            return Err(EthProofsError::ParseError(
                "DownloadProofsResponse".to_string(),
            ));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::proofs::ListProofsResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::ListProofs(response) = value else {
            return Err(EthProofsError::ParseError("ListProofsResponse".to_string()));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::proofs::QueuedProofResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::QueuedProof(response) = value else {
            return Err(EthProofsError::ParseError(
                "QueuedProofResponse".to_string(),
            ));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::proofs::ProvingProofResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::ProvingProof(response) = value else {
            return Err(EthProofsError::ParseError(
                "ProvingProofResponse".to_string(),
            ));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::proofs::ProvedProofResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::ProvedProof(response) = value else {
            return Err(EthProofsError::ParseError(
                "ProvedProofResponse".to_string(),
            ));
        };

        Ok(response)
    }
}

impl TryFrom<EthProofsResponse> for rpc::cloud_instances::ListCloudInstancesResponse {
    type Error = EthProofsError;

    fn try_from(value: EthProofsResponse) -> Result<Self, Self::Error> {
        let EthProofsResponse::ListCloudInstances(response) = value else {
            return Err(EthProofsError::ParseError(
                "ListCloudInstancesResponse".to_string(),
            ));
        };

        Ok(response)
    }
}
