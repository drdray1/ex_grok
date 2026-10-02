defmodule ExGrok.Images do
  @moduledoc """
  xAI Grok Imagine **image generation and editing** (`/v1/images`).

  ## Examples

      client = ExGrok.Client.new("xai-your-api-key")

      {:ok, response} = ExGrok.Images.generate(client, "A sunset over the ocean")
      urls = ExGrok.Images.extract_image_urls(response)

      {:ok, response} =
        ExGrok.Images.generate(client, "A lighthouse at dusk",
          aspect_ratio: "16:9",
          resolution: "2k"
        )

  ## Editing

  Pass one source image with `:image`, or several (multi-reference editing)
  with `:images`. Each may be a public URL or a `data:` URI:

      {:ok, response} =
        ExGrok.Images.edit(client, "Make the sky purple",
          image: "https://example.com/photo.png"
        )

      {:ok, response} =
        ExGrok.Images.edit(client, "Put the cat from <IMAGE_1> on the sofa in <IMAGE_2>",
          images: ["https://example.com/cat.png", "https://example.com/sofa.png"]
        )
  """

  alias ExGrok.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @default_model "grok-imagine-image"

  # Request fields forwarded verbatim (atom option -> string key).
  @passthrough_opts ~w(n response_format aspect_ratio resolution quality output_format user storage_options)a

  @doc """
  Generates images from a text prompt (`POST /images/generations`).

  ## Options

    - `:model` - Image model (default: `"grok-imagine-image"`; others include
      `"grok-imagine-image-2.0"` and `"grok-imagine-image-quality"`)
    - `:n` - Number of images to generate (default: 1)
    - `:response_format` - `"url"` or `"b64_json"` (default: `"url"`)
    - `:aspect_ratio` - `"1:1"`, `"16:9"`, `"9:16"`, `"4:3"`, `"3:4"`, `"3:2"`,
      `"2:3"`, `"2:1"`, `"1:2"`, `"19.5:9"`, `"9:19.5"`, `"20:9"`, `"9:20"`,
      or `"auto"` (the default; the model picks)
    - `:resolution` - `"1k"` or `"2k"`
    - `:quality` - `"low"` or `"medium"` (`grok-imagine-image-2.0` only)
    - `:output_format` - output image encoding
    - `:user` - end-user identifier for abuse monitoring
    - `:storage_options` - persist the result to the Files API, e.g.
      `%{"filename" => "out.png", "public_url" => true}`

  ## Examples

      {:ok, response} = ExGrok.Images.generate(client, "A cat in space")
      urls = ExGrok.Images.extract_image_urls(response)

      {:ok, response} = ExGrok.Images.generate(client, "A cat in space",
        n: 2,
        aspect_ratio: "1:1",
        response_format: "b64_json"
      )
  """
  @spec generate(client(), String.t(), keyword()) :: response()
  def generate(client, prompt, opts \\ []) do
    params = build_params(prompt, opts)

    client
    |> Req.post(url: "/images/generations", json: params)
    |> Client.handle_response()
  end

  @doc """
  Edits one or more images based on a text prompt (`POST /images/edits`).

  Accepts every option `generate/3` does, plus:

    - `:image` - the source image: a URL or `data:` URI string, or a ready-made
      map (e.g. `%{"url" => ..., "type" => "image_url"}`) sent as-is
    - `:images` - a list of source images for multi-reference editing; refer to
      them in the prompt as `<IMAGE_1>`, `<IMAGE_2>`, ...
    - `:image_url` - deprecated alias for `:image`

  `:image` and `:images` are mutually exclusive.

  ## Examples

      {:ok, response} = ExGrok.Images.edit(client, "Make the sky purple",
        image: "https://example.com/image.png"
      )
  """
  @spec edit(client(), String.t(), keyword()) :: response()
  def edit(client, prompt, opts \\ []) do
    params = build_edit_params(prompt, opts)

    client
    |> Req.post(url: "/images/edits", json: params)
    |> Client.handle_response()
  end

  @doc """
  Extracts image data from response.

  ## Examples

      iex> extract_images(%{"data" => [%{"url" => "https://..."}]})
      [%{"url" => "https://..."}]
  """
  @spec extract_images(map()) :: list(map())
  def extract_images(%{"data" => data}) when is_list(data), do: data
  def extract_images(_), do: []

  @doc """
  Extracts image URLs from response.

  ## Examples

      iex> extract_image_urls(%{"data" => [%{"url" => "https://example.com/img.png"}]})
      ["https://example.com/img.png"]
  """
  @spec extract_image_urls(map()) :: list(String.t())
  def extract_image_urls(response), do: pluck(response, "url")

  @doc """
  Extracts base64 image payloads from a `response_format: "b64_json"` response.

  ## Examples

      iex> extract_image_b64(%{"data" => [%{"b64_json" => "aGk="}]})
      ["aGk="]
  """
  @spec extract_image_b64(map()) :: list(String.t())
  def extract_image_b64(response), do: pluck(response, "b64_json")

  defp pluck(response, key) do
    response
    |> extract_images()
    |> Enum.map(& &1[key])
    |> Enum.reject(&is_nil/1)
  end

  defp build_params(prompt, opts) do
    base = %{"prompt" => prompt, "model" => Keyword.get(opts, :model, @default_model)}

    opts
    |> Keyword.take(@passthrough_opts)
    |> Enum.reduce(base, fn {key, value}, acc -> maybe_put(acc, key, value) end)
  end

  defp build_edit_params(prompt, opts) do
    image = Keyword.get(opts, :image) || Keyword.get(opts, :image_url)
    images = Keyword.get(opts, :images)

    if image && images do
      raise ArgumentError, "pass either :image or :images to ExGrok.Images.edit/3, not both"
    end

    prompt
    |> build_params(opts)
    |> maybe_put(:image, image && image_ref(image))
    |> maybe_put(:images, images && Enum.map(images, &image_ref/1))
  end

  defp image_ref(%{} = ref), do: ref
  defp image_ref(url) when is_binary(url), do: %{"url" => url, "type" => "image_url"}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, Atom.to_string(key), value)
end
