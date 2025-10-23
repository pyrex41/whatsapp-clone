defmodule GlobalbridgeBackendWeb.ErrorJSONTest do
  use GlobalbridgeBackendWeb.ConnCase, async: true

  test "renders 404" do
    assert GlobalbridgeBackendWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end

  test "renders 500" do
    assert GlobalbridgeBackendWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
