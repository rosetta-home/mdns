defmodule Mdns.EventManager do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:ok, events} = GenEvent.start_link([{:name, Mdns.Events}])
    {:ok, %{:handlers => [], :events => events}}
  end

  def add_handler(handler) do
    GenServer.call(__MODULE__, {:handler, handler})
  end

  def handle_call({:handler, handler}, {pid, _}, state) do
    GenEvent.add_mon_handler(Mdns.Events, handler, pid)
    {:reply, :ok, %{state | :handlers => [{handler, pid} | state.handlers]}}
  end

  def handle_info({:gen_event_EXIT, _handler, _reason}, state) do
    Enum.each(state.handlers, fn(h) ->
      GenEvent.add_mon_handler(Mdns.Events, elem(h, 0), elem(h, 1))
    end)
    {:noreply, state}
  end

end
