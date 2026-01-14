defmodule EthProofsClient.EthRpc do
  @moduledoc false

  use Tesla

  @request_timeout 30_000

  plug(Tesla.Middleware.Timeout, timeout: @request_timeout)
  plug(Tesla.Middleware.Headers, [{"content-type", "application/json"}])

  def eth_rpc_url do
    Application.get_env(:ethproofs_client, :eth_rpc_url) ||
      raise("ETH_RPC_URL not set in config")
  end

  def debug_execution_witness(block_number, opts \\ []) do
    send_request("debug_executionWitness", [normalize_block_number(block_number)], opts)
  end

  def get_block_by_number(block_number, full_tx \\ false, opts \\ []) do
    send_request("eth_getBlockByNumber", [normalize_block_number(block_number), full_tx], opts)
  end

  def get_latest_block_number(opts \\ []) do
    with {:ok, value} <- send_request("eth_blockNumber", [], opts) do
      value = if opts[:raw], do: Jason.decode!(value), else: value
      {:ok, String.to_integer(String.replace_prefix(value, "0x", ""), 16)}
    end
  end

  @doc """
  Returns `{:ok, {block_number, timestamp}}` for the latest block.
  The timestamp is in Unix seconds.
  """
  def get_latest_block_info do
    with {:ok, block} <- get_block_by_number("latest") do
      block_number = String.to_integer(String.replace_prefix(block["number"], "0x", ""), 16)
      timestamp = String.to_integer(String.replace_prefix(block["timestamp"], "0x", ""), 16)
      {:ok, {block_number, timestamp}}
    end
  end

  defp send_request(method, args, opts) do
    payload = build_payload(method, args)

    case post(eth_rpc_url(), payload) do
      {:ok, rsp} ->
        handle_response(rsp, opts)

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_payload(method, params) do
    %{
      jsonrpc: "2.0",
      id: Enum.random(1..9_999_999),
      method: method,
      params: params
    }
    |> Jason.encode!()
  end

  defp handle_response(rsp, opts) do
    case Jason.decode!(rsp.body) do
      %{"result" => result} ->
        if opts[:raw] do
          {:ok, Jason.encode!(result)}
        else
          {:ok, result}
        end

      %{"error" => error} ->
        {:error, error}
    end
  end

  defp normalize_block_number(block_number) when is_integer(block_number) do
    "0x" <> Integer.to_string(block_number, 16)
  end

  # Special block tags like "latest", "pending", "earliest", "safe", "finalized"
  defp normalize_block_number(block_number)
       when block_number in ~w(latest pending earliest safe finalized) do
    block_number
  end

  defp normalize_block_number(block_number) when is_binary(block_number) do
    if String.starts_with?(block_number, "0x") do
      block_number
    else
      "0x" <> block_number
    end
  end
end
