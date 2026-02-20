defmodule EthProofsClient.BlockMetadataTest do
  use ExUnit.Case, async: false

  alias EthProofsClient.BlockMetadata

  setup do
    BlockMetadata.init_table()
    BlockMetadata.clear()
    :ok
  end

  describe "put_from_json/2 and get/1" do
    test "stores and retrieves valid block metadata" do
      block_json =
        Jason.encode!(%{
          "gasUsed" => "0xe4e1c0",
          "transactions" => ["0xabc", "0xdef", "0x123"]
        })

      assert :ok = BlockMetadata.put_from_json(100, block_json)
      assert {:ok, %{gas_used: 15_000_000, tx_count: 3}} = BlockMetadata.get(100)
    end

    test "handles gas_used without 0x prefix" do
      block_json =
        Jason.encode!(%{
          "gasUsed" => "e4e1c0",
          "transactions" => []
        })

      assert :ok = BlockMetadata.put_from_json(200, block_json)
      assert {:ok, %{gas_used: 15_000_000, tx_count: 0}} = BlockMetadata.get(200)
    end

    test "returns :error for invalid JSON" do
      assert :error = BlockMetadata.put_from_json(300, "not json")
    end

    test "returns :error when gasUsed missing" do
      block_json = Jason.encode!(%{"transactions" => []})
      assert :error = BlockMetadata.put_from_json(400, block_json)
    end

    test "returns :error when transactions missing" do
      block_json = Jason.encode!(%{"gasUsed" => "0x1"})
      assert :error = BlockMetadata.put_from_json(500, block_json)
    end

    test "returns :error when transactions is not a list" do
      block_json = Jason.encode!(%{"gasUsed" => "0x1", "transactions" => 42})
      assert :error = BlockMetadata.put_from_json(600, block_json)
    end

    test "returns :error for unparseable hex" do
      block_json = Jason.encode!(%{"gasUsed" => "notahex", "transactions" => []})
      assert :error = BlockMetadata.put_from_json(700, block_json)
    end
  end

  describe "get/1" do
    test "returns :error for unknown block" do
      assert :error = BlockMetadata.get(999_999)
    end
  end

  describe "clear/0" do
    test "removes all stored metadata" do
      block_json = Jason.encode!(%{"gasUsed" => "0x1", "transactions" => ["0xa"]})
      BlockMetadata.put_from_json(100, block_json)
      BlockMetadata.put_from_json(200, block_json)

      assert {:ok, _} = BlockMetadata.get(100)
      assert :ok = BlockMetadata.clear()
      assert :error = BlockMetadata.get(100)
      assert :error = BlockMetadata.get(200)
    end
  end
end
