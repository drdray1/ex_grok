defmodule ExGrok.UsageTest do
  use ExUnit.Case, async: true

  alias ExGrok.Fixtures
  alias ExGrok.Usage

  describe "Responses-style usage (detailed)" do
    setup do
      %{usage: Fixtures.sample_response_usage_detailed()}
    end

    test "token accessors", %{usage: u} do
      assert Usage.input_tokens(u) == 231
      assert Usage.output_tokens(u) == 957
      assert Usage.total_tokens(u) == 1188
      assert Usage.reasoning_tokens(u) == 594
      assert Usage.cached_tokens(u) == 128
    end

    test "cost_usd converts ticks to dollars", %{usage: u} do
      assert Usage.cost_usd(u) == 0.0059864
    end

    test "source and server-tool counts", %{usage: u} do
      assert Usage.sources_used(u) == 0
      assert Usage.server_tools_used(u) == 0
    end
  end

  describe "accepts a full response body, not just the usage map" do
    test "reads through the \"usage\" key" do
      resp = Fixtures.sample_response_text()
      assert Usage.input_tokens(resp) == 10
      assert Usage.output_tokens(resp) == 20
      assert Usage.total_tokens(resp) == 30
    end
  end

  describe "Chat-style usage (prompt/completion naming)" do
    test "normalizes prompt_tokens/completion_tokens" do
      usage = %{"prompt_tokens" => 5, "completion_tokens" => 7, "total_tokens" => 12}
      assert Usage.input_tokens(usage) == 5
      assert Usage.output_tokens(usage) == 7
      assert Usage.total_tokens(usage) == 12
    end

    test "reads cached tokens from prompt_tokens_details" do
      usage = %{"prompt_tokens" => 5, "prompt_tokens_details" => %{"cached_tokens" => 3}}
      assert Usage.cached_tokens(usage) == 3
    end
  end

  describe "missing fields" do
    test "return nil rather than raising" do
      assert Usage.reasoning_tokens(%{}) == nil
      assert Usage.cost_usd(%{}) == nil
      assert Usage.cached_tokens(%{"input_tokens" => 1}) == nil
      assert Usage.input_tokens("not a map") == nil
    end
  end
end
