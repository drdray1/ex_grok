defmodule ExGrok.Client do
  @moduledoc """
  HTTP client for the xAI Grok API.

  Handles Bearer token authentication and request/response formatting.

  ## Usage

      client = ExGrok.Client.new("xai-your-api-key")
      {:ok, response} = ExGrok.Chat.create_completion(client, %{
        "model" => "grok-3-mini",
        "messages" => [%{"role" => "user", "content" => "Hello"}]
      })

  ## Configuration

  All configuration is optional — sensible defaults are provided:

      config :ex_grok,
        config: [
          base_url: "https://api.x.ai/v1",
          timeout: 120_000
        ]
  """

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @default_base_url "https://api.x.ai/v1"
  @default_timeout 120_000

  @doc """
  Creates a new Grok API client with Bearer token authentication.

  ## Parameters

    - `api_key` - xAI API key (format: `xai-...`)

  ## Options

    - `:plug` - Test plug for `Req.Test` (default: nil)

  ## Examples

      client = ExGrok.Client.new("xai-your-api-key")

      # Testing with Req.Test
      client = ExGrok.Client.new("xai-test", plug: {Req.Test, MyStub})
  """
  @spec new(String.t(), keyword()) :: client()
  def new(api_key, opts \\ []) do
    plug = Keyword.get(opts, :plug)

    req_opts =
      [
        base_url: base_url(),
        headers: [{"content-type", "application/json"}],
        receive_timeout: timeout(),
        retry: :transient,
        max_retries: 3,
        retry_delay: fn attempt -> 500 * Integer.pow(2, max(0, attempt)) end
      ]
      |> maybe_add_plug(plug)

    Req.new(req_opts)
    |> ExGrok.Auth.attach(api_key)
  end

  @doc """
  Returns the base URL based on environment configuration.
  """
  @spec base_url() :: String.t()
  def base_url do
    config = Application.get_env(:ex_grok, :config, [])
    Keyword.get(config, :base_url, @default_base_url)
  end

  @doc """
  Returns the configured timeout in milliseconds.
  """
  @spec timeout() :: non_neg_integer()
  def timeout do
    config = Application.get_env(:ex_grok, :config, [])
    Keyword.get(config, :timeout, @default_timeout)
  end

  @doc """
  Verifies credentials by testing the API connection.

  ## Returns

    - `{:ok, models}` - On successful authentication
    - `{:error, reason}` - On failure
  """
  @spec verify_credentials(String.t()) :: response()
  def verify_credentials(api_key) do
    client = new(api_key)

    case Req.get(client, url: "/models") do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Req.Response{status: 403}} ->
        {:error, :forbidden}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:api_error, status, extract_error_message(body)}}

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end

  @doc """
  Performs a health check by validating credentials.
  """
  @spec healthcheck(client()) :: :ok | {:error, term()}
  def healthcheck(client) do
    case Req.get(client, url: "/models") do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Req.Response{status: 403}} ->
        {:error, :forbidden}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Handles API response and normalizes to standard format.
  """
  @spec handle_response({:ok, Req.Response.t()} | {:error, term()}) :: response()
  def handle_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  def handle_response({:ok, %Req.Response{status: 401}}) do
    {:error, :unauthorized}
  end

  def handle_response({:ok, %Req.Response{status: 403}}) do
    {:error, :forbidden}
  end

  def handle_response({:ok, %Req.Response{status: 404}}) do
    {:error, :not_found}
  end

  def handle_response({:ok, %Req.Response{status: 429}}) do
    {:error, :rate_limited}
  end

  def handle_response({:ok, %Req.Response{status: status, body: body}}) when status >= 400 do
    {:error, {:api_error, status, extract_error_message(body)}}
  end

  def handle_response({:error, reason}) do
    {:error, {:connection_error, reason}}
  end

  @spec extract_error_message(map() | term()) :: String.t()
  defp extract_error_message(%{"error" => %{"message" => message}}) when is_binary(message),
    do: message

  defp extract_error_message(%{"error" => error}) when is_binary(error), do: error
  defp extract_error_message(%{"message" => message}) when is_binary(message), do: message
  defp extract_error_message(_), do: "Unknown error"

  defp maybe_add_plug(opts, nil), do: opts
  defp maybe_add_plug(opts, plug), do: Keyword.put(opts, :plug, plug)
end
