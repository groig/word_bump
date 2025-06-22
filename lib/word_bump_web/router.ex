# lib/word_bump_web/router.ex
defmodule WordBumpWeb.Router do
  use WordBumpWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WordBumpWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WordBumpWeb do
    pipe_through :browser

    live "/", WordBumpLive, :index
  end
end
