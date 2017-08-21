defmodule UppyPhxWeb.TusController do
  use UppyPhxWeb, :controller

    require Logger


  def static_url(conn, params) do
    %{"uuid" => uuid_media} = params
    conn
    |> send_resp(200,Poison.encode! "http://localhost:3001/uploads/"<>uuid_media )
  end

  def get(conn, params) do
    IO.puts "GET----------------------"
    %{"uuid" => uuid_media} = params

    conn
    |> redirect(to: "/uploads/#{uuid_media}")
  end

  def options(conn, params) do
    IO.puts "OPTIONS----------------------"
    conn
    |> put_resp_header("Content-Type","text/plain; charset=utf-8")
    |> put_resp_header("Content-Length", "0")
    |> put_resp_header("access-control-allow-headers","Origin, X-Requested-With, Content-Type, Upload-Length, Upload-Offset, Tus-Resumable, Upload-Metadata")
    |> put_resp_header("Access-Control-Allow-Methods", "POST, GET, HEAD, PATCH, DELETE, OPTIONS")
    |> put_resp_header("tus-extension", "creation,creation-with-upload,termination,creation-defer-length")
    |> put_resp_header("tus-max-size", "1000000000")
    |> put_resp_header("tus-version", "1.0.0")
    |> put_resp_header("Upload-Offset", "0")
    |> send_resp(200,"")
  end



  def post(conn, params) do
    IO.puts "POST----------------------"
    %Plug.Conn{req_headers: request_headers} = conn
    upload_length =Enum.find_value(request_headers, 0, fn {h, v} -> if "upload-length" == h, do: v end)
    upload_deferer_length = Enum.find_value(request_headers, 0, fn {h, v} -> if "upload-defer-length" == h, do: v end)
    upload_metadata = Enum.find_value(request_headers, 0, fn {h, v} -> if "upload-metadata" == h, do: v end)
    metadata = decode_metadata(upload_metadata)

    case upload_deferer_length do
      "1" -> length = 1
       _  -> length = upload_length
    end

    srv_location = "http://localhost:3001/umedia/#{create_u_file( length, metadata )}"

    IO.puts "UPLOAD_LENGTH #{upload_length}"
    IO.puts "UPLOAD_DEFERER_LENGTH #{upload_deferer_length}"
    IO.write "UPLOAD_METADATA "; IO.inspect metadata
    IO.puts "LOCATION #{srv_location}"

    conn
    |> put_resp_header("Content-Type","text/plain; charset=utf-8")
    |> put_resp_header("Content-Length", "0")
    |> put_resp_header("tus-max-size", "1000000000")
    |> put_resp_header("Tus-Resumable", "1.0.0")
    |> put_resp_header("tus-version", "1.0.0")
    |> put_resp_header("Location", srv_location)
    |> send_resp(201, "")

  end


  def head(conn, params) do
    IO.puts "HEAD----------------------"
    %{"uuid" => uuid_media} = params
    srv_upload_offset = get_uuid_file_size(uuid_media)
    stash_size = Stash.get(:uppy_cache, uuid_media)
    case stash_size do
       nill->srv_upload_length = 0
       _ -> srv_upload_length = String.to_integer(stash_size) - srv_upload_offset
    end



    IO.puts  "SRV_UPLOAD_LENGTH: #{srv_upload_length}"
    IO.puts  "SRV_UPLOAD_OFFSET: #{srv_upload_offset}"

    conn
    |> put_resp_header("Content-Type","text/plain; charset=utf-8")
    |> put_resp_header("Content-Length", "0")
    |> put_resp_header("Tus-Resumable", "1.0.0")
    |> put_resp_header("tus-version", "1.0.0")
    |> put_resp_header("Upload-Length", "#{srv_upload_length}")
    |> put_resp_header("Upload-Offset", "#{srv_upload_offset}")
    |> send_resp(200, "")
  end

  def patch(conn, params) do
    IO.puts "PATCH----------------------"
    %{"uuid" => uuid_media} = params
    media_size = Stash.get(:uppy_cache, uuid_media)|>String.to_integer
    %Plug.Conn{req_headers: request_headers} = conn
    cli_content_length =Enum.find_value(request_headers, 0, fn {h, v} -> if "content-length" == h, do: v end)
    cli_upload_offset =Enum.find_value(request_headers, 0, fn {h, v} -> if "upload-offset" == h, do: v end)
    upload_deferer_length = Enum.find_value(request_headers, 0, fn {h, v} -> if "upload-defer-length" == h, do: v end)


    upload_length =Enum.find_value(request_headers, 0, fn {h, v} -> if "upload-length" == h, do: v end)
    cond  do
      (upload_length != 0  && Stash.set(:uppy_cache, uuid_media) == "1") ->Stash.set(:uppy_cache, uuid_media, upload_length)
      true -> Logger.info("Upload-Length already set to: #{Stash.get(:uppy_cache, uuid_media)}")
    end

    media_size_tuple = write_patch(conn, uuid_media)
    srv_prepatch_size = elem(media_size_tuple, 0)
    srv_upload_offset = elem(media_size_tuple, 1)


    #if cli_content_length==srv_upload_offset || media_size == srv_media_size do
      http_code=204
      http_msg="No Content"
    #else
    #  http_code=409
    #  http_msg="Conflict"
    #end

    IO.puts  "UUIDFILE: #{uuid_media}"
    IO.puts  "SRV TOTAL MEDIA SIZE: #{media_size}"
    IO.puts  "CLI CONTENTLENGTH: #{cli_content_length}"
    IO.puts  "CLI UPLOADOFFSET: #{cli_content_length}"
    IO.puts  "SRV UPLOADOFFSET #{srv_upload_offset}"
    IO.puts  "SRV PRE PATCH SIZE #{srv_prepatch_size}"
    IO.puts  "SRV UPLOADOFFSET SEND #{srv_upload_offset}"
    IO.puts  "HTTP CODE #{http_code}"

    conn
    |> put_resp_header("Tus-Resumable", "1.0.0")
    |> put_resp_header("tus-version", "1.0.0")
    |> put_resp_header("Upload-Offset", "#{srv_upload_offset}")
    |> send_resp(http_code, http_msg)

  end


  def create_u_file(upload_length, remote_metadata) do     
    uuid_file = Ecto.UUID.generate()<>Path.extname(remote_metadata["name"])
    file_out_path = Path.expand('./uploads')|>Path.join(uuid_file)
    File.touch!(file_out_path)
    # Salvamos la el tamaño y el nombre para luego subirlo a S3
    # Esto puede ir a ECTO, pero ahora como demo se utiliza una ETS con persistencia por facilidad
    Stash.load(:uppy_cache, Path.expand('./uploads')|>Path.join("uppy.db"))
    Stash.set(:uppy_cache, uuid_file, upload_length)
    Stash.set(:uppy_cache, "name_"<>uuid_file, remote_metadata["name"])
    Stash.persist(:uppy_cache, Path.expand('./uploads')|>Path.join("uppy.db"))
    Logger.info("uppy_cache: #{inspect Stash.keys(:uppy_cache) }")
    uuid_file
  end


  def write_patch(conn, uuid_media) do
    out_file = Path.expand('./uploads')|>Path.join(uuid_media)
    initial_file_size = File.stat!(out_file)
                    |>Map.get(:size)

    with {:ok, wdev} <- File.open(out_file, [:append]) do
      try do
        transfer(conn, wdev)
      after
        File.close wdev
      rescue
        error -> Logger.error "Failed to write #{out_file} #{Exception.format(:error, error)}"
      end
    else
     whatever -> Logger.error "Failed to write #{out_file}: #{inspect whatever}"
    end
    final_file_size = File.stat!(out_file)
                  |>Map.get(:size)
    {initial_file_size,final_file_size}
  end

  def transfer(conn, wdev) do
    case Plug.Conn.read_body(conn) do
      {:ok, chunk, conn} -> IO.binwrite(wdev, chunk)
      {:more, chunk, conn} -> IO.binwrite(wdev, chunk); transfer(conn, wdev)
      {:error, reason} -> Logger.error "Chunk read failed #{inspect reason}"
    end

  end

  def get_uuid_file_size(uuid_media) do
      uuid_path = Path.expand('./uploads')|>Path.join( uuid_media)
      case File.stat uuid_path do
      {:ok, %{size: uuid_path_size}} -> uuid_path_size
      {:error, reason} -> Logger.error "Failed to write #{uuid_path} #{Exception.format(:error, reason)}"
                          uuid_path_size = 0
    end
  end

  def decode_metadata(metadata) do
    split_md = metadata|>String.split([" ", ","])
    list_md = Enum.concat(["dummy"],split_md)
      |>Enum.map_every(2,fn(x) ->
            case Base.decode64(x) do
              {:ok, token}-> token
              :error -> x
            end
        end)
      |>List.delete_at(0)
    Enum.zip(Enum.take_every(list_md, 2), Enum.drop_every(list_md, 2)) |> Enum.into(%{})
  end

  def append_chunck in_file  do
    out_file = Path.expand('./uploads')|>Path.join(Ecto.UUID.generate())
    with {:ok, wdev} <- File.open(out_file, [:write]),
         {:ok, rdev} <- File.open(in_file, [:read]) do
        try do
          rdev |> IO.binstream(4096) |> Enum.each(fn x -> IO.binwrite wdev, x end)
        after
          File.close wdev
          File.close rdev
        rescue
          error -> Logger.error "Failed to write #{in_file} "
        end
    else
      whatever -> Logger.error "Failed to write #{in_file}: "
    end
  end


end
