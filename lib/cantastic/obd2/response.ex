defmodule Cantastic.OBD2.Response do
  alias Cantastic.OBD2.Parameter
  defstruct [
    :request_name,
    :mode,
    parameters: %{}
  ]

  def interpret(request_specification, raw_response) do
    <<mode::integer-size(8), raw_parameters::binary>> = raw_response

    acc = %{raw_parameters: raw_parameters}
    parameters = request_specification.parameter_specifications |> Enum.reduce(acc, fn(parameter_specification, acc) ->
      {:ok, parameter, truncated_raw_parameters} = Parameter.interpret(raw_parameters, parameter_specification)
      acc
        |> put_in([parameter.name], parameter)
        |> put_in([:raw_parameters], truncated_raw_parameters)
    end)
    response = %__MODULE__{frame | request_name: request_specification.name, mode: mode, parameters: parameters}
    {:ok, response}
  end
end
