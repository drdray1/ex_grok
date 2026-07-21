defmodule ExGrok.Realtime.Connection do
  @moduledoc """
  Live WebSocket connection for the xAI **Voice Agent / realtime** API,
  built on `Mint.WebSocket`.

  This is the integration counterpart to the pure `ExGrok.Realtime` codec: it
  opens `wss://api.x.ai/v1/realtime`, streams client events up, and invokes an
  `on_event` callback for each decoded server event. Build the event maps with
  `ExGrok.Realtime` and send them with `send_event/2` (or the
  `append_audio/2` / `commit/1` / `create_response/2` conveniences).

  See `ExGrok.Realtime` for a full usage example.
  """

  use GenServer
  require Logger

  alias ExGrok.Realtime

  @default_host "api.x.ai"
  @default_path "/v1/realtime"
  @default_model "grok-voice-latest"

  @doc """
  Opens a realtime WebSocket session.

  ## Options
    - `:api_key` (required) — xAI API key
    - `:on_event` (required) — `(map -> any)` callback invoked per server event
    - `:model` — realtime model (default `"grok-voice-latest"`)
    - `:host`, `:path` — override endpoint (for testing)
    - `:name` — optional GenServer name
  """
  @spec connect(keyword()) :: GenServer.on_start()
  def connect(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, Map.new(opts), gen_opts)
  end

  @doc "Sends a client event map (see `ExGrok.Realtime` builders) over the socket."
  @spec send_event(GenServer.server(), map()) :: :ok | {:error, term()}
  def send_event(server, event) when is_map(event),
    do: GenServer.call(server, {:send, Realtime.encode(event)})

  @doc "Streams a chunk of PCM audio to the input buffer."
  @spec append_audio(GenServer.server(), binary()) :: :ok | {:error, term()}
  def append_audio(server, pcm), do: send_event(server, Realtime.append_audio_event(pcm))

  @doc "Commits the input audio buffer (manual turn end)."
  @spec commit(GenServer.server()) :: :ok | {:error, term()}
  def commit(server), do: send_event(server, Realtime.commit_event())

  @doc "Asks the model to generate a response."
  @spec create_response(GenServer.server(), map()) :: :ok | {:error, term()}
  def create_response(server, config \\ %{}),
    do: send_event(server, Realtime.create_response_event(config))

  @doc "Closes the WebSocket session."
  @spec close(GenServer.server()) :: :ok
  def close(server), do: GenServer.stop(server, :normal)

  @impl true
  def init(%{api_key: api_key, on_event: on_event} = opts) do
    host = Map.get(opts, :host, @default_host)
    path = Map.get(opts, :path, @default_path)
    model = Map.get(opts, :model, @default_model)
    query = URI.encode_query(%{"model" => model})
    headers = [{"authorization", "Bearer #{api_key}"}]

    with {:ok, conn} <- Mint.HTTP.connect(:https, host, 443, protocols: [:http1]),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(:wss, conn, "#{path}?#{query}", headers) do
      {:ok, %{conn: conn, ref: ref, websocket: nil, status: :connecting, on_event: on_event}}
    else
      {:error, reason} -> {:stop, {:connect_failed, reason}}
      {:error, _conn, reason} -> {:stop, {:upgrade_failed, reason}}
    end
  end

  @impl true
  def handle_call({:send, _text}, _from, %{status: status} = state) when status != :connected do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send, text}, _from, %{conn: conn, websocket: ws, ref: ref} = state) do
    with {:ok, ws, data} <- Mint.WebSocket.encode(ws, {:text, text}),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(conn, ref, data) do
      {:reply, :ok, %{state | conn: conn, websocket: ws}}
    else
      {:error, ws_or_conn, reason} -> {:reply, {:error, reason}, put_conn(state, ws_or_conn)}
    end
  end

  @impl true
  def handle_info(message, %{conn: conn} = state) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, responses} ->
        {:noreply, Enum.reduce(responses, %{state | conn: conn}, &handle_frame_response/2)}

      {:error, conn, reason, _responses} ->
        Logger.warning("ExGrok.Realtime stream error: #{inspect(reason)}")
        {:noreply, %{state | conn: conn}}

      :unknown ->
        {:noreply, state}
    end
  end

  # Complete the WebSocket handshake once we have status + headers.
  defp handle_frame_response({:status, ref, status}, %{ref: ref} = state),
    do: Map.put(state, :handshake_status, status)

  defp handle_frame_response({:headers, ref, headers}, %{ref: ref, conn: conn} = state) do
    case Mint.WebSocket.new(conn, ref, state.handshake_status, headers) do
      {:ok, conn, websocket} ->
        %{state | conn: conn, websocket: websocket, status: :connected}

      {:error, conn, reason} ->
        Logger.warning("ExGrok.Realtime handshake failed: #{inspect(reason)}")
        %{state | conn: conn, status: :error}
    end
  end

  defp handle_frame_response({:data, ref, data}, %{ref: ref, websocket: ws} = state)
       when not is_nil(ws) do
    case Mint.WebSocket.decode(ws, data) do
      {:ok, ws, frames} ->
        Enum.each(frames, &dispatch_frame(&1, state.on_event))
        %{state | websocket: ws}

      {:error, ws, reason} ->
        Logger.warning("ExGrok.Realtime decode error: #{inspect(reason)}")
        %{state | websocket: ws}
    end
  end

  defp handle_frame_response(_other, state), do: state

  defp dispatch_frame({:text, text}, on_event) do
    case Realtime.parse_event(text) do
      {:ok, event} -> on_event.(event)
      {:error, _} -> :ok
    end
  end

  defp dispatch_frame(_frame, _on_event), do: :ok

  defp put_conn(state, %Mint.WebSocket{} = ws), do: %{state | websocket: ws}
  defp put_conn(state, conn), do: %{state | conn: conn}
end
