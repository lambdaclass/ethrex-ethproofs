defmodule EthProofsClient.Repo.Migrations.CreateBlocksTables do
  use Ecto.Migration

  def change do
    create table(:proved_blocks) do
      add :block_number, :integer, null: false
      add :proved_at, :utc_datetime, null: false
      add :proving_duration_seconds, :integer
      add :input_generation_duration_seconds, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:proved_blocks, [:block_number])
    create index(:proved_blocks, [:proved_at])

    create table(:missed_blocks) do
      add :block_number, :integer, null: false
      add :failed_at, :utc_datetime, null: false
      add :stage, :string
      add :reason, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:missed_blocks, [:block_number])
    create index(:missed_blocks, [:failed_at])
  end
end
