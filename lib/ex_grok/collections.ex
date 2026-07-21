defmodule ExGrok.Collections do
  @moduledoc """
  xAI Grok **Collections API** — grouped files with an embedding index for
  semantic retrieval.

  ## Two hosts, two keys

  Collection *management* (create/list/delete, add/remove documents) lives on
  the **Management API** (`management-api.x.ai`) and needs a **Management API
  key** — build that client with `ExGrok.Client.management_client/1`.

  Document *search* runs on the normal inference host (`api.x.ai`) with your
  regular key, so `search/2` takes an ordinary `ExGrok.Client` client.

  ## Example

      mgmt = ExGrok.Client.management_client("xai-mgmt-key")
      {:ok, coll} = ExGrok.Collections.create(mgmt, "SEC Filings")
      cid = ExGrok.Collections.extract_collection_id(coll)

      # a file previously uploaded via ExGrok.Files.upload/3:
      {:ok, _} = ExGrok.Collections.add_document(mgmt, cid, file_id)

      client = ExGrok.Client.new("xai-your-api-key")
      {:ok, results} = ExGrok.Collections.search(client, "revenue guidance", collection_ids: [cid])
  """

  alias ExGrok.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  # ---- management host ------------------------------------------------------

  @doc "Creates a collection (`POST /collections`). Uses a management client."
  @spec create(client(), String.t(), keyword()) :: response()
  def create(mgmt_client, collection_name, opts \\ []) do
    params =
      opts
      |> Keyword.take([:field_definitions])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.reduce(%{"collection_name" => collection_name}, fn {k, v}, acc ->
        Map.put(acc, Atom.to_string(k), v)
      end)

    mgmt_client
    |> Req.post(url: "/collections", json: params)
    |> Client.handle_response()
  end

  @doc "Lists collections (`GET /collections`). Uses a management client."
  @spec list(client()) :: response()
  def list(mgmt_client) do
    mgmt_client
    |> Req.get(url: "/collections")
    |> Client.handle_response()
  end

  @doc "Retrieves a collection by id (`GET /collections/:id`). Uses a management client."
  @spec get(client(), String.t()) :: response()
  def get(mgmt_client, collection_id) when is_binary(collection_id) do
    mgmt_client
    |> Req.get(url: "/collections/#{collection_id}")
    |> Client.handle_response()
  end

  @doc "Updates a collection (`PUT /collections/:id`). Uses a management client."
  @spec update(client(), String.t(), map()) :: response()
  def update(mgmt_client, collection_id, %{} = params) when is_binary(collection_id) do
    mgmt_client
    |> Req.put(url: "/collections/#{collection_id}", json: params)
    |> Client.handle_response()
  end

  @doc "Deletes a collection (`DELETE /collections/:id`). Uses a management client."
  @spec delete(client(), String.t()) :: response()
  def delete(mgmt_client, collection_id) when is_binary(collection_id) do
    mgmt_client
    |> Req.delete(url: "/collections/#{collection_id}")
    |> Client.handle_response()
  end

  @doc """
  Attaches an already-uploaded file to a collection
  (`POST /collections/:id/documents/:file_id`). Uses a management client.
  """
  @spec add_document(client(), String.t(), String.t()) :: response()
  def add_document(mgmt_client, collection_id, file_id) do
    mgmt_client
    |> Req.post(url: "/collections/#{collection_id}/documents/#{file_id}")
    |> Client.handle_response()
  end

  @doc """
  Detaches a file from a collection
  (`DELETE /collections/:id/documents/:file_id`). Uses a management client.
  """
  @spec remove_document(client(), String.t(), String.t()) :: response()
  def remove_document(mgmt_client, collection_id, file_id) do
    mgmt_client
    |> Req.delete(url: "/collections/#{collection_id}/documents/#{file_id}")
    |> Client.handle_response()
  end

  # ---- inference host -------------------------------------------------------

  @doc """
  Searches documents across one or more collections
  (`POST /documents/search` on the normal inference host).

  ## Options
    - `:collection_ids` — list of collection ids to search (required in practice)
    - `:retrieval_mode` — `"hybrid"` | `"keyword"` | `"semantic"` (default `"hybrid"`)
    - `:limit` — max results
  """
  @spec search(client(), String.t(), keyword()) :: response()
  def search(client, query, opts \\ []) do
    params =
      %{"query" => query}
      |> put_source(Keyword.get(opts, :collection_ids))
      |> Map.put("retrieval_mode", %{"type" => Keyword.get(opts, :retrieval_mode, "hybrid")})
      |> maybe_put("limit", Keyword.get(opts, :limit))

    client
    |> Req.post(url: "/documents/search", json: params)
    |> Client.handle_response()
  end

  @doc "The collection id from a create/get response, or nil."
  @spec extract_collection_id(map()) :: String.t() | nil
  def extract_collection_id(%{"collection_id" => id}) when is_binary(id), do: id
  def extract_collection_id(%{"id" => id}) when is_binary(id), do: id
  def extract_collection_id(_), do: nil

  @doc "The result list from a search response, or []."
  @spec extract_search_results(map()) :: list(map())
  def extract_search_results(%{"results" => results}) when is_list(results), do: results
  def extract_search_results(%{"data" => data}) when is_list(data), do: data
  def extract_search_results(_), do: []

  # ---------------------------------------------------------------------------

  defp put_source(params, nil), do: params
  defp put_source(params, ids), do: Map.put(params, "source", %{"collection_ids" => ids})

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
