defmodule ExGrok.Models do
  @moduledoc """
  xAI Grok API - Model listing operations.

  Provides functions to list and retrieve available Grok models.

  ## Examples

      client = ExGrok.Client.new("xai-your-api-key")

      {:ok, response} = ExGrok.Models.list_models(client)
      models = ExGrok.Models.extract_models(response)
  """

  alias ExGrok.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Lists all available models.

  ## Examples

      iex> list_models(client)
      {:ok, %{"object" => "list", "data" => [%{"id" => "grok-3", ...}]}}
  """
  @spec list_models(client()) :: response()
  def list_models(client) do
    client
    |> Req.get(url: "/models")
    |> Client.handle_response()
  end

  # A convenience reference of commonly-available Grok model ids. This is a
  # static hint for callers; use `list_models/1` for the authoritative,
  # account-scoped list from the API.
  @known_models ~w(
    grok-4.5 grok-4 grok-4-fast grok-code-fast-1
    grok-3 grok-3-mini grok-2-image
  )

  @doc """
  Returns a static reference list of commonly-available Grok model ids.

  This does not hit the API — use `list_models/1` for the authoritative list.

  ## Examples

      iex> "grok-4.5" in ExGrok.Models.known_models()
      true
  """
  @spec known_models() :: list(String.t())
  def known_models, do: @known_models

  @doc """
  Retrieves a single model by ID.

  ## Examples

      iex> get_model(client, "grok-3-mini")
      {:ok, %{"id" => "grok-3-mini", "object" => "model", ...}}
  """
  @spec get_model(client(), String.t()) :: response()
  def get_model(client, model_id) do
    client
    |> Req.get(url: "/models/#{model_id}")
    |> Client.handle_response()
  end

  @doc """
  Extracts models list from response.

  ## Examples

      iex> extract_models(%{"data" => [%{"id" => "grok-3"}]})
      [%{"id" => "grok-3"}]
  """
  @spec extract_models(map()) :: list(map())
  def extract_models(%{"data" => data}) when is_list(data), do: data
  def extract_models(_), do: []

  @doc """
  Extracts model ID strings from response.

  ## Examples

      iex> extract_model_ids(%{"data" => [%{"id" => "grok-3"}, %{"id" => "grok-3-mini"}]})
      ["grok-3", "grok-3-mini"]
  """
  @spec extract_model_ids(map()) :: list(String.t())
  def extract_model_ids(response) do
    response
    |> extract_models()
    |> Enum.map(& &1["id"])
    |> Enum.reject(&is_nil/1)
  end
end
