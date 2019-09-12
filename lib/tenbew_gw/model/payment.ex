defmodule TenbewGw.Model.Payment do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  alias TenbewGw.Model.{Payment, Subscription}
  alias TenbewGw.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "payments" do
    field(:msisdn, :string)
    field(:status, :string)
    field(:amount, :integer)
    field(:currency, :string)
    field(:service_type, :string)
    field(:paid_at, :naive_datetime)
    field(:paid, :boolean, default: false)

    belongs_to(:subscription, TenbewGw.Model.Subscription, foreign_key: :subscription_id)

    timestamps()
  end

  @doc false
  def changeset(%Payment{} = payment, attrs) do
    payment
      |> cast(attrs, [
        :msisdn,
        :status,
        :amount,
        :currency,
        :service_type,
        :subscription_id,
        :paid_at,
        :paid
      ])
      |> foreign_key_constraint(:subscription_id)
      |> validate_required([:msisdn, :amount, :service_type])
  end

  def update_changeset(%Payment{} = payment, attrs) do
    payment
      |> cast(attrs, [:msisdn, :status, :amount, :service_type, :paid])
      |> validate_required([:msisdn])
  end

  def create_payment(attrs \\ %{}) do
    %Payment{}
      |> changeset(attrs)
      |> Repo.insert
  end

  def update_payment(%Payment{} = payment, attrs) do
    payment
      |> update_changeset(attrs)
      |> Repo.update()
  end

  def list_payments(), do: Repo.all(Payment)

  def get_payment(id), do: Repo.get!(Payment, id)

  def get_payment_by_msisdn(msisdn),
    do: Repo.get_by(Payment, msisdn: msisdn)

  def get_payments_by_subscriber(subscription_id) do
    query = from p in Payment, where: p.subscription_id == ^subscription_id
    Repo.all(query)
  end

  def last_payment_by_subscriber(subscription_id) do
    get_payments_by_subscriber(subscription_id) |> List.last()
  rescue
    e -> nil
  end

  def is_paid(subscription_id) do
    payments =
      from(p in Payment,
        where: fragment("inserted_at > NOW() at time zone 'utc' - INTERVAL '1 day'"),
        where: p.subscription_id == ^subscription_id,
        where: p.paid == true
      )
      |> Repo.all()
      # |> List.last()
    case length(payments) do
      1 -> true
      _ -> false
    end
  rescue
    e -> false
  end

  def get_first_payment() do
    Payment |> Repo.all() |> List.first()
  end

  def get_last_payment() do
    Payment |> Repo.all() |> List.last()
  end

  def exists?(msisdn) do
    payments = from(p in Payment, where: p.msisdn == ^msisdn) |> Repo.all()
    if length(payments) <= 0, do: false, else: true
  end

end
