defmodule Iris.Personas do
  require Logger

  import Ecto.Query

  alias Iris.{
    # Accounts,
    # Accounts.User,
    # ChatSession,
    # InstructionSet,
    Persona,
    # PersonaAccess,
    # Personas.Interview,
    Repo
  }
  # alias Ecto.Multi

  def all_public_ids() do
    Persona
    |> where([persona], is_nil(persona.archived_at))
    |> order_by(desc: :main, asc: :name)
    |> select([persona], %{public_id: persona.public_id, name: persona.name})
    |> Repo.all()
  end

end
