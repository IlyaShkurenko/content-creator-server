defmodule Iris.ChatSessions do
  import Ecto.Query

  alias Iris.{
    ChatMessage,
    ChatSession,
    Persona,
    Repo
    # ResembleAI,
    # ElevenLabsAI
  }

  # alias Ecto.Multi

  def retrieve_chat_messages() do
    Iris.ChatMessage
    |> where([message], message.content["type"] == ^:text)
    |> Repo.all()
  end

  # def fetch_messages_by_persona(public_id) do
  #   from(
  #     persona in Persona,
  #     join: session in ChatSession,
  #     on: session.persona_id == persona.id,
  #     join: message in ChatMessage,
  #     on: message.session_id == session.id,
  #     where: persona.public_id == ^public_id,
  #     order_by: [asc: session.inserted_at, asc: message.inserted_at],
  #     limit: 10,
  #     select: %{
  #       persona: persona,
  #       session: session,
  #       message: message
  #     }
  #   )
  #   |> Repo.all()
  # end
  # def fetch_messages_by_persona(public_id) do
  #   query =
  #     from(
  #       session in ChatSession,
  #       join: message in ChatMessage,
  #       on: message.session_id == session.id,
  #       join: persona in Persona,
  #       on: session.persona_id == persona.id,
  #       where: persona.public_id == ^public_id,
  #       group_by: [session.id, session.inserted_at],
  #       order_by: [asc: session.inserted_at],
  #       limit: 2,
  #       select: %{
  #         session_id: session.id,
  #         session_created_at: session.inserted_at,
  #         total_messages: count(message.id),
  #         messages: fragment(
  #           "JSON_AGG(JSON_BUILD_OBJECT('content', ?, 'actor_role', ?))",
  #           message.content,
  #           message.actor_role
  #         )
  #       }
  #     )

  #   Repo.all(query)
  # end
  def retrieve_journals_messages_by_persona(public_id) do
    # A Journal is a group of consecutive messages where each message is sent at least one hour after the previous one.
    # If the interval between messages exceeds one hour, a new Journal is started.

    import Ecto.Query

    per_page = 10  # Number of journals per page

    # Base query
    base_query =
      from(
        p in Persona,
        join: s in ChatSession, on: s.persona_id == p.id,
        join: m in ChatMessage, on: m.session_id == s.id,
        where: p.public_id == ^public_id,
        where: not fragment("?->>'value' LIKE 'data:image/%;base64,%'", m.content),
        select: %{
          m | # Select all fields from m (ChatMessage)
          prev_inserted_at: fragment("LAG(?) OVER (ORDER BY ?)", m.inserted_at, m.inserted_at)
        }
      )

    # grouped_messages CTE
    grouped_messages =
      from(
        m in subquery(base_query),
        select_merge: %{
          journal_break: fragment(
            """
            CASE
              WHEN ? IS NULL OR EXTRACT(EPOCH FROM (? - ?)) > 3600 THEN 1
              ELSE 0
            END
            """,
            m.prev_inserted_at,
            m.inserted_at,
            m.prev_inserted_at
          )
        }
      )

    # final_groups CTE
    final_groups =
      from(
        m in subquery(grouped_messages),
        select_merge: %{
          journal_id: fragment(
            "SUM(?) OVER (ORDER BY ?)",
            m.journal_break,
            m.inserted_at
          )
        }
      )

    # Subquery to count total journals
    total_journals_query =
      from(
        m in subquery(final_groups),
        select: fragment("COUNT(DISTINCT ?)", m.journal_id)
      )

    # Fetch total number of journals
    total_journals = Repo.one(total_journals_query)

    total_pages = Float.ceil(total_journals / per_page) |> trunc()

    # Prepare the final query without limit and offset
    base_final_query =
      from(
        m in subquery(final_groups),
        group_by: m.journal_id,
        select: %{
          journal_id: m.journal_id,
          journal_start_time: fragment("MIN(?)", m.inserted_at),
          journal_end_time: fragment("MAX(?)", m.inserted_at),
          total_messages: fragment("COUNT(?)", m.id),
          messages: fragment(
            """
            JSON_AGG(
              JSON_BUILD_OBJECT(
                'content', ?,
                'actor_role', ?,
                'created_at', ?
              ) ORDER BY ?
            )
            """,
            m.content,
            m.actor_role,
            m.inserted_at,
            m.inserted_at
          )
        },
        order_by: fragment("MIN(?)", m.inserted_at)
      )

    # Fetch paginated results
    results = Enum.reduce(1..total_pages, [], fn page, acc ->
      offset = (page - 1) * per_page

      paginated_query =
        base_final_query
        |> limit(^per_page)
        |> offset(^offset)

      page_results = Repo.all(paginated_query)
      acc ++ page_results
    end)

    results
  end



  def retrieve_sessions_messages_by_persona(public_id) do
    base_query =
      from(
        session in ChatSession,
        join: message in ChatMessage,
        on: message.session_id == session.id,
        join: persona in Persona,
        on: session.persona_id == persona.id,
        where: persona.public_id == ^public_id,
        where: not fragment("?->>'value' LIKE 'data:image/%;base64,%'", message.content),
        group_by: [session.id, session.inserted_at],
        order_by: [asc: session.inserted_at],
        select: %{
          session_id: session.id,
          session_created_at: session.inserted_at,
          total_messages: count(message.id),
          messages: fragment(
            """
            JSON_AGG(
              JSON_BUILD_OBJECT('content', ?, 'actor_role', ?)
              ORDER BY ? ASC
            )
            """,
            message.content,
            message.actor_role,
            message.inserted_at
          )
        }
      )


    total_sessions =
      from(session in subquery(base_query), select: count("*"))
      |> Repo.one()

    per_page = 100
    total_pages = Float.ceil(total_sessions / per_page) |> trunc()
    # per_page = 5
    # total_pages = 1
    all_messages = []
    IO.inspect(total_pages, label: "Total Pages")

    Enum.reduce(1..total_pages, all_messages, fn page, acc ->
      IO.inspect(page, label: "Page")
      paginated_query =
        base_query
        |> limit(^per_page)
        |> offset((^page - 1) * ^per_page)

      acc ++ Repo.all(paginated_query)
    end)
  end
end
