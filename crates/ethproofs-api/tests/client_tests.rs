use ethproofs_api::{EthProofsClient, rpc};

#[tokio::test]
async fn test_get_block_details() {
    let api_key = std::env::var("ETH_PROOFS_API_KEY")
        .unwrap_or_else(|_| panic!("ETH_PROOFS_API_KEY must be set"));

    let client = EthProofsClient::staging(api_key).unwrap();

    let block_number = rpc::common::NumberOrString::Int(23982100);

    let block_details = client.get_block_details(block_number).await.unwrap();

    println!("{block_details:#?}");
}

#[tokio::test]
async fn test_list_clusters() {
    let api_key = std::env::var("ETH_PROOFS_API_KEY")
        .unwrap_or_else(|_| panic!("ETH_PROOFS_API_KEY must be set"));

    let client = EthProofsClient::staging(api_key).unwrap();

    let request = rpc::clusters::ListClustersRequest {};

    let clusters_list = client.list_clusters(request).await.unwrap();

    println!("{clusters_list:#?}");
}

#[tokio::test]
async fn test_list_active_clusters_for_team() {
    let api_key = std::env::var("ETH_PROOFS_API_KEY")
        .unwrap_or_else(|_| panic!("ETH_PROOFS_API_KEY must be set"));
    let team_id = match std::env::var("TEAM_ID") {
        Ok(id) => id,
        Err(_) => return, // skip test if not set
    };
    let client = EthProofsClient::staging(api_key).unwrap();
    let request = rpc::clusters::ListActiveClustersForATeamRequest { team_id };
    let result = client.list_active_clusters_for_team(request).await;
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_download_proof() {
    let api_key = std::env::var("ETH_PROOFS_API_KEY")
        .unwrap_or_else(|_| panic!("ETH_PROOFS_API_KEY must be set"));
    let proof_id = match std::env::var("PROOF_ID") {
        Ok(id) => id,
        Err(_) => return, // skip test if not set
    };
    let client = EthProofsClient::staging(api_key).unwrap();
    let result = client.download_proof(&proof_id).await;
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_list_proofs() {
    let api_key = std::env::var("ETH_PROOFS_API_KEY")
        .unwrap_or_else(|_| panic!("ETH_PROOFS_API_KEY must be set"));

    let client = EthProofsClient::staging(api_key).unwrap();

    let request = rpc::proofs::ListProofsRequest {
        block: None,
        clusters: None,
        limit: 10,
        offset: 0,
    };

    let proofs_list = client.list_proofs(request).await.unwrap();

    println!("{proofs_list:#?}");
}

#[tokio::test]
async fn test_list_cloud_instances() {
    let api_key = std::env::var("ETH_PROOFS_API_KEY")
        .unwrap_or_else(|_| panic!("ETH_PROOFS_API_KEY must be set"));

    let client = EthProofsClient::staging(api_key).unwrap();

    let request = rpc::cloud_instances::ListCloudInstancesRequest { provider: None };

    let cloud_instances_list = client.list_cloud_instances(request).await.unwrap();

    println!("{cloud_instances_list:#?}");
}
