defmodule ExGrok.Files do
  @moduledoc """
  xAI Grok **Files API** (`/v1/files`).

  Upload, list, retrieve, download, and delete files. Uploaded files can be
  attached to chat/responses for document understanding, or added to a
  collection (see `ExGrok.Collections`) for semantic search.

  ## Example

      client = ExGrok.Client.new("xai-your-api-key")

      {:ok, file} = ExGrok.Files.upload(client, {:file, "report.pdf"}, purpose: "collections")
      id = ExGrok.Files.extract_file_id(file)

      {:ok, _} = ExGrok.Files.delete(client, id)
  """

  alias ExGrok.Client

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Uploads a file (`POST /files`, multipart).

  `source` is `{:file, path}` or `{:content, bytes, filename}`.

  ## Options
    - `:purpose` — intended use (e.g. `"collections"`)
    - `:expires_after` — expiry policy map, or `:expires_at` — explicit timestamp
  """
  @spec upload(client(), tuple(), keyword()) :: response()
  def upload(client, source, opts \\ []) do
    fields =
      opts
      |> Keyword.take([:purpose, :expires_after, :expires_at])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> {Atom.to_string(k), stringify(v)} end)

    client
    |> Req.post(url: "/files", form_multipart: [file_part(source) | fields])
    |> Client.handle_response()
  end

  @doc "Lists uploaded files (`GET /files`)."
  @spec list(client()) :: response()
  def list(client) do
    client
    |> Req.get(url: "/files")
    |> Client.handle_response()
  end

  @doc "Retrieves file metadata by id (`GET /files/:id`)."
  @spec get(client(), String.t()) :: response()
  def get(client, file_id) when is_binary(file_id) do
    client
    |> Req.get(url: "/files/#{file_id}")
    |> Client.handle_response()
  end

  @doc "Downloads raw file content by id (`GET /files/:id/content`)."
  @spec content(client(), String.t()) :: {:ok, binary()} | {:error, term()}
  def content(client, file_id) when is_binary(file_id) do
    client
    |> Req.get(url: "/files/#{file_id}/content")
    |> Client.handle_response()
  end

  @doc "Deletes a file by id (`DELETE /files/:id`)."
  @spec delete(client(), String.t()) :: response()
  def delete(client, file_id) when is_binary(file_id) do
    client
    |> Req.delete(url: "/files/#{file_id}")
    |> Client.handle_response()
  end

  @doc "The file id from an upload/get response, or nil."
  @spec extract_file_id(map()) :: String.t() | nil
  def extract_file_id(%{"id" => id}) when is_binary(id), do: id
  def extract_file_id(%{"file_id" => id}) when is_binary(id), do: id
  def extract_file_id(_), do: nil

  @doc "The list of file maps from a list response, or []."
  @spec extract_files(map()) :: list(map())
  def extract_files(%{"data" => data}) when is_list(data), do: data
  def extract_files(%{"files" => files}) when is_list(files), do: files
  def extract_files(_), do: []

  # ---------------------------------------------------------------------------

  defp file_part({:content, bytes, filename}) when is_binary(bytes),
    do: {"file", {bytes, filename: filename}}

  defp file_part({:file, path}),
    do: {"file", {File.read!(path), filename: Path.basename(path)}}

  defp stringify(v) when is_binary(v), do: v
  defp stringify(v) when is_map(v) or is_list(v), do: Jason.encode!(v)
  defp stringify(v), do: to_string(v)
end
