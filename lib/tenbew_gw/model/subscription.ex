defmodule TenbewGw.Model.Subscription do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query , warn: false
  alias TenbewGw.Model.Subscription
  alias TenbewGw.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "subscriptions" do
    field(:msisdn, :string)
    field(:status, :string)
    field(:services, :string)
    field(:validated, :boolean)

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

  @doc false
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

  def get!(id), do: Repo.get!(Subscription, id)
  def get(id) do
    Repo.get(Subscription, id)
  rescue
    e -> nil
  end

  def get_by_msisdn(msisdn) do
    query = from(s in Subscription, where: s.msisdn == ^msisdn)
    # subscriptions = Repo.all(query)
    # if length(subscriptions) > 1, do: List.first(subscriptions), else: subscriptions
    Repo.all(query) |> List.first()
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
    # if is_nil(s), do: false, else: true
  end

  def set_validated(msisdn) do
    s = Subscription |> Repo.get_by(msisdn: msisdn)
    cs = validated_changeset(s, %{validated: true})
    Repo.update!(cs)
  rescue
    e -> IO.puts "set_validated/1 ERROR: #{inspect(e)}"
  end


end
