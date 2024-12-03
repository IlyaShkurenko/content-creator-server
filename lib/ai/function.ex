defmodule Iris.AI.Function do
  @type message() :: String.t()
  @type status() :: atom()
  @type reason() :: %{
          status: status(),
          message: String.t()
        }

  @type action_reply() :: {:action, action_name :: atom(), action :: map()}

  @type result() ::
          {:noreply, any()}
          | {:error, reason()}
          | {:reply, action_reply(), any()}
  @type validation_result() :: {:ok, arguments :: map()} | {:error, reason()}
  @type json_schema() :: map()

  @callback execute(arguments :: map(), context :: map()) :: result()
  @callback validate(arguments :: map()) :: validation_result()
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback parameters() :: json_schema()

  defstruct [
    :id,
    :index,
    :name,
    :encoded_args,
    :args,
    :result
  ]

  @spec execute(%Iris.AI.Function{}, context :: map()) :: result()
  def execute(%Iris.AI.Function{name: name, args: arguments}, context) do
    case Iris.AI.ChatCompletion.get_function_module(name) do
      {:ok, function_module} ->
        function_module.execute(arguments, context)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec validate(%Iris.AI.Function{}) :: validation_result()
  def validate(%Iris.AI.Function{name: name, args: arguments}) do
    case Iris.AI.ChatCompletion.get_function_module(name) do
      {:ok, function_module} ->
        function_module.validate(arguments)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stream(%__MODULE__{} = function, id, name, args) do
    %__MODULE__{
      function
      | id: function.id || id,
        name: "#{function.name}#{name}",
        encoded_args: "#{function.encoded_args}#{args}"
    }
  end

  def decode(%__MODULE__{encoded_args: encoded_args} = function) do
    %{function | args: Jason.decode!(encoded_args)}
  end

  def put_result(function, result) do
    %__MODULE__{function | result: result}
  end
end
