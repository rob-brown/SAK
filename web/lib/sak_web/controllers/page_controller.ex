defmodule SakWeb.PageController do
  use SakWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
