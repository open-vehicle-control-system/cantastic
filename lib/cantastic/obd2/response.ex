defmodule Cantastic.OBD2.Response do
  alias Cantastic.OBD2.Parameter

  @moduledoc """
    `Cantastic.OBD2.Response` is a `Struct` used to represent one OBD2 response.

    The attributes are the following:

    * `:request_name` The OBD2 request's name, as defined in your YAML file.
    * `:mode` The OBD2 mode, as defined in your YAML file.
    * `:reception_timestamp`  The `DateTime` at which the frame was received by the kernel.
    * `:parameters` A `Map` of the parameters contained in this response.
  """

  defstruct [
    :request_name,
    :mode,
    :reception_timestamp,
    parameters: %{}
  ]

  @doc false
  def interpret(request_specification, socket_message) do
    <<mode::integer-size(8), raw_parameters::bitstring>> = socket_message.raw
    acc = %{raw_parameters: raw_parameters}
    parameters = request_specification.parameter_specifications |> Enum.reduce(acc, fn(parameter_specification, acc) ->
      {:ok, parameter, truncated_raw_parameters} = Parameter.interpret(acc.raw_parameters, parameter_specification)
      acc
        |> put_in([parameter.name], parameter)
        |> put_in([:raw_parameters], truncated_raw_parameters)
    end)
    response = %__MODULE__{
      request_name: request_specification.name,
      mode: mode,
      parameters: parameters,
      reception_timestamp: socket_message.reception_timestamp
    }
    {:ok, response}
  end
end
