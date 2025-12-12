defmodule EthProofsClient.Rpc do
  @moduledoc false
  require Logger

  use Tesla

  @output_dir "output"

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
      cluster_id: String.to_integer(EthProofsClient.Rpc.ethproofs_cluster_id())
    })
  end

  def proving_proof(block_number) do
    send_request("proofs/proving", %{
      block_number: block_number,
      cluster_id: String.to_integer(EthProofsClient.Rpc.ethproofs_cluster_id())
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
      cluster_id: String.to_integer(EthProofsClient.Rpc.ethproofs_cluster_id()),
      proving_time: proving_time,
      proving_cycles: proving_cycles,
      proof: proof
    }

    body = if verifier_id, do: Map.put(body, :verifier_id, verifier_id), else: body
    send_request("proofs/proved", body, true)
  end

  defp send_request(endpoint, body, persist_body \\ false) do
    case ethproofs_rpc_url() do
      nil ->
        Logger.warning("ETHPROOFS_RPC_URL not set, skipping RPC call to #{endpoint}")

        {:ok, :skipped}

      url ->
        url = url <> "/" <> endpoint

        encoded_body = Jason.encode!(body)

        if persist_body do
          request_body_path =
            Path.join([
              @output_dir,
              Integer.to_string(body.block_number),
              Integer.to_string(body.block_number) <>
                ".json"
            ])

          Logger.debug("Persisting request body for block #{body.block_number} to disk")

          File.write!(
            request_body_path,
            encoded_body
          )
        end

        Logger.debug("Sending request to #{url} with body: #{encoded_body}")

        {:ok, rsp} = post(url, encoded_body)

        handle_response(rsp)
    end
  end

  defp handle_response(rsp) do
    if rsp.status == 200 do
      case Jason.decode(rsp.body) do
        {:ok, %{"proof_id" => id}} ->
          {:ok, id}

        {:ok, %{"error" => error}} ->
          {:error, error}

        {:error, decode_error} ->
          {:error, "Invalid JSON response: #{decode_error}"}
      end
    else
      {:error, "HTTP #{rsp.status}: #{rsp.body}"}
    end
  end
end
