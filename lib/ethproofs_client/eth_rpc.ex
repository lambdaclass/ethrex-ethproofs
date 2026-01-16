defmodule EthProofsClient.EthRpc do
  @moduledoc false

  use Tesla

  alias EthProofsClient.Helpers
  alias EthProofsClient.Notifications

  plug(Tesla.Middleware.Headers, [{"content-type", "application/json"}])

  @rpc_down_after_ms 60_000
  @status_table :ethproofs_eth_rpc_status
  @status_key :status

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
    url = eth_rpc_url()

    case post(url, payload) do
      {:ok, rsp} ->
        case handle_response(rsp, opts) do
          {:ok, _result} = ok ->
            record_success(url)
            ok

          {:error, reason, :responded} ->
            record_success(url)
            {:error, reason}

          {:error, reason} ->
            record_failure(url, reason)
            {:error, reason}
        end

      {:error, reason} ->
        error = Helpers.format_reason(reason)
        record_failure(url, error)
        {:error, error}
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

  defp handle_response(%{status: 200, body: body}, opts) do
    case Jason.decode(body) do
      {:ok, %{"result" => result}} ->
        value = if opts[:raw], do: Jason.encode!(result), else: result
        {:ok, value}

      {:ok, %{"error" => error}} ->
        {:error, Helpers.format_reason(error), :responded}

      {:ok, decoded} ->
        {:error, "Unexpected JSON-RPC response: #{inspect(decoded)}"}

      {:error, decode_error} ->
        {:error, "Invalid JSON response: #{inspect(decode_error)}"}
    end
  end

  defp handle_response(%{status: status, body: body}, _opts) do
    {:error, "HTTP #{status}: #{body}"}
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

  defp record_success(url) do
    status = rpc_status()

    if status.down_since_ms do
      now = now_ms()

      if status.notified? do
        Notifications.rpc_recovered(url, status.down_since_ms, now)
      end

      update_rpc_status(%{down_since_ms: nil, notified?: false, last_error: nil})
    end

    :ok
  end

  defp record_failure(url, reason) do
    now = now_ms()
    status = rpc_status()

    status =
      if is_nil(status.down_since_ms) do
        %{down_since_ms: now, notified?: false, last_error: reason}
      else
        %{status | last_error: reason}
      end

    status =
      if not status.notified? and now - status.down_since_ms >= @rpc_down_after_ms do
        Notifications.rpc_down(url, status.down_since_ms, status.last_error)
        %{status | notified?: true}
      else
        status
      end

    update_rpc_status(status)
    :ok
  end

  defp rpc_status do
    ensure_status_table()

    status =
      case :ets.lookup(@status_table, @status_key) do
        [{@status_key, status}] -> status
        _ -> %{}
      end

    Map.merge(%{down_since_ms: nil, notified?: false, last_error: nil}, status)
  end

  defp update_rpc_status(status) do
    ensure_status_table()
    :ets.insert(@status_table, {@status_key, status})
  end

  defp ensure_status_table do
    case :ets.whereis(@status_table) do
      :undefined ->
        :ets.new(@status_table, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        @status_table
    end
  end

  defp now_ms do
    System.system_time(:millisecond)
  end
end
