defmodule ElixirDropbox do
  @moduledoc """
  ElixirDropbox is a wrapper for Dropbox API V2
  """
  use HTTPoison.Base
  require Logger
  @type response :: {any}

  @base_url_v1 "https://api.dropboxapi.com/1"
  @base_url "https://content.dropboxapi.com/2"
  @upload_url "https://content.dropboxapi.com/2"
  
  def post_v1(client, url, body \\ "") do
    headers = json_headers()
    post_request(client, "#{@base_url_v1}#{url}", body, headers)
  end
  
  def post(client, url, body \\ "") do
    headers = json_headers()
    post_request(client, "#{@base_url}#{url}", body, headers)
  end

  @spec upload_response(HTTPoison.Response.t) :: response
  def upload_response(%HTTPoison.Response{status_code: 200, body: body}), do: Poison.decode!(body)
  def upload_response(%HTTPoison.Response{status_code: status_code, body: body }) do
    cond do
    status_code in 400..599 ->
      {{:status_code, status_code}, Poison.decode(body)}
    end
  end

   @spec download_response(HTTPoison.Response.t) :: response
   def download_response(response) do
    case response do
      %HTTPoison.Response{body: body, headers: headers, status_code: 200} ->
        {:ok, %{file: body, headers: get_header(headers, "dropbox-api-result") |> Poison.decode}}
      _-> response   
    end
  end

  def post_request(client, url, body, headers) do
    headers = Map.merge(headers, headers(client))
    options = [recv_timeout: 50000]
    HTTPoison.post!(url, body, headers, options) |> upload_response
  end

  def headers(client) do
    %{ "Authorization" => "Bearer #{client.access_token}" }
  end

  def json_headers do
    %{ "Content-Type" => "application/json" }
  end

  def get_header(headers, key) do
    headers
    |> Enum.filter(fn({k, _}) -> k == key end)
    |> hd
    |> elem(1)
  end

  def upload_request(client, url, data, headers) do
    post_request(client, "#{@upload_url}#{url}", {:file, data}, headers)
  end

  def download_request1(client, url, data, headers) do
    headers = Map.merge(headers, headers(client))
    options = [recv_timeout: 50000]
    HTTPoison.post!("#{@upload_url}#{url}", data, headers, options) |> download_response
  end

  def download_request(client, url, data, headers) do
    headers = Map.merge(headers, headers(client))
    options = [stream_to: self(), async: :once, recv_timeout: 50000]
    case HTTPoison.post!("#{@upload_url}#{url}", data, headers, options) do
      resp = %HTTPoison.AsyncResponse{id: id} ->
        receive do
              %HTTPoison.AsyncStatus{ id: ^id, code: status } ->
                case status do
                  200 -> async_loop(id, resp, %{})
                  non_200 -> {:error, non_200}
                end
              whatever -> {:error, whatever}
            end
      whatever -> {:error, whatever}
    end
  end
  
  def async_loop id, resp, acc do
    case HTTPoison.stream_next(resp) do
      {:ok, ^resp} ->
        receive do
          %HTTPoison.AsyncHeaders{ id: ^id, headers: headers } ->
            headers = case get_header(headers, "dropbox-api-result") |> Poison.decode() do
              {:ok, decoded_headers} -> decoded_headers

              {:error, whatever} ->
                Logger.error "Failed to decode #{inspect headers}: #{inspect whatever}"
                %{"name" => "name.unknown"}
            end

            uuid_file = Ecto.UUID.generate() <> Path.extname(headers["name"])
            upload_folder = Path.expand('./uploads')
            File.mkdir_p upload_folder
            uuid_path = upload_folder |> Path.join(uuid_file)

            acc = acc
              |> Map.put(:headers, headers)
              |> Map.put(:uuid_file, uuid_file)
              |> Map.put(:uuid_path, uuid_path)

            async_loop(id, resp, acc)

          %HTTPoison.AsyncChunk{ id: ^id, chunk: chunk } ->
            case File.write(acc[:uuid_path], chunk, [:append]) do
              :ok ->
                async_loop(id, resp, acc)

              {:error, posix} = error ->
                Logger.error "Failed to write chunk: #{inspect posix}"
                error
            end

          %HTTPoison.AsyncEnd{ id: ^id } ->
            Stash.load(:uppy_cache, Path.expand('./uploads') |> Path.join("uppy.db"))
            Stash.set(:uppy_cache, "name_" <> acc[:uuid_file], get_in(acc, [:headers, "name"]))
            Stash.persist(:uppy_cache, Path.expand('./uploads') |> Path.join("uppy.db"))
            {:ok, acc}

          whatever ->
            {:error, whatever}
        end

      {:error, _} = error -> error
    end
  end
end
