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
