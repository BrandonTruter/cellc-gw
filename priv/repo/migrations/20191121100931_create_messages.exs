defmodule TenbewGw.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :message_id, :string
      add :message, :string
      add :subscription_id, references(:subscriptions, on_delete: :nothing, type: :binary_id)

      timestamps()
    end

    create index(:messages, [:subscription_id])
  end
end
