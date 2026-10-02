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

  ## Editing and extending

  `edit/3` restyles or changes an existing video; `extend/3` continues one from
  its last frame. Both return a `request_id` you poll exactly like `generate/3`:

      {:ok, %{"request_id" => id}} =
        ExGrok.Video.edit(client, "make it snow", video: "https://example.com/in.mp4")

  Any image or video argument may be a URL string (or `data:` URI), which is
  wrapped as `%{"url" => ...}`, or a ready-made map sent as-is.
  """

  alias ExGrok.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @default_model "grok-imagine-video"
  @terminal_statuses ~w(done failed expired)

  # Fields forwarded verbatim (atom option -> string key) per endpoint.
  @generate_opts ~w(duration aspect_ratio resolution generate_audio reference_audios user storage_options)a
  @edit_opts ~w(user storage_options)a
  @extend_opts ~w(duration storage_options)a

  @doc """
  Starts a video generation job (`POST /videos/generations`).

  Returns `{:ok, %{"request_id" => id, ...}}`.

  ## Options
    - `:model` — video model (default `"grok-imagine-video"`; also
      `"grok-imagine-video-1.5"`)
    - `:duration` — seconds (e.g. 1–15)
    - `:aspect_ratio` — e.g. `"16:9"`, `"9:16"`, `"1:1"`
    - `:resolution` — `"480p"`, `"720p"`, or `"1080p"` (1080p needs
      `grok-imagine-video-1.5`; reference-to-video is capped at 720p)
    - `:generate_audio` — boolean
    - `:image` — start image for image-to-video
    - `:last_frame` — image to end on (`grok-imagine-video-1.5` only)
    - `:keyframes` — up to 4 mid-video anchors as `{image, timestamp_seconds}`
      tuples (`grok-imagine-video-1.5` only)
    - `:reference_images` — 1–7 images for reference-to-video
    - `:reference_audios` — up to 3 audio refs, e.g. `[%{"voice_id" => "..."}]`
    - `:user` — end-user identifier for abuse monitoring
    - `:storage_options` — persist to the Files API, e.g. `%{"filename" => "out.mp4"}`

  To edit or extend an existing video use `edit/3` or `extend/3`.
  """
  @spec generate(client(), String.t(), keyword()) :: response()
  def generate(client, prompt, opts \\ []) do
    if Keyword.has_key?(opts, :video) do
      raise ArgumentError,
            "ExGrok.Video.generate/3 no longer takes :video; use edit/3 or extend/3"
    end

    params =
      prompt
      |> base_params(opts, @generate_opts)
      |> put_ref("image", Keyword.get(opts, :image))
      |> put_ref("last_frame", Keyword.get(opts, :last_frame))
      |> put_refs("reference_images", Keyword.get(opts, :reference_images))
      |> put_keyframes(Keyword.get(opts, :keyframes))

    post(client, "/videos/generations", params)
  end

  @doc """
  Starts a video edit job (`POST /videos/edits`) on an existing video.

  Returns `{:ok, %{"request_id" => id, ...}}`; poll it like `generate/3`.

  ## Options
    - `:video` — source video (required)
    - `:model`, `:user`, `:storage_options` — as for `generate/3`
  """
  @spec edit(client(), String.t(), keyword()) :: response()
  def edit(client, prompt, opts) do
    params =
      prompt
      |> base_params(opts, @edit_opts)
      |> put_ref("video", Keyword.fetch!(opts, :video))

    post(client, "/videos/edits", params)
  end

  @doc """
  Starts a video extension job (`POST /videos/extensions`), continuing an
  existing video from its last frame.

  Returns `{:ok, %{"request_id" => id, ...}}`; poll it like `generate/3`.

  ## Options
    - `:video` — source video (required)
    - `:duration` — seconds to add
    - `:model`, `:storage_options` — as for `generate/3`
  """
  @spec extend(client(), String.t(), keyword()) :: response()
  def extend(client, prompt, opts) do
    params =
      prompt
      |> base_params(opts, @extend_opts)
      |> put_ref("video", Keyword.fetch!(opts, :video))

    post(client, "/videos/extensions", params)
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

  defp post(client, url, params) do
    client
    |> Req.post(url: url, json: params)
    |> Client.handle_response()
  end

  defp base_params(prompt, opts, allowed) do
    base = %{"model" => Keyword.get(opts, :model, @default_model), "prompt" => prompt}

    opts
    |> Keyword.take(allowed)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.reduce(base, fn {key, value}, acc -> Map.put(acc, Atom.to_string(key), value) end)
  end

  defp put_ref(params, _key, nil), do: params
  defp put_ref(params, key, ref), do: Map.put(params, key, media_ref(ref))

  defp put_refs(params, _key, nil), do: params
  defp put_refs(params, key, refs), do: Map.put(params, key, Enum.map(refs, &media_ref/1))

  defp put_keyframes(params, nil), do: params

  defp put_keyframes(params, keyframes) do
    Map.put(params, "keyframes", Enum.map(keyframes, &keyframe/1))
  end

  defp keyframe({image, seconds}), do: %{"image" => media_ref(image), "timestamp_s" => seconds}
  defp keyframe(%{} = keyframe), do: keyframe

  defp media_ref(%{} = ref), do: ref
  defp media_ref(url) when is_binary(url), do: %{"url" => url}
end
