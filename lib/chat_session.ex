defmodule Iris.ChatSession do
  use Ecto.Schema

  # import Ecto.Changeset

  # alias Iris.PersonaAccess

  schema "chat_sessions" do
    belongs_to :persona, Iris.Persona
    # belongs_to :access, Iris.PersonaAccess
    # belongs_to :instruction_set, Iris.InstructionSet, type: :binary_id
    has_many :messages, Iris.ChatMessage, foreign_key: :session_id
    # has_many :journals, Iris.ChatSession.Journal, foreign_key: :session_id

    field :access_key, :string
    field :name, :string
    field :expires_at, :utc_datetime_usec
    field :intent, Ecto.Enum, values: [:interview]

    timestamps()
  end

  # def changeset(
  #       %PersonaAccess{persona: persona} = access,
  #       instruction_set,
  #       params \\ %{},
  #       requested_at
  #     ) do
  #   fields = [:intent]

  #   %__MODULE__{}
  #   |> cast(params, fields)
  #   |> put_assoc(:persona, persona)
  #   |> put_assoc(:access, access)
  #   |> put_assoc(:instruction_set, instruction_set)
  #   |> put_change(:name, "New Chat")
  #   |> put_change(:access_key, Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false))
  #   |> put_change(:expires_at, DateTime.add(requested_at, 365 * 86400, :second))
  # end
end
