defmodule TenbewGw.Model.Message do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  alias TenbewGw.Model.{Message, Subscription}
  alias TenbewGw.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "messages" do
    field(:message_id, :string)
    field(:message, :string)

    belongs_to(:subscription, TenbewGw.Model.Subscription, foreign_key: :subscription_id)

    timestamps()
  end

  @doc false
  def changeset(%Message{} = message, attrs) do
    message
      |> cast(attrs, [
        :message,
        :message_id,
        :subscription_id
      ])
      |> foreign_key_constraint(:subscription_id)
      |> validate_required([:message, :message_id])
  end

  def create_message(attrs \\ %{}) do
    %Message{}
      |> changeset(attrs)
      |> Repo.insert
  end

  def list_messages(), do: Repo.all(Message)

  def get_message(id), do: Repo.get!(Message, id)

  def get_messages_by_subscriber(subscription_id) do
    query = from m in Message, where: m.subscription_id == ^subscription_id
    Repo.all(query)
    |> List.last()
  end

  def get_messages_by_msisdn(msisdn) do
    subscription =
      from(s in Subscription, where: s.msisdn == ^msisdn)
      |> Repo.all()
      |> List.last()

    query = from m in Message, where: m.subscription_id == ^subscription.id
    Repo.all(query)
  end

  def test_message_creation() do
    sub = Subscription |> Repo.all() |> List.first()
    attrs = %{
      message_id: "001",
      subscription_id: sub.id,
      message: default_message
    }
    create_message(attrs)
  end

  defp default_message do
    "Welcome to QQ-Tenbew Games. Experience our world. Thank you for subscribing. Service costs 5 Rands a day charged daily"
  end

end
