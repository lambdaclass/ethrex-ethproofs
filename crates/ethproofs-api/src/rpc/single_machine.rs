use crate::rpc::common::MachineConfiguration;

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct CreateSingleMachineRequest {
    /// Human-readable name. Main display name in the UI
    ///
    /// * Required
    /// * Max length: 50 characters
    pub nickname: String,
    /// Description of the cluster
    ///
    /// * Optional
    /// * Max length: 200 characters
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// ID of the zkVM version. Visit [ZKVMs](https://ethproofs.org/docs/zkvms) to view all available zkVMs and their IDs.
    ///
    /// * Required
    /// * Integer greater than 0
    pub zkvm_version_id: u64,
    /// Technical specifications. Use `configuration.cluster_machine` field instead.
    ///
    /// * Optional
    /// * Max length: 200 characters
    #[deprecated]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hardware: Option<String>,
    /// Type of cycle
    ///
    /// * Optional
    /// * Max length: 50 characters
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cycle_type: Option<String>,
    /// Proof system used to generate proofs. (e.g., Groth16 or PlonK).
    ///
    /// * Optional
    /// * Max length: 50 characters
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proof_type: Option<String>,
    /// Physical hardware specifications of the machine
    ///
    /// * Required
    pub machine: MachineConfiguration,
    /// The instance_name value of the cloud instance. Visit [Cloud Instances](https://ethproofs.org/docs/cloud-instances) to view all available instances and their exact names.
    ///
    /// * Required
    pub cloud_instance_name: String,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(transparent)]
pub struct CreateSingleMachineResponse {
    pub machine_id: u64,
}
