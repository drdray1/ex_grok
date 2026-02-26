defmodule ExGrok.AuthTest do
  use ExUnit.Case, async: true

  alias ExGrok.Auth

  describe "attach/2" do
    test "appends grok_auth request step" do
      request = Req.new()
      result = Auth.attach(request, "xai-test-key")

      assert Keyword.has_key?(result.request_steps, :grok_auth)
    end

    test "stores api key in options" do
      request = Req.new()
      result = Auth.attach(request, "xai-test-key")

      assert result.options[:grok_api_key] == "xai-test-key"
    end

    test "sets authorization header on request" do
      Req.Test.expect(:auth_test, fn conn ->
        auth_header = Plug.Conn.get_req_header(conn, "authorization")
        assert auth_header == ["Bearer xai-test-key"]
        Req.Test.json(conn, %{"ok" => true})
      end)

      request =
        Req.new(plug: {Req.Test, :auth_test})
        |> Auth.attach("xai-test-key")

      Req.get!(request, url: "/test")
    end

    test "skips auth header when api key is nil" do
      Req.Test.expect(:auth_nil_test, fn conn ->
        auth_header = Plug.Conn.get_req_header(conn, "authorization")
        assert auth_header == []
        Req.Test.json(conn, %{"ok" => true})
      end)

      request =
        Req.new(plug: {Req.Test, :auth_nil_test})
        |> Auth.attach(nil)

      Req.get!(request, url: "/test")
    end
  end
end
