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
        assert params["model"] == "grok-imagine-image"
        assert Map.keys(params) |> Enum.sort() == ["model", "prompt"]

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

    test "forwards Imagine options" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["aspect_ratio"] == "16:9"
        assert params["resolution"] == "2k"
        assert params["quality"] == "low"
        assert params["user"] == "u-1"
        assert params["storage_options"] == %{"filename" => "out.png"}
        refute Map.has_key?(params, "bogus")

        Req.Test.json(conn, Fixtures.sample_image_generation_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Images.generate(client, "A lighthouse",
                 model: "grok-imagine-image-2.0",
                 aspect_ratio: "16:9",
                 resolution: "2k",
                 quality: "low",
                 user: "u-1",
                 storage_options: %{"filename" => "out.png"},
                 bogus: true
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
    test "sends POST to /images/edits with the image as an image_url object" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/images/edits"
        assert conn.method == "POST"

        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["prompt"] == "Make the sky purple"
        assert params["model"] == "grok-imagine-image"
        assert params["image"] == %{"url" => "https://example.com/img.png", "type" => "image_url"}
        refute Map.has_key?(params, "image_url")

        Req.Test.json(conn, Fixtures.sample_image_edit_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, response} =
               Images.edit(client, "Make the sky purple", image: "https://example.com/img.png")

      assert length(response["data"]) == 1
    end

    test "maps the deprecated :image_url option onto image" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["image"] == %{"url" => "https://example.com/img.png", "type" => "image_url"}
        Req.Test.json(conn, Fixtures.sample_image_edit_response())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = Images.edit(client, "x", image_url: "https://example.com/img.png")
    end

    test "sends multiple references under images and passes maps through" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)

        assert params["images"] == [
                 %{"url" => "https://ex/a.png", "type" => "image_url"},
                 %{"file_id" => "file-1"}
               ]

        assert params["aspect_ratio"] == "1:1"
        refute Map.has_key?(params, "image")
        Req.Test.json(conn, Fixtures.sample_image_edit_response())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, _} =
               Images.edit(client, "combine <IMAGE_1> and <IMAGE_2>",
                 images: ["https://ex/a.png", %{"file_id" => "file-1"}],
                 aspect_ratio: "1:1"
               )
    end

    test "rejects :image together with :images" do
      client = Fixtures.test_client(@stub_name)

      assert_raise ArgumentError, fn ->
        Images.edit(client, "x", image: "https://ex/a.png", images: ["https://ex/b.png"])
      end
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

  describe "extract_image_b64/1" do
    test "extracts base64 payloads" do
      assert Images.extract_image_b64(%{"data" => [%{"b64_json" => "aGk="}, %{"url" => "u"}]}) ==
               ["aGk="]

      assert Images.extract_image_b64(%{}) == []
    end
  end
end
