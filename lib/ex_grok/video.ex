defmodule ExGrok.Video do
  @moduledoc """
  xAI Grok Imagine **video generation** (`/v1/videos`).

  Video generation is asynchronous: `generate/3` returns a `request_id`
  immediately, then you poll `get/2` (or `poll/3`) until the job reaches a
  terminal status and exposes a `video.url`.

  ## Example

      client = ExGrok.Client.new("xai-your-api-key")

      {:ok, %{"request_id" => id}} =
        ExGrok.Video.generate(client, "A neon city at night, cinematic", duration: 8)

      {:ok, done} = ExGrok.Video.poll(client, id)
      ExGrok.Video.extract_video_url(done)
      # => "https://vidgen.x.ai/.../video.mp4"

  ## Image-to-video

      ExGrok.Video.generate(client, "pan across the scene",
        image: "https://example.com/frame.jpg", resolution: "720p")
  """

  alias ExGrok.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @default_model "grok-imagine-video"
  @allowed_opts ~w(duration aspect_ratio resolution image reference_images video)a
  @terminal_statuses ~w(done failed expired)

  @doc """
  Starts a video generation job (`POST /videos/generations`).

  Returns `{:ok, %{"request_id" => id, ...}}`.

  ## Options
    - `:model` — video model (default `"grok-imagine-video"`)
    - `:duration` — seconds (e.g. 1–15)
    - `:aspect_ratio` — e.g. `"16:9"`, `"9:16"`, `"1:1"`
    - `:resolution` — `"480p"`, `"720p"`, `"1080p"`
    - `:image` — source image URL for image-to-video
    - `:reference_images` — list of reference image URLs
    - `:video` — source video URL for editing/extension
  """
  @spec generate(client(), String.t(), keyword()) :: response()
  def generate(client, prompt, opts \\ []) do
    params = build_params(prompt, opts)

    client
    |> Req.post(url: "/videos/generations", json: params)
    |> Client.handle_response()
  end

  @doc "Retrieves a video job by id (`GET /videos/:id`)."
  @spec get(client(), String.t()) :: response()
  def get(client, request_id) when is_binary(request_id) do
    client
    |> Req.get(url: "/videos/#{request_id}")
    |> Client.handle_response()
  end

  @doc """
  Polls `get/2` until the job reaches a terminal status
  (`"done"`/`"failed"`/`"expired"`).

  Returns `{:ok, job}` on a terminal status, `{:error, :timeout}` if
  `:max_attempts` is exhausted, or any error from `get/2`.

  ## Options
    - `:interval_ms` — delay between polls (default `3000`)
    - `:max_attempts` — maximum polls (default `60`)
  """
  @spec poll(client(), String.t(), keyword()) :: response() | {:error, :timeout}
  def poll(client, request_id, opts \\ []) do
    interval = Keyword.get(opts, :interval_ms, 3000)
    max_attempts = Keyword.get(opts, :max_attempts, 60)
    do_poll(client, request_id, interval, max_attempts)
  end

  @doc "The generated video URL, or nil."
  @spec extract_video_url(map()) :: String.t() | nil
  def extract_video_url(%{"video" => %{"url" => url}}) when is_binary(url), do: url
  def extract_video_url(_), do: nil

  @doc "The job status (`pending`/`done`/`failed`/`expired`), or nil."
  @spec extract_status(map()) :: String.t() | nil
  def extract_status(%{"status" => status}), do: status
  def extract_status(_), do: nil

  # ---------------------------------------------------------------------------

  defp do_poll(_client, _id, _interval, attempts) when attempts <= 0, do: {:error, :timeout}

  defp do_poll(client, id, interval, attempts) do
    case get(client, id) do
      {:ok, body} ->
        if extract_status(body) in @terminal_statuses do
          {:ok, body}
        else
          Process.sleep(interval)
          do_poll(client, id, interval, attempts - 1)
        end

      error ->
        error
    end
  end

  defp build_params(prompt, opts) do
    base = %{"model" => Keyword.get(opts, :model, @default_model), "prompt" => prompt}

    opts
    |> Keyword.take(@allowed_opts)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.reduce(base, fn {key, value}, acc -> Map.put(acc, Atom.to_string(key), value) end)
  end
end
