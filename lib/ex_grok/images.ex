defmodule ExGrok.Images do
  @moduledoc """
  xAI Grok API - Image generation operations.

  Provides functions to generate and edit images using Grok image models.

  ## Examples

      client = ExGrok.Client.new("xai-your-api-key")

      {:ok, response} = ExGrok.Images.generate(client, "A sunset over the ocean")
      urls = ExGrok.Images.extract_image_urls(response)
  """

  alias ExGrok.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Generates images from a text prompt.

  ## Options

    - `:model` - Image model (default: `"grok-2-image"`)
    - `:n` - Number of images to generate (default: 1)
    - `:response_format` - `"url"` or `"b64_json"` (default: `"url"`)

  ## Examples

      {:ok, response} = ExGrok.Images.generate(client, "A cat in space")
      urls = ExGrok.Images.extract_image_urls(response)

      {:ok, response} = ExGrok.Images.generate(client, "A cat in space",
        model: "grok-2-image",
        n: 2,
        response_format: "b64_json"
      )
  """
  @spec generate(client(), String.t(), keyword()) :: response()
  def generate(client, prompt, opts \\ []) do
    params = build_generate_params(prompt, opts)

    client
    |> Req.post(url: "/images/generations", json: params)
    |> Client.handle_response()
  end

  @doc """
  Edits an image based on a text prompt.

  ## Options

    - `:model` - Image model (default: `"grok-2-image"`)
    - `:image_url` - URL of the image to edit
    - `:n` - Number of images to generate (default: 1)
    - `:response_format` - `"url"` or `"b64_json"` (default: `"url"`)

  ## Examples

      {:ok, response} = ExGrok.Images.edit(client, "Make the sky purple",
        image_url: "https://example.com/image.png"
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
  def extract_image_urls(response) do
    response
    |> extract_images()
    |> Enum.map(& &1["url"])
    |> Enum.reject(&is_nil/1)
  end

  defp build_generate_params(prompt, opts) do
    %{"prompt" => prompt, "model" => Keyword.get(opts, :model, "grok-2-image")}
    |> maybe_put(:n, Keyword.get(opts, :n))
    |> maybe_put(:response_format, Keyword.get(opts, :response_format))
  end

  defp build_edit_params(prompt, opts) do
    %{"prompt" => prompt, "model" => Keyword.get(opts, :model, "grok-2-image")}
    |> maybe_put(:image_url, Keyword.get(opts, :image_url))
    |> maybe_put(:n, Keyword.get(opts, :n))
    |> maybe_put(:response_format, Keyword.get(opts, :response_format))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, Atom.to_string(key), value)
end
