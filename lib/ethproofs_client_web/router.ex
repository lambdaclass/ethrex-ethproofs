defmodule EthProofsClientWeb.Router do
  use EthProofsClientWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {EthProofsClientWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", EthProofsClientWeb do
    pipe_through(:browser)

    live("/", DashboardLive, :index)
  end

  # Health API endpoints
  scope "/api", EthProofsClientWeb do
    pipe_through(:api)

    get("/health", HealthController, :index)
    get("/health/ready", HealthController, :ready)
    get("/health/live", HealthController, :live)
  end
end
