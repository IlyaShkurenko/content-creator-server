#

defmodule SessionSplitter do
  require Logger

  def create_chunks_from_sessions(sessions, lower_border \\ 10000, upper_border \\ 20000, overlap \\ 20) do
    IO.puts("Starting split_sessions with #{length(sessions)} sessions")

    groups = []
    current_group = []
    current_tokens = 0

    Enum.reduce(sessions, {groups, current_group, current_tokens}, fn session, {groups, current_group, current_tokens} ->
      IO.puts("Processing session with #{length(session.messages)} messages")

      session_text = Enum.join(session.messages, "\n")
      # IO.puts("Session text: #{session_text}")

      session_tokens = Tiktoken.encode_with_special_tokens("gpt-4o", session_text)
      |> elem(1)
      |> length()

      IO.puts("Session tokens: #{session_tokens}")
      IO.puts("Current group tokens: #{current_tokens}")

      if current_tokens + session_tokens <= upper_border do
        IO.puts("Adding session to current group")
        {
          groups,
          current_group ++ session.messages,
          current_tokens + session_tokens
        }
      else
        if current_tokens >= lower_border do
          IO.puts("Finalizing current group")

          # Transform current_group into the desired format before adding to groups
          new_groups = groups ++ [%{messages: current_group}]

          IO.puts("New group created, total groups: #{length(new_groups)}")

          if session_tokens > upper_border do
            IO.puts("Splitting the current session as it exceeds upper_border")
            handle_split_session(new_groups, session.messages, lower_border, upper_border, overlap)
          else
            {
              new_groups,
              session.messages,
              session_tokens
            }
          end
        else
          handle_split_session(groups, session.messages, lower_border, upper_border, overlap)
        end
      end
    end)
    |> finalize_result()
  end

  defp finalize_result({groups, current_group, _current_tokens}) do
    updated_groups =
      if current_group != [] do
        groups ++ [%{messages: current_group}]
      else
        groups
      end

    Enum.map(updated_groups, fn %{messages: messages} = group ->
      messages_text = Enum.join(messages, "\n")

      tokens =
        Tiktoken.encode_with_special_tokens("gpt-4o", messages_text)
        |> elem(1)
        |> length()

      Map.put(group, :tokens, tokens)
    end)
  end

  defp handle_split_session(groups, session_messages, lower_border, upper_border, overlap) do
    split_result = split_large_session(session_messages, lower_border, upper_border, [], 0, overlap)

    # Transform split_result into a list of maps with the desired format
    transformed_split_result = Enum.map(split_result, fn chunk -> %{messages: chunk} end)

    # Add transformed_split_result to groups
    new_groups = groups ++ transformed_split_result

    IO.puts("Split result added, total groups: #{length(new_groups)}")
    {
      new_groups,
      [],
      0
    }
  end

  def split_large_session(messages, lower_border, upper_border, current_group \\ [], current_tokens \\ 0, overlap \\ 20) do
    IO.puts("Splitting large session with #{length(messages)} messages")

    if Enum.empty?(messages) do
      IO.puts("Returning final chunk with #{length(current_group)} messages")
      [current_group]
    else
      mapped_messages = Enum.join(messages, "\n")

      session_tokens =
        Tiktoken.encode_with_special_tokens("gpt-4o", mapped_messages)
        |> elem(1)
        |> length()

      IO.puts("Session tokens for splitting: #{session_tokens}")
      IO.puts("Current group tokens in split: #{current_tokens}")

      if current_tokens + session_tokens <= upper_border do
        IO.puts("Adding entire session to the current group in split")
        [current_group ++ messages]
      else
        IO.puts("Splitting session into smaller chunks")
        {chunk, remainder} = split_messages(messages, current_group, upper_border)
        remainder = if is_list(remainder), do: remainder, else: []

        # IO.inspect(remainder, label: "Remainder")
        IO.puts("Chunk size: #{length(chunk)}, Remainder size: #{length(remainder)}")
        new_group = current_group ++ chunk

        overlap_messages = Enum.take(new_group, -overlap)

        overlap_text = Enum.join(overlap_messages, "\n")

        overlap_tokens =
          Tiktoken.encode_with_special_tokens("gpt-4o", overlap_text)
          |> elem(1)
          |> length()

          if length(remainder) > 0 do
            [new_group | split_large_session(remainder, lower_border, upper_border, overlap_messages, overlap_tokens, overlap)]
          else
            [new_group]
          end

      end
    end
  end

  defp split_messages(messages, current_group, upper_border) do
    IO.puts("Splitting messages with #{length(messages)} total messages")

    current_group_text = Enum.join(current_group, "\n")

    current_group_tokens =
      Tiktoken.encode_with_special_tokens("gpt-4o", current_group_text)
      |> elem(1)
      |> length()

    IO.puts("Current group tokens in split_messages: #{current_group_tokens}")

    Enum.reduce_while(messages, {[], current_group_tokens}, fn message, {chunk, current_tokens} ->

      message_tokens =
        Tiktoken.encode_with_special_tokens("gpt-4o", message)
        |> elem(1)
        |> length()

        IO.puts(message_tokens > upper_border)

        if message_tokens > upper_border * 2 do
          IO.puts("Large message detected with #{message_tokens} tokens, skipping.")
          {:cont, {chunk, current_tokens}}
        else
          IO.puts("Processing message with #{message_tokens} tokens")

          if current_tokens + message_tokens <= upper_border do
            IO.puts("Adding message to chunk")
            IO.inspect(message, label: "Message")
            {:cont, {[message | chunk], current_tokens + message_tokens}}
          else
            IO.puts("Stopping split at message")
            # IO.inspect(Enum.drop(messages, length(chunk)))
            IO.inspect(length(chunk))
            if length(chunk) == 0 do
              {:cont, {[message | chunk], current_tokens + message_tokens}}
            else
              {:halt, {Enum.reverse(chunk), Enum.drop(messages, length(chunk))}}
            end
          end
        end
    end)
  end
end
