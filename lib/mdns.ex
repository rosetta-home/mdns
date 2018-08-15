defmodule Mdns do
  use Application
  require Logger

  def start(_type, _args) do
    Mdns.Supervisor.start_link()
  end
end
