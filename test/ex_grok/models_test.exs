defmodule ExGrok.ModelsTest do
  use ExUnit.Case, async: true

  alias ExGrok.{Fixtures, Models}

  @stub_name :models_test_stub

  describe "list_models/1" do
    test "returns models on success" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/models"
        assert conn.method == "GET"
        Req.Test.json(conn, Fixtures.sample_models_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, response} = Models.list_models(client)
      assert response["object"] == "list"
      assert length(response["data"]) == 3
    end

    test "returns error on unauthorized" do
      Req.Test.expect(@stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(Fixtures.sample_error_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :unauthorized} = Models.list_models(client)
    end
  end

  describe "get_model/2" do
    test "returns model on success" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/models/grok-3-mini"
        assert conn.method == "GET"
        Req.Test.json(conn, Fixtures.sample_model_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, model} = Models.get_model(client, "grok-3-mini")
      assert model["id"] == "grok-3-mini"
    end

    test "returns not_found for unknown model" do
      Req.Test.expect(@stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"error" => %{"message" => "Model not found"}})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, :not_found} = Models.get_model(client, "nonexistent")
    end
  end

  describe "extract_models/1" do
    test "extracts models list from response" do
      response = Fixtures.sample_models_response()
      models = Models.extract_models(response)
      assert length(models) == 3
      assert hd(models)["id"] == "grok-3"
    end

    test "returns empty list for invalid response" do
      assert Models.extract_models(%{}) == []
      assert Models.extract_models(nil) == []
    end
  end

  describe "extract_model_ids/1" do
    test "extracts model IDs from response" do
      response = Fixtures.sample_models_response()
      ids = Models.extract_model_ids(response)
      assert ids == ["grok-3", "grok-3-mini", "grok-4-fast"]
    end

    test "returns empty list for invalid response" do
      assert Models.extract_model_ids(%{}) == []
    end
  end

  describe "known_models/0" do
    test "includes current Grok models" do
      known = Models.known_models()
      assert "grok-4.5" in known
      assert "grok-4-fast" in known
      assert "grok-2-image" in known
    end
  end
end
