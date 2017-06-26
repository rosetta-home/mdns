defmodule Mdns.Supervisor do
  use Supervisor

  def start_link do
      Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    children = [
      worker(Mdns.EventManager, []),
      worker(Mdns.Client, []),
      worker(Mdns.Server, []),
    ]
    supervise(children, strategy: :one_for_one)
  end
end
