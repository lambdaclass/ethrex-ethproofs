use serde::{Deserialize, Serialize};

use crate::rpc::common::{CloudInstance, MachineConfiguration};

#[derive(Debug, thiserror::Error)]
pub enum CreateClusterRequestError {
    #[error("Missing field: {0}")]
    MissingField(&'static str),
    #[error("Invalid field {0}: {1}")]
    InvalidField(String, &'static str),
    #[error("Malformed request: {0}")]
    MalformedRequest(&'static str),
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct CreateClusterRequest {
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
    /// Cluster configuration.
    ///
    /// * Required
    pub configuration: Vec<ClusterConfiguration>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ClusterConfiguration {
    /// Physical hardware specifications of the machine.
    pub machine: MachineConfiguration,
    /// Number of machines of this type.
    ///
    /// * Must be greater than 0
    pub machine_count: u64,
    /// The instance_name value of the cloud instance. Visit [Cloud Instances](https://ethproofs.org/docs/cloud-instances) to view all available instances and their exact names.
    pub cloud_instance_name: String,
    /// Number of equivalent cloud instances.
    ///
    /// * Must be greater than 0
    pub cloud_instance_count: u64,
}

/// Builder for `CreateClusterRequest` to facilitate construction with validation.
///
/// This builder provides a fluent API for creating `CreateClusterRequest` instances,
/// ensuring that all required fields are set and validating constraints such as
/// maximum lengths and value ranges.
///
/// # Example
///
/// ```rust
/// use ethproofs_api::clusters::{CreateClusterRequestBuilder, ClusterConfiguration, MachineConfiguration};
///
/// let request = CreateClusterRequestBuilder::new()
///     .nickname("My Cluster")
///     .description("A test cluster")
///     .zkvm_version_id(1)
///     .hardware("deprecated")
///     .cycle_type("SP1")
///     .proof_type("Groth16")
///     .configuration(vec![ClusterConfiguration {
///         machine: MachineConfiguration {
///             cpu_model: "Intel Xeon".to_string(),
///             cpu_cores: 4,
///             gpu_models: vec!["RTX 4090".to_string()],
///             gpu_count: vec![1],
///             gpu_memory_gb: vec![24],
///             memory_size_gb: vec![32],
///             memory_count: vec![8],
///             memory_type: vec!["DDR5".to_string()],
///             storage_size_gb: Some(1000),
///             total_tera_flops: Some(1000),
///             network_between_machines: Some("100GbE".to_string()),
///         },
///         machine_count: 2,
///         cloud_instance_name: "c5.xlarge".to_string(),
///         cloud_instance_count: 1,
///     }])
///     .build()
///     .expect("Failed to build request");
/// ```
#[derive(Debug, Default)]
pub struct CreateClusterRequestBuilder {
    nickname: Option<String>,
    description: Option<String>,
    zkvm_version_id: Option<u64>,
    #[deprecated]
    hardware: Option<String>,
    cycle_type: Option<String>,
    proof_type: Option<String>,
    configuration: Option<Vec<ClusterConfiguration>>,
}

impl CreateClusterRequestBuilder {
    /// Creates a new builder instance.
    pub fn new() -> Self {
        Self::default()
    }

    /// Sets the nickname for the cluster.
    ///
    /// # Arguments
    /// * `nickname` - The human-readable name, max 50 characters.
    pub fn nickname(mut self, nickname: impl Into<String>) -> Self {
        self.nickname = Some(nickname.into());
        self
    }

    /// Sets the description for the cluster.
    ///
    /// # Arguments
    /// * `description` - The description, max 200 characters. Pass `None` to unset.
    pub fn description(mut self, description: impl Into<String>) -> Self {
        self.description = Some(description.into());
        self
    }

    /// Sets the zkVM version ID.
    ///
    /// # Arguments
    /// * `id` - The ID, must be greater than 0.
    pub fn zkvm_version_id(mut self, id: u64) -> Self {
        self.zkvm_version_id = Some(id);
        self
    }

    /// Sets the hardware specification (deprecated).
    ///
    /// # Arguments
    /// * `hardware` - The hardware string, max 200 characters.
    #[expect(deprecated)]
    #[deprecated]
    pub fn hardware(mut self, hardware: impl Into<String>) -> Self {
        self.hardware = Some(hardware.into());
        self
    }

    /// Sets the cycle type.
    ///
    /// # Arguments
    /// * `cycle_type` - The cycle type string.
    pub fn cycle_type(mut self, cycle_type: impl Into<String>) -> Self {
        self.cycle_type = Some(cycle_type.into());
        self
    }

    /// Sets the proof type.
    ///
    /// # Arguments
    /// * `proof_type` - The proof type string (e.g., "Groth16").
    pub fn proof_type(mut self, proof_type: impl Into<String>) -> Self {
        self.proof_type = Some(proof_type.into());
        self
    }

    /// Sets the cluster configuration.
    ///
    /// # Arguments
    /// * `config` - The cluster configurations.
    pub fn configuration(mut self, config: Vec<ClusterConfiguration>) -> Self {
        self.configuration = Some(config);
        self
    }

    /// Builds the `CreateClusterRequest`, validating all constraints.
    ///
    /// # Returns
    /// Returns the constructed `CreateClusterRequest` or an error if validation fails.
    ///
    /// # Errors
    /// * `CreateClusterRequestError::MissingField` - If a required field is missing
    /// * `CreateClusterRequestError::InvalidField` - If a field fails validation
    /// * `CreateClusterRequestError::MalformedRequest` - If the request structure is invalid
    #[expect(deprecated, reason = "builder uses deprecated hardware field")]
    pub fn build(self) -> Result<CreateClusterRequest, CreateClusterRequestError> {
        let Some(nickname) = self.nickname else {
            return Err(CreateClusterRequestError::MissingField("nickname"));
        };

        if nickname.len() > 50 {
            return Err(CreateClusterRequestError::InvalidField(
                "nickname".to_string(),
                "must be at most 50 characters",
            ));
        }

        if self.description.as_ref().is_some_and(|d| d.len() > 200) {
            return Err(CreateClusterRequestError::InvalidField(
                "description".to_string(),
                "must be at most 200 characters",
            ));
        }

        let Some(zkvm_version_id) = self.zkvm_version_id else {
            return Err(CreateClusterRequestError::MissingField("zkvm_version_id"));
        };

        if zkvm_version_id == 0 {
            return Err(CreateClusterRequestError::InvalidField(
                "zkvm_version_id".to_string(),
                "must be greater than 0",
            ));
        }

        if self.hardware.as_ref().is_some_and(|h| h.len() > 200) {
            return Err(CreateClusterRequestError::InvalidField(
                "hardware".to_string(),
                "must be between 1 and 200 characters",
            ));
        }

        if self.cycle_type.as_ref().is_some_and(|c| c.is_empty()) {
            return Err(CreateClusterRequestError::InvalidField(
                "cycle_type".to_string(),
                "cycle_type is required",
            ));
        }

        if self.proof_type.as_ref().is_some_and(|p| p.is_empty()) {
            return Err(CreateClusterRequestError::InvalidField(
                "proof_type".to_string(),
                "proof_type is required",
            ));
        }

        let configuration = self
            .configuration
            .ok_or(CreateClusterRequestError::MissingField("configuration"))?;

        if configuration.is_empty() {
            return Err(CreateClusterRequestError::InvalidField(
                "configuration".to_string(),
                "configuration must not be empty",
            ));
        }

        for config in &configuration {
            if config.machine_count == 0 {
                return Err(CreateClusterRequestError::InvalidField(
                    "machine_count".to_string(),
                    "must be greater than 0",
                ));
            }
            if config.cloud_instance_count == 0 {
                return Err(CreateClusterRequestError::InvalidField(
                    "cloud_instance_count".to_string(),
                    "must be greater than 0",
                ));
            }

            let machine = &config.machine;

            // Validate CPU
            if machine.cpu_model.len() > 200 {
                return Err(CreateClusterRequestError::InvalidField(
                    "cpu_model".to_string(),
                    "must be at most 200 characters",
                ));
            }
            if machine.cpu_cores == 0 {
                return Err(CreateClusterRequestError::InvalidField(
                    "cpu_cores".to_string(),
                    "must be greater than 0",
                ));
            }

            // Validate GPU arrays lengths match
            let gpu_len = machine.gpu_models.as_ref().map_or(0, |v| v.len());
            if machine.gpu_count.as_ref().map_or(0, |v| v.len()) != gpu_len
                || machine.gpu_memory_gb.as_ref().map_or(0, |v| v.len()) != gpu_len
            {
                return Err(CreateClusterRequestError::MalformedRequest(
                    "gpu_models, gpu_count, and gpu_memory_gb must have the same length",
                ));
            }
            if let Some(gpu_models) = &machine.gpu_models {
                for (i, model) in gpu_models.iter().enumerate() {
                    if model.len() > 200 {
                        return Err(CreateClusterRequestError::InvalidField(
                            format!("gpu_models[{}]", i),
                            "must be at most 200 characters",
                        ));
                    }
                    if machine.gpu_count.as_ref().is_some_and(|v| v[i] == 0) {
                        return Err(CreateClusterRequestError::InvalidField(
                            format!("gpu_count[{}]", i),
                            "must be greater than 0",
                        ));
                    }
                    if machine.gpu_memory_gb.as_ref().is_some_and(|v| v[i] == 0) {
                        return Err(CreateClusterRequestError::InvalidField(
                            format!("gpu_memory_gb[{}]", i),
                            "must be greater than 0",
                        ));
                    }
                }
            }

            // Validate memory arrays
            let mem_len = machine.memory_size_gb.len();
            if machine.memory_count.len() != mem_len || machine.memory_type.len() != mem_len {
                return Err(CreateClusterRequestError::MalformedRequest(
                    "memory_size_gb, memory_count, and memory_type must have the same length",
                ));
            }
            if mem_len == 0 {
                return Err(CreateClusterRequestError::MalformedRequest(
                    "memory_size_gb, memory_count, and memory_type must not be empty",
                ));
            }
            for (i, &size) in machine.memory_size_gb.iter().enumerate() {
                if size == 0 {
                    return Err(CreateClusterRequestError::InvalidField(
                        format!("memory_size_gb[{}]", i),
                        "must be greater than 0",
                    ));
                }
                if machine.memory_count[i] == 0 {
                    return Err(CreateClusterRequestError::InvalidField(
                        format!("memory_count[{}]", i),
                        "must be greater than 0",
                    ));
                }
                if machine.memory_type[i].len() > 200 {
                    return Err(CreateClusterRequestError::InvalidField(
                        format!("memory_type[{}]", i),
                        "must be at most 200 characters",
                    ));
                }
            }

            // Validate optional fields
            if machine.storage_size_gb.is_some_and(|s| s == 0) {
                return Err(CreateClusterRequestError::InvalidField(
                    "storage_size_gb".to_string(),
                    "must be greater than 0",
                ));
            }
            if machine.total_tera_flops.is_some_and(|f| f == 0) {
                return Err(CreateClusterRequestError::InvalidField(
                    "total_tera_flops".to_string(),
                    "must be greater than 0",
                ));
            }
            if machine
                .network_between_machines
                .as_ref()
                .is_some_and(|n| n.len() > 500)
            {
                return Err(CreateClusterRequestError::InvalidField(
                    "network_between_machines".to_string(),
                    "must be at most 500 characters",
                ));
            }
        }

        let create_cluster_request = CreateClusterRequest {
            nickname,
            description: self.description,
            zkvm_version_id,
            hardware: self.hardware,
            cycle_type: self.cycle_type,
            proof_type: self.proof_type,
            configuration,
        };

        Ok(create_cluster_request)
    }
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct CreateClusterResponse {
    /// Cluster ID (index)
    ///
    /// * Required
    pub id: u64,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ListClustersRequest;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct ListClustersResponse {
    pub clusters: Vec<ClusterData>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct ClusterData {
    pub id: Option<u64>,
    pub nickname: String,
    // Serialization not skipped when None to match API response structure (string or null)
    #[serde(default)]
    pub description: Option<String>,
    // Serialization not skipped when None to match API response structure (string or null)
    #[serde(default)]
    pub hardware: Option<String>,
    // Serialization not skipped when None to match API response structure (string or null)
    #[serde(default)]
    pub cycle_type: Option<String>,
    // Serialization not skipped when None to match API response structure (string or null)
    #[serde(default)]
    pub proof_type: Option<String>,
    pub machines: Vec<MachineData>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct MachineData {
    pub machine: MachineConfiguration,
    pub machine_count: u64,
    pub cloud_instance: CloudInstance,
    pub cloud_instance_count: u64,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ListActiveClustersForATeamRequest {
    /// The UUID of the team
    ///
    /// * Required
    /// * Example: "team_id=550e8400-e29b-41d4-a716-446655440000"
    pub team_id: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(transparent)]
pub struct ListActiveClustersForATeamResponse {
    pub clusters: Vec<ClusterID>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ClusterID {
    /// Cluster ID (index)
    ///
    /// * Required
    pub id: u64,
}
