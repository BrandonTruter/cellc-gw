defmodule TenbewGw.Repo.Migrations.CreatePayments do
  use Ecto.Migration

  def change do
    create table(:payments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :status, :string
      add :msisdn, :string
      add :amount, :integer
      add :currency, :string
      add :service_type, :string
      add :paid_at, :naive_datetime
      add :paid, :boolean, default: false, null: true
      add :subscription_id, references(:subscriptions, on_delete: :nothing, type: :binary_id)

      timestamps()
    end

    create index(:payments, [:subscription_id])
  end
end
