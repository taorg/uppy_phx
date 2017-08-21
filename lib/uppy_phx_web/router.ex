defmodule UppyPhxWeb.Router do
  use UppyPhxWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end
  pipeline :api do
    plug :accepts, ["json"]
  end
  scope "/", UppyPhxWeb do
    pipe_through :api
    options "/umedia/:uuid", TusController, :options
    head "/umedia/:uuid", TusController, :head
    get "/umedia/:uuid", TusController, :get
    patch "/umedia/:uuid", TusController, :patch
    post "/umedia", TusController, :post
  end
  scope "/", UppyPhxWeb do
    pipe_through :browser
    # Use the default browser stack
    get "/", PageController, :index
    get "/uppy", UppyController, :index
  end
end
# Other scopes may use custom stacks.
# scope "/api", UppyPhxWeb do
#   pipe_through :api
# end
