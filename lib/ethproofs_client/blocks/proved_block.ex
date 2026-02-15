defmodule EthProofsClient.Blocks.ProvedBlock do
  @moduledoc """
  Ecto schema for proved blocks.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "proved_blocks" do
    field :block_number, :integer
    field :proved_at, :utc_datetime
    field :proving_duration_seconds, :integer
    field :input_generation_duration_seconds, :integer

    timestamps(type: :utc_datetime)
  end

  @required_fields [:block_number, :proved_at]
  @optional_fields [:proving_duration_seconds, :input_generation_duration_seconds]

  def changeset(proved_block, attrs) do
    proved_block
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:block_number)
  end
end
