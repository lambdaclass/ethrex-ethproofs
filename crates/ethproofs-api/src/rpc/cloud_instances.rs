use crate::rpc::common::CloudInstance;

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ListCloudInstancesRequest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
#[serde(transparent)]
pub struct ListCloudInstancesResponse {
    pub instances: Vec<CloudInstance>,
}
