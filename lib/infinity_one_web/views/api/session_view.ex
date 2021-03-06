defmodule InfinityOneWeb.API.SessionView do
  use InfinityOneWeb, :view

  require Logger

  def render("create.json", %{data: data}) do
    # json conn, %{status: "success", data: Enum.into(opts, %{})}
    Logger.warn "data: " <> inspect(data)

    %{status: "success", data: Enum.into(data, %{})}
  end
end
