defmodule UppyPhxWeb.PageController do
  use UppyPhxWeb, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
