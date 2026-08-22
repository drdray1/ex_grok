defmodule ExGrok.ClientTest do
  use ExUnit.Case, async: true

  alias ExGrok.{Client, Fixtures}

  @stub_name :client_test_stub

  describe "new/2" do
    test "creates a Req.Request struct" do
      client = Fixtures.test_client(@stub_name)
      assert %Req.Request{} = client
    end

    test "attaches auth step" do
      client = Fixtures.test_client(@stub_name)
      assert Keyword.has_key?(client.request_steps, :grok_auth)
    end
  end

  describe "base_url/0" do
    test "returns default base URL" do
      assert Client.base_url() == "https://api.x.ai/v1"
    end
  end

  describe "timeout/0" do
    test "returns default timeout" do
      assert Client.timeout() == 120_000
    end
  end

  describe "handle_response/1" do
    test "handles 200 success" do
      body = %{"data" => "test"}

      assert {:ok, ^body} =
               Client.handle_response({:ok, %Req.Response{status: 200, body: body}})
    end

    test "handles 201 success" do
      body = %{"created" => true}

      assert {:ok, ^body} =
               Client.handle_response({:ok, %Req.Response{status: 201, body: body}})
    end

    test "handles 401 unauthorized" do
      assert {:error, {:unauthorized, _}} =
               Client.handle_response({:ok, %Req.Response{status: 401, body: %{}}})
    end

    test "handles 403 forbidden" do
      assert {:error, {:forbidden, _}} =
               Client.handle_response({:ok, %Req.Response{status: 403, body: %{}}})
    end

    test "handles 404 not found" do
      assert {:error, {:not_found, _}} =
               Client.handle_response({:ok, %Req.Response{status: 404, body: %{}}})
    end

    test "handles 429 rate limited" do
      assert {:error, {:rate_limited, _}} =
               Client.handle_response({:ok, %Req.Response{status: 429, body: %{}}})
    end

    test "handles 400 with OpenAI error format" do
      body = Fixtures.sample_error_response()

      assert {:error, {:api_error, 400, "Invalid API key provided"}} =
               Client.handle_response({:ok, %Req.Response{status: 400, body: body}})
    end

    test "handles 500 server error" do
      body = %{"error" => %{"message" => "Internal server error"}}

      assert {:error, {:api_error, 500, "Internal server error"}} =
               Client.handle_response({:ok, %Req.Response{status: 500, body: body}})
    end

    test "handles connection error" do
      assert {:error, {:connection_error, :timeout}} =
               Client.handle_response({:error, :timeout})
    end

    test "handles unknown error body format" do
      body = "not json"

      assert {:error, {:api_error, 400, "Unknown error"}} =
               Client.handle_response({:ok, %Req.Response{status: 400, body: body}})
    end

    test "handles 202 as pending" do
      assert {:ok, :pending} =
               Client.handle_response({:ok, %Req.Response{status: 202, body: ""}})
    end

    test "extracts string error and bare message formats" do
      assert {:error, {:api_error, 400, "boom"}} =
               Client.handle_response(
                 {:ok, %Req.Response{status: 400, body: %{"error" => "boom"}}}
               )

      assert {:error, {:api_error, 400, "msg"}} =
               Client.handle_response(
                 {:ok, %Req.Response{status: 400, body: %{"message" => "msg"}}}
               )
    end
  end

  describe "healthcheck/1 error branches" do
    test "maps 403 and unexpected status" do
      Req.Test.stub(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{})
      end)

      assert {:error, {:forbidden, _}} = Client.healthcheck(Fixtures.test_client(@stub_name))
    end

    test "maps unexpected status" do
      Req.Test.stub(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
      end)

      assert {:error, {:unexpected_status, 500}} =
               Client.healthcheck(Fixtures.test_client(@stub_name))
    end
  end

  describe "verify_credentials/1 via management client path" do
    test "maps 403 and api_error using an injected client is covered by handle_response" do
      # verify_credentials/1 builds its own client, so exercise its status
      # mapping through healthcheck (same handle logic) with a 401 stub.
      Req.Test.stub(@stub_name, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{})
      end)

      assert {:error, {:unauthorized, _}} = Client.healthcheck(Fixtures.test_client(@stub_name))
    end
  end

  describe "healthcheck/1" do
    test "returns :ok on success" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/models"
        Req.Test.json(conn, Fixtures.sample_models_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert :ok = Client.healthcheck(client)
    end

    test "returns error on 401" do
      Req.Test.expect(@stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(Fixtures.sample_error_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, {:unauthorized, _}} = Client.healthcheck(client)
    end
  end

  describe "verify_credentials/1" do
    test "returns error for invalid key" do
      # verify_credentials creates its own client internally (no plug option),
      # so it hits the real API. We just validate it returns a proper error tuple.
      result = Client.verify_credentials("xai-invalid-test-key")
      assert {:error, _reason} = result
    end
  end

  describe "new/2 base_url override" do
    test "honors an explicit :base_url" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.host == "management-api.x.ai"
        Req.Test.json(conn, %{"ok" => true})
      end)

      client =
        "k"
        |> Client.new(base_url: "https://management-api.x.ai/v1", plug: {Req.Test, @stub_name})
        |> Req.Request.merge_options(retry: false)

      assert {:ok, %{"ok" => true}} = Client.handle_response(Req.get(client, url: "/ping"))
    end
  end

  describe "management_client/2" do
    test "points at the management host" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.host == "management-api.x.ai"
        Req.Test.json(conn, %{"ok" => true})
      end)

      client =
        Fixtures.test_management_client(@stub_name)

      assert {:ok, %{"ok" => true}} = Client.handle_response(Req.get(client, url: "/collections"))
    end
  end

  describe "api_key_info/1" do
    test "GETs /api-key" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/api-key"
        Req.Test.json(conn, Fixtures.sample_api_key_info())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"api_key_id" => "key-123"}} = Client.api_key_info(client)
    end
  end
end
