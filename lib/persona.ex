defmodule Iris.Persona do
  use Ecto.Schema

  # import Ecto.Changeset

  @default_model "anthropic/claude-3.5-sonnet"

  def default_model(), do: @default_model

  @type t :: %__MODULE__{
          public_id: Ecto.UUID.t(),
          name: String.t(),
          instructions: [String.t()],
          model: String.t(),
          archived_at: DateTime.t(),
          next_owner_notified_at: DateTime.t(),
          # instruction_sets: [Iris.InstructionSet.t()],
          # speech_synthesis: %ElevenLabs{} | %ResembleAI{}
        }

  # @languages Enum.map(Iris.Locale.language_codes(), &String.to_atom/1)
  @monetizations [:owner_funded, :consumer_funded]

  schema "personas" do
    field(:public_id, Ecto.UUID, autogenerate: true)
    field(:name, :string)
    field(:instructions, {:array, :string})
    field(:model, :string, default: @default_model)
    field(:archived_at, :utc_datetime)
    field(:published_at, :utc_datetime_usec)
    field(:next_owner_notified_at, :utc_datetime_usec)
    field(:main, :boolean, default: false)
    # field :default_language, Ecto.Enum, values: @languages, default: :en
    field :points, :integer, default: 0
    field :energy, :integer, default: 0
    field :monetization, Ecto.Enum, values: @monetizations
    field :initiation_prompt, :string, default: "Follow up or initiate the conversation"

    # belongs_to :user, Iris.Accounts.User, references: :public_id, type: Ecto.UUID

    # has_one :active_enrollment, Iris.Persona.Enrollment,
    #   foreign_key: :persona_id,
    #   references: :public_id,
    #   where: [status: :active],
    #   defaults: [status: :active],
    #   on_replace: :update

    # has_one(:active_avatar, Iris.Persona.Avatar,
    #   foreign_key: :persona_id,
    #   references: :public_id,
    #   where: [active: true],
    #   defaults: [active: true],
    #   on_replace: :update
    # )

    # has_one(:active_voice, Iris.Persona.Voice,
    #   foreign_key: :persona_id,
    #   references: :public_id,
    #   where: [active: true],
    #   defaults: [active: true],
    #   on_replace: :update
    # )

    # has_many(:instruction_sets, Iris.InstructionSet, preload_order: [desc: :inserted_at])

    # field(:speech_synthesis, Ecto.SchemaUnion,
    #   type_field: :service,
    #   schemata: %{
    #     "resemble_ai" => ResembleAI,
    #     "eleven_labs" => ElevenLabs
    #   }
    # )

    field(:avatar, :any, virtual: true)

    # embeds_one(:model_settings, Iris.Persona.ModelSettings, on_replace: :update)

    timestamps()
  end
end
