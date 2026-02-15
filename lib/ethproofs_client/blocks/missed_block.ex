defmodule EthProofsClient.Blocks.MissedBlock do
  @moduledoc """
  Ecto schema for missed/failed blocks.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "missed_blocks" do
    field :block_number, :integer
    field :failed_at, :utc_datetime
    field :stage, Ecto.Enum, values: [:input_generation, :proving, :unknown]
    field :reason, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:block_number, :failed_at]
  @optional_fields [:stage, :reason]

  def changeset(missed_block, attrs) do
    missed_block
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:block_number)
  end
end
