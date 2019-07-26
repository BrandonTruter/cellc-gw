defmodule TenbewGw.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :msisdn, :string
      add :status, :string
      add :services, :string
      add :validated, :boolean, default: false, null: true

      timestamps()
    end
  end
end
