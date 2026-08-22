defmodule ExGrok.LiveSmokeTest do
  @moduledoc """
  Real requests against the xAI API. Excluded by default (see `test_helper.exs`);
  run with `mix test --only live` and `XAI_API_KEY` set.

  These exist because every other test in this suite stubs the transport, so all
  of them stayed green while the Responses API rejected our structured-output
  request with a 400 on every call. Run them before tagging a release.
  """

  use ExUnit.Case, async: false

  @moduletag :live

  alias ExGrok.{Chat, Responses}

  @schema %{
    "type" => "object",
    "properties" => %{"city" => %{"type" => "string"}},
    "required" => ["city"],
    "additionalProperties" => false
  }

  setup do
    case System.get_env("XAI_API_KEY") do
      nil -> flunk("XAI_API_KEY is not set; live tests cannot run")
      key -> %{client: ExGrok.new(key), model: System.get_env("XAI_MODEL", "grok-4.5")}
    end
  end

  test "Responses API accepts text.format structured output", ctx do
    assert {:ok, resp} =
             Responses.create(ctx.client, ctx.model, "Name any city as JSON.",
               text: Responses.json_schema_text("city", @schema)
             )

    assert {:ok, %{"city" => city}} = Responses.extract_parsed(resp)
    assert is_binary(city)
  end

  test "Chat Completions accepts response_format structured output", ctx do
    assert {:ok, resp} =
             Chat.create_completion(
               ctx.client,
               ctx.model,
               [Chat.user_message("Name any city as JSON.")],
               response_format: Chat.json_schema_format("city", @schema)
             )

    assert {:ok, %{"city" => city}} = Jason.decode(ExGrok.extract_content(resp))
    assert is_binary(city)
  end

  test "the API still rejects the shapes we guard against", ctx do
    # If xAI ever starts accepting response_format on /v1/responses, our guard
    # becomes unnecessarily strict and this test tells us to relax it.
    assert {:error, {:api_error, 400, message}} =
             Responses.create(ctx.client, %{
               "model" => ctx.model,
               "input" => "hi",
               "text" => %{"format" => %{"type" => "json_schema"}}
             })

    assert is_binary(message)
  end
end
