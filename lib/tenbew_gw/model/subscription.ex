defmodule TenbewGw.Model.Subscription do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query , warn: false
  alias TenbewGw.Model.{Subscription, Payment}
  alias TenbewGw.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "subscriptions" do
    field(:msisdn, :string)
    field(:status, :string)
    field(:services, :string)
    field(:validated, :boolean)

    has_many(:payments, TenbewGw.Model.Payment)

    timestamps()
  end

  @doc false
  def changeset(%Subscription{} = subscription, attrs) do
    subscription
    |> cast(attrs, [
      :msisdn,
      :status,
      :services,
      :validated
    ])
    |> validate_required([:msisdn, :status])
  end

  def create_changeset(%Subscription{} = subscription, attrs) do
    changeset(subscription, attrs)
  end

  def update_changeset(%Subscription{} = subscription, attrs) do
    subscription
      |> cast(attrs, [:msisdn, :status, :services, :validated])
  end

  def status_changeset(%Subscription{} = subscription, attrs) do
    subscription
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end

  def validated_changeset(%Subscription{} = subscription, attrs) do
    subscription
    |> cast(attrs, [:validated])
    |> validate_required([:validated])
  end

  def create_subscription(attrs \\ %{}) do
    %Subscription{}
      |> create_changeset(attrs)
      |> Repo.insert
  end

  def update_subscription(%Subscription{} = subscription, attrs \\ %{}) do
    subscription
      |> update_changeset(attrs)
      |> Repo.update()
  end

  def set_status(%Subscription{} = subscription, attrs) do
    subscription
      |> status_changeset(attrs)
      |> Repo.update()
  end

  def get!(id), do: Repo.get!(Subscription, id)
  def get(id) do
    Repo.get(Subscription, id)
  rescue
    e -> nil
  end

  def get_by_msisdn!(msisdn) do
    Subscription |> Repo.get_by!(msisdn: msisdn) |> Repo.preload([:payments])
  rescue e ->
    nil
  end
  def get_by_msisdn(msisdn) do
    from(s in Subscription, where: s.msisdn == ^msisdn)
      |> Repo.all()
      |> List.first()
      |> Repo.preload([:payments])
  rescue e ->
    nil
  end

  def get_status(msisdn) do
    s = get_by_msisdn(msisdn)
    if is_nil(s), do: nil, else: s.status
  end

  def get_service(msisdn) do
    s = get_by_msisdn(msisdn)
    if is_nil(s), do: nil, else: s.services
  end

  def validated?(msisdn) do
    s = Subscription |> Repo.get_by(msisdn: msisdn)
    if is_nil(s), do: false, else: s.validated
  end

  def exists?(msisdn) do
    s = from(s in Subscription, where: s.msisdn == ^msisdn) |> Repo.all()
    if length(s) <= 0, do: false, else: true
  end

  def set_validated(msisdn) do
    s = Subscription |> Repo.get_by(msisdn: msisdn)
    cs = validated_changeset(s, %{validated: true})
    Repo.update!(cs)
  rescue
    e -> IO.puts "set_validated/1 ERROR: #{inspect(e)}"
  end

  def get_first_subscription() do
    Subscription |> Repo.all() |> List.first()
  end

  # Payments

  def get_payments(id) do
    s = Subscription |> Repo.get(id)
    query = from p in Payment, where: p.subscription_id == ^s.id
    Repo.all(query)
  rescue e ->
    nil
  end

  def get_payments_by_msisdn(msisdn) do
    s = get_by_msisdn(msisdn)
    query = from p in Payment, where: p.msisdn == ^msisdn and p.subscription_id == ^s.id
    Repo.all(query)
  rescue e ->
    nil
  end

  def last_payment_by_subscriber(subscription) do
    query = from(p in Payment, where: p.subscription_id == ^subscription.id)
    Repo.all(query)
    |> List.first()
    rescue e -> nil
  end

  def status() do
    %{
      active:    000, # This subscriber has been taken through the double opt in process and confirmed
      pending:   100, # The subscriber has been submitted for the DOI process, but has not confirmed yet
      cancelled: 200, # The subscriber has cancelled the subscription. For purposes of development, the subscriber will be assumed to be non-existent in the database.
      unknown:   900  # anything else, not supported, unavailable
    }
  end

end
