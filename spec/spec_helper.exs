Code.require_file("#{__DIR__}/support/test_factory.ex")
Code.require_file("#{__DIR__}/support/fake_socket.ex")

ESpec.configure fn(config) ->
  config.before fn(_tags) ->
    {:ok, _} = Application.ensure_all_started(:faker)

    case Cantastic.FakeSocket.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> Cantastic.FakeSocket.reset()
    end
  end

  config.finally fn(_shared) ->
    :ok
  end
end
