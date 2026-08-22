defmodule ExGrok.ImagesTest do
  use ExUnit.Case, async: true

  alias ExGrok.{Fixtures, Images}

  @stub_name :images_test_stub

  describe "generate/3" do
    test "sends POST to /images/generations" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/images/generations"
        assert conn.method == "POST"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["prompt"] == "A sunset over the ocean"
        assert params["model"] == "grok-2-image"

        Req.Test.json(conn, Fixtures.sample_image_generation_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, response} = Images.generate(client, "A sunset over the ocean")
      assert length(response["data"]) == 1
    end

    test "uses custom model and options" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["model"] == "grok-imagine-image"
        assert params["n"] == 2
        assert params["response_format"] == "b64_json"

        Req.Test.json(conn, Fixtures.sample_image_b64_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _response} =
               Images.generate(client, "A cat",
                 model: "grok-imagine-image",
                 n: 2,
                 response_format: "b64_json"
               )
    end

    test "returns error on unauthorized" do
      Req.Test.expect(@stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(Fixtures.sample_error_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:error, {:unauthorized, _}} = Images.generate(client, "A cat")
    end
  end

  describe "edit/3" do
    test "sends POST to /images/edits" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/images/edits"
        assert conn.method == "POST"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["prompt"] == "Make the sky purple"
        assert params["image_url"] == "https://example.com/img.png"

        Req.Test.json(conn, Fixtures.sample_image_edit_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, response} =
               Images.edit(client, "Make the sky purple",
                 image_url: "https://example.com/img.png"
               )

      assert length(response["data"]) == 1
    end
  end

  describe "extract_images/1" do
    test "extracts image data from response" do
      response = Fixtures.sample_image_generation_response()
      images = Images.extract_images(response)
      assert length(images) == 1
      assert hd(images)["url"] == "https://example.com/generated-image.png"
    end

    test "returns empty list for invalid response" do
      assert Images.extract_images(%{}) == []
      assert Images.extract_images(nil) == []
    end
  end

  describe "extract_image_urls/1" do
    test "extracts URLs from response" do
      response = Fixtures.sample_image_generation_response()
      urls = Images.extract_image_urls(response)
      assert urls == ["https://example.com/generated-image.png"]
    end

    test "returns empty list for b64 responses" do
      response = Fixtures.sample_image_b64_response()
      urls = Images.extract_image_urls(response)
      assert urls == []
    end

    test "returns empty list for invalid response" do
      assert Images.extract_image_urls(%{}) == []
    end
  end
end
