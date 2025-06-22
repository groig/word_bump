defmodule WordBumpWeb.PageController do
  use WordBumpWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
