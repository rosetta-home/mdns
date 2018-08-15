defmodule Mdns.EventManager do
  use GenServer
  require Logger

  def add_handler() do
    GenServer.call(__MODULE__, :add_handler)
  end

  def register() do
    GenServer.call(__MODULE__, :add_handler)
  end

  def notify(message) do
    GenServer.call(__MODULE__, {:notify, message})
  end

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_call(:add_handler, {pid, _ref}, state) do
    Registry.register(Mdns.EventManager.Registry, Mdns, pid)
    {:reply, :ok, state}
  end

  def handle_call({:notify, message}, _from, state) do
    Logger.debug("mDNS dispatching: #{inspect(message)}")

    case Registry.lookup(Mdns.EventManager.Registry, Mdns) do
      [] ->
        Logger.debug("No Registrations for Mdns")

      _ ->
        Registry.dispatch(Mdns.EventManager.Registry, Mdns, fn entries ->
          for {_module, pid} <- entries, do: send(pid, message)
        end)
    end

    {:reply, message, state}
  end
end
