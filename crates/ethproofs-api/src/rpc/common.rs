use std::fmt::Display;

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct MachineConfiguration {
    /// CPU model name
    ///
    /// * Required
    /// * Max length: 200 characters
    pub cpu_model: String,
    /// Number of CPU cores
    ///
    /// * Required
    /// * Must be greater than 0
    pub cpu_cores: u64,
    /// List of GPU models
    ///
    /// * Optional
    /// * Each model max length: 200 characters
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gpu_models: Option<Vec<String>>,
    /// Number of each GPU model
    ///
    /// * Optional
    /// * Each count must be greater than 0
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gpu_count: Option<Vec<u64>>,
    /// Memory per GPU in GB
    ///
    /// * Optional
    /// * Each size must be greater than 0
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gpu_memory_gb: Option<Vec<u64>>,
    /// Memory size per module in GB
    ///
    /// * Required
    /// * Each size must be greater than 0
    pub memory_size_gb: Vec<u64>,
    /// Number of memory modules
    ///
    /// * Required
    /// * Each count must be greater than 0
    pub memory_count: Vec<u64>,
    /// Type of memory modules
    ///
    /// * Required
    /// * Each type max length: 200 characters
    pub memory_type: Vec<String>,
    /// Total storage size in GB
    ///
    /// * Must be greater than 0
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub storage_size_gb: Option<u64>,
    /// Total compute power in teraflops
    ///
    /// * Optional
    /// * Must be greater than 0
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total_tera_flops: Option<u64>,
    /// Network configuration between machines
    ///
    /// * Optional
    /// * Max length: 500 characters
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub network_between_machines: Option<String>,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(untagged)]
pub enum BlockNumber {
    Int(u64),
    String(String),
}

impl Display for BlockNumber {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BlockNumber::Int(num) => write!(f, "{num}"),
            BlockNumber::String(s) => write!(f, "{s}"),
        }
    }
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
pub struct CloudInstance {
    pub id: u64,
    pub provider: String,
    pub instance_name: String,
    pub region: String,
    pub hourly_price: f64,
    #[serde(default, rename = "cpu_arch")]
    pub cpu_architecture: Option<String>,
    pub cpu_cores: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cpu_effective_cores: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cpu_name: Option<String>,
    pub memory: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gpu_count: Option<u64>,
    #[serde(default, rename = "gpu_arch")]
    pub gpu_architecture: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gpu_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gpu_memory: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mobo_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub disk_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub disk_space: Option<u64>,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub snapshot_date: Option<String>,
}
