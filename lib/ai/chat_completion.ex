defmodule Iris.AI.ChatCompletion do
  alias Iris.AI

  @chat_completions Application.compile_env!(:iris, [:chat_completions])

  @completion_models for module <- @chat_completions,
                         do: {module, Application.compile_env!(:iris, [module, :models])}

  @callback stream_chat(payload :: map(), options :: keyword(), receiver :: pid()) ::
              {:ok, reference()} | :error
  @callback complete_chat(payload :: map(), options :: keyword()) :: {:ok, binary()} | :error

  # FIXME: completion module should come from the caller.
  def stream_chat(%{model: model} = payload, options \\ [], receiver \\ self()) do
    get_completion_module(model).stream_chat(payload, options, receiver)
  end

  def complete_chat(%{model: model} = payload, options \\ []) do
    get_completion_module(model).complete_chat(payload, options)
  end

  def models() do
    Enum.flat_map(@completion_models, fn {_module, models} -> models end)
  end

  def thinking_messages() do
    [
      "Hmmmn.",
      "Ehh hmmm.",
      "I see.",
      "Alright.",
      "Let me think...",
      "Got it.",
      "Okay, give me a moment.",
      "Interesting.",
      "Sure thing.",
      "Understood.",
      "Alright.",
      "Noted.",
      "Let’s see ...",
      "Right.",
      "Okay then."
    ]
  end

  for {module, models} <- @completion_models, model <- models do
    defp get_completion_module(unquote(model)) do
      unquote(module)
    end
  end

  def completion_stream(payload, options \\ [], receiver \\ self()) do
    case stream_chat(payload, options, receiver) do
      {:ok, request_ref} ->
        request_ref
        |> to_event_stream()
        |> accumulate_function_partials()

      :error ->
        [{:error, :request_failure}]
    end
  end

  def to_event_stream(request_ref, timeout \\ 5000) do
    Stream.unfold(request_ref, fn ref ->
      if ref do
        receive do
          {:stream, ^ref, {:done, _} = data} ->
            {data, nil}

          {:stream, ^ref, data} ->
            {data, ref}
        after
          timeout -> {{:error, :timeout}, nil}
        end
      end
    end)
  end

  def accumulate_function_partials(event_stream) do
    Stream.transform(event_stream, %{current_function: nil}, fn event, state ->
      current_function = state.current_function

      case event do
        {:function_partial, index, {id, name, args}} ->
          # For now we TRUST that OpenAI will send each function separately.
          {events, current_function} =
            case current_function do
              # When no current function, we emit no events, but initialize a function.
              nil ->
                {[], %AI.Function{index: index}}

              # When there is current function, we emit that function, but initialize a function.
              %{index: current_index} when current_index != index ->
                {[{:function, AI.Function.decode(current_function)}], %AI.Function{index: index}}

              # When the partial is for the current function, we continue streaming it.
              %{index: current_index} when current_index == index ->
                {[], current_function}
            end

          current_function = AI.Function.stream(current_function, id, name, args)

          {events, Map.put(state, :current_function, current_function)}

        _ ->
          function_event =
            if current_function do
              {:function, AI.Function.decode(current_function)}
            end

          {List.wrap(function_event) ++ [event], Map.put(state, :current_function, nil)}
      end
    end)
  end

  @function_sets %{
    "wip" => [AI.WIP.Noop],
    "video" => [AI.Video.Suggestion],
    "cloud" => [AI.Cloud.SearchVideo, AI.Cloud.EditVideo],
    "persona" => [AI.Persona.SearchAvatar],
    "user" => [AI.User.Weather]
  }

  # for {_set_name, fun_modules} <- @function_sets,
  #     fun_module <- fun_modules,
  #     name = fun_module.name() do
  #   def get_function_module(unquote(name)) do
  #     {:ok, unquote(fun_module)}
  #   end
  # end

  def get_function_module(_) do
    {:error, :not_found}
  end

  @spec get_functions!(binary()) :: list(module())
  def get_functions!(set_name) when is_binary(set_name) do
    Map.fetch!(@function_sets, set_name)
  end

  @spec function_sets() :: list(String.t())
  def function_sets(), do: Map.keys(@function_sets)

  def guestimate_tokens(text) when is_binary(text) do
    token_byte_size = 4

    text
    |> byte_size()
    |> Kernel./(token_byte_size)
    |> trunc()
  end
end
