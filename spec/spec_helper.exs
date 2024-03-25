Code.require_file("#{__DIR__}/support/test_factory.ex")

ESpec.configure fn(config) ->
  config.before fn(_tags) ->
    {:ok, _} = Application.ensure_all_started(:faker)
  end

  config.finally fn(_shared) ->
    :ok
  end
end
