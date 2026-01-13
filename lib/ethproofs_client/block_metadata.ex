defmodule EthProofsClient.BlockMetadata do
  @moduledoc false

  # Stores block gas used and transaction count so notifications can include them later.
  @table :ethproofs_block_metadata

  def init_table do
    ensure_table()
    :ok
  end

  def put_from_json(block_number, block_json) when is_integer(block_number) do
    with {:ok, %{"gasUsed" => gas_used, "transactions" => transactions}} <-
           Jason.decode(block_json),
         {:ok, gas_used_int} <- parse_hex_quantity(gas_used),
         true <- is_list(transactions) do
      put(block_number, %{gas_used: gas_used_int, tx_count: length(transactions)})
    else
      _ -> :error
    end
  end

  def get(block_number) when is_integer(block_number) do
    ensure_table()

    case :ets.lookup(@table, block_number) do
      [{^block_number, data}] -> {:ok, data}
      _ -> :error
    end
  end

  defp put(block_number, data) do
    ensure_table()
    :ets.insert(@table, {block_number, data})
    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        @table
    end
  end

  defp parse_hex_quantity("0x" <> hex), do: parse_hex_quantity(hex)

  defp parse_hex_quantity(hex) when is_binary(hex) do
    case Integer.parse(hex, 16) do
      {value, _} -> {:ok, value}
      :error -> :error
    end
  end

  defp parse_hex_quantity(_), do: :error
end
