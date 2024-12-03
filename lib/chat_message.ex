defmodule Iris.ChatMessage do
  use Ecto.Schema

  import Ecto.Changeset

  alias Iris.{
    # Accounts,
    Persona
  }

  defmodule Content do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:type, Ecto.Enum, values: [:text, :image])
      field(:value, :string)
    end

    def changeset(content, params) do
      fields = [:type, :value]

      content
      |> cast(params, fields)
      |> validate_required(fields)
    end
  end

  schema "chat_messages" do
    belongs_to(:session, Iris.ChatSession)
    embeds_one(:content, Content)

    field(:public_id, Ecto.UUID, autogenerate: true)
    field(:actor_id, :integer)
    field(:actor_role, Ecto.Enum, values: [:persona, :user])

    timestamps()
  end

  def insert_changeset(session, actor, params) do
    %__MODULE__{}
    |> cast(params, [])
    |> cast_embed(:content, required: true)
    |> put_assoc(:session, session)
    |> put_actor(actor)
  end

  defp put_actor(changeset, %Persona{id: persona_id}) do
    changeset
    |> put_change(:actor_role, :persona)
    |> put_change(:actor_id, persona_id)
  end

  # defp put_actor(changeset, %Accounts.User{id: user_id}) do
  #   changeset
  #   |> put_change(:actor_role, :user)
  #   |> put_change(:actor_id, user_id)
  # end

  @remember_this_intent_types ["remember this", "Remember this", "Kom ihåg", "kom ihåg", "R:"]
  @intent_types ["reply", "initiation", "draw", "sketch", "remember"] ++
                  @remember_this_intent_types

  def intent_types, do: @intent_types
  def remember_this_intent_types, do: @remember_this_intent_types

  # def new_request(session, %Iris.Accounts.User{id: user_id}) do
  #   %__MODULE__{
  #     public_id: Ecto.UUID.generate(),
  #     actor_role: :user,
  #     actor_id: user_id,
  #     session: session
  #   }
  # end

  # def me?(
  #       %__MODULE__{actor_role: :user, actor_id: actor_id},
  #       %Accounts.User{id: actor_id}
  #     ) do
  #   true
  # end

  def me?(_, _), do: false

  def determine_intent(%{type: "draw", content: prompt}) do
    {:image_generation, Iris.OpenAI, prompt}
  end

  def determine_intent("draw:" <> prompt) do
    {:image_generation, Iris.OpenAI, prompt}
  end

  def determine_intent(%{type: "sketch", content: prompt}) do
    {:image_generation, Iris.StabilityAI, prompt}
  end

  def determine_intent("sketch:" <> prompt) do
    {:image_generation, Iris.StabilityAI, prompt}
  end

  def determine_intent(%{type: "remember", content: instruction}) do
    {:instruction_insertion, instruction}
  end

  for prefix <- @remember_this_intent_types do
    def determine_intent(%{type: "reply", content: unquote(prefix) <> instruction}) do
      instruction =
        instruction
        |> String.trim_leading(":")
        |> String.trim_leading(",")
        |> String.trim()

      {:instruction_insertion, instruction}
    end
  end

  def determine_intent(%{type: "reply"}) do
    :text_completion
  end

  def determine_intent(_) do
    :text_completion
  end

  # @emojis :iris
  #         |> Application.app_dir("/priv/emoji.json")
  #         |> File.read!()
  #         |> Jason.decode!()
  #         |> MapSet.new()

  # def to_ssml(%__MODULE__{content: %{type: :text, value: content}}) do
  #   spoken_content = sanitize_content(content)

  #   {:ok,
  #    """
  #    <speak>
  #      <resemble:emotion pitch="0.7" intensity="0.5" pace="0.6">#{spoken_content}</resemble:emotion>
  #    </speak>
  #    """}
  # end

  # def to_ssml(_), do: :error

  # @symbols_to_remove ~r/[@#\$%\*\^~]/
  # def sanitize_content(content) do
  #   content =
  #     content
  #     |> String.graphemes()
  #     |> Enum.reject(&MapSet.member?(@emojis, &1))
  #     |> Enum.join()
  #     |> to_plain_text()

  #   Regex.replace(@symbols_to_remove, content, "")
  # end

  # def to_plain_text(text) do
  #   case EarmarkParser.as_ast(text) do
  #     {:ok, ast, _} ->
  #       parse(ast)

  #     _ ->
  #       text
  #   end
  # end

  # defp parse([]), do: ""
  # defp parse(argument) when is_binary(argument), do: argument
  # defp parse([argument]) when is_binary(argument), do: argument

  # defp parse([argument | tail]) when is_binary(argument) do
  #   argument <> parse(tail)
  # end

  # defp parse([{"code", [{_, "markdown"}], [arguments], _} | tail]) do
  #   to_plain_text(arguments) <> parse(tail)
  # end

  # defp parse([{_operator, _, arguments, _} | tail]) do
  #   parse(arguments) <> parse(tail)
  # end
end
