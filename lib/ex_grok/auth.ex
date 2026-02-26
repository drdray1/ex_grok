defmodule ExGrok.Auth do
  @moduledoc """
  Req plugin for xAI Grok Bearer token authentication.

  Automatically attaches the Authorization header to each request.

  ## Usage

  Typically used via `ExGrok.Client.new/2`, but can be attached manually:

      Req.new(base_url: "https://api.x.ai/v1")
      |> ExGrok.Auth.attach("xai-your-api-key")
  """

  @doc """
  Attaches Bearer token authentication to a Req request.
  """
  @spec attach(Req.Request.t(), String.t() | nil) :: Req.Request.t()
  def attach(request, api_key) do
    request
    |> Req.Request.register_options([:grok_api_key])
    |> Req.Request.merge_options(grok_api_key: api_key)
    |> Req.Request.append_request_steps(grok_auth: &sign_request/1)
  end

  defp sign_request(request) do
    api_key = request.options[:grok_api_key]

    if api_key do
      Req.Request.put_header(request, "authorization", "Bearer #{api_key}")
    else
      request
    end
  end
end
