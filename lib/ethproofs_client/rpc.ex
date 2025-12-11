defmodule EthProofsClient.Rpc do
  @moduledoc false
  require Logger

  use Tesla

  plug(Tesla.Middleware.Headers, [
    {"content-type", "application/json"},
    {"authorization", "Bearer " <> ethproofs_api_key()}
  ])

  def ethproofs_rpc_url do
    Application.get_env(:ethproofs_client, :ethproofs_rpc_url)
  end

  def ethproofs_api_key do
    Application.get_env(:ethproofs_client, :ethproofs_api_key)
  end

  def ethproofs_cluster_id do
    Application.get_env(:ethproofs_client, :ethproofs_cluster_id)
  end

  def queued_proof(block_number) do
    send_request("proofs/queued", %{
      block_number: block_number,
      cluster_id: EthProofsClient.Rpc.ethproofs_cluster_id()
    })
  end

  def proving_proof(block_number) do
    send_request("proofs/proving", %{
      block_number: block_number,
      cluster_id: EthProofsClient.Rpc.ethproofs_cluster_id()
    })
  end

  def proved_proof(
        block_number,
        proving_time,
        proving_cycles,
        proof,
        verifier_id \\ nil
      ) do
    body = %{
      block_number: block_number,
      cluster_id: EthProofsClient.Rpc.ethproofs_cluster_id(),
      proving_time: proving_time,
      proving_cycles: proving_cycles,
      proof: proof
    }

    body = if verifier_id, do: Map.put(body, :verifier_id, verifier_id), else: body
    send_request("proofs/proved", body)
  end

  defp send_request(endpoint, body) do
    case ethproofs_rpc_url() do
      nil ->
        Logger.warning("ETHPROOFS_RPC_URL not set, skipping RPC call to #{endpoint}")

        {:ok, :skipped}

      url ->
        url = url <> "/" <> endpoint

        {:ok, rsp} = post(url, Jason.encode!(body))

        handle_response(rsp)
    end
  end

  defp handle_response(rsp) do
    case Jason.decode!(rsp.body) do
      %{"proof_id" => id} ->
        {:ok, id}

      %{"error" => error} ->
        {:error, error}
    end
  end
end
