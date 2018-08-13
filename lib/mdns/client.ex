defmodule Mdns.Client do
  use GenServer
  require Logger

  @mdns_group {224,0,0,251}
  @port Application.get_env(:mdns, :port, 5353)

  @query_packet %DNS.Record{
      header: %DNS.Header{},
      qdlist: []
  }

  defmodule State do
    defstruct devices: %{},
      udp: nil,
      handlers: [],
      queries: []
  end

  defmodule Device do
    defstruct ip: nil,
      services: [],
      domain: nil,
      payload: %{}
  end

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def query(namespace \\ "_services._dns-sd._udp.local") do
    GenServer.cast(__MODULE__, {:query, namespace})
  end

  def devices do
    GenServer.call(__MODULE__, :devices)
  end

  def start do
    GenServer.call(__MODULE__, :start)
  end

  def init(:ok) do
    {:ok, %State{}}
  end

  def handle_call(:start, _from, state) do
    udp_options = [
        :binary,
        broadcast:       true,
        active:          true,
        ip:              {0,0,0,0},
        ifaddr:          {0,0,0,0},
        add_membership:  {@mdns_group, {0,0,0,0}},
        multicast_if:    {0,0,0,0},
        multicast_loop:  true,
        multicast_ttl:   32,
        reuseaddr:       true
    ]

    {:ok, udp} = :gen_udp.open(@port, udp_options)
    {:reply, :ok, %State{state | udp: udp}}
  end

  def handle_call(:devices, _from, state) do
    {:reply, state.devices, state}
  end

  def handle_cast({:query, namespace}, state) do
    packet = %DNS.Record{@query_packet | :qdlist => [
      %DNS.Query{domain: to_charlist(namespace), type: :ptr, class: :in}
    ]}
    p = DNS.Record.encode(packet)
    :gen_udp.send(state.udp, @mdns_group, @port, p)
    {:noreply,  %State{state | :queries => Enum.uniq([namespace | state.queries])}}
  end

  def handle_info({:udp, _socket, ip, _port, packet}, state) do
    {:noreply, handle_packet(ip, packet, state)}
  end

  def handle_packet(ip, packet, state) do
    record = DNS.Record.decode(packet)
    case record.header.qr do
      true -> handle_response(ip, record, state)
      _ -> state
    end
  end

  def handle_response(ip, record, state) do
    Logger.debug("mDNS got response: #{inspect record}")
    device = get_device(ip, record, state)
    devices =
      Enum.reduce(state.queries, %{:other => []}, fn(query, acc) ->
        cond do
          Enum.any?(device.services, fn(service) -> String.ends_with?(service, query) end) ->
            {namespace, devices} = create_namespace_devices(query, device, acc, state)
            Mdns.EventManager.notify({namespace, device})
            Logger.debug("mDNS device: #{inspect {namespace, device}}")
            devices
          true -> Map.merge(acc, state.devices)
        end
      end)
    %State{state | :devices => devices}
  end

  def handle_device(%DNS.Resource{:type => :ptr} = record, device) do
    %Device{device | :services => Enum.uniq([to_string(record.data), to_string(record.domain)] ++ device.services)}
  end

  def handle_device(%DNS.Resource{:type => :a} = record, device) do
    %Device{device | :domain => to_string(record.domain)}
  end

  def handle_device({:dns_rr, _d, :txt, _id, _, _, data, _, _, _}, device) do
    %Device{device | :payload => Enum.reduce(data, %{}, fn(kv, acc) ->
      case String.split(to_string(kv), "=", parts: 2) do
        [k, v] -> Map.put(acc, String.downcase(k), String.trim(v))
        _ -> nil
      end
    end)}
  end

  def handle_device(%DNS.Resource{}, device) do
    device
  end

  def handle_device({:dns_rr, _, _, _, _, _, _, _, _, _}, device) do
    device
  end

  def handle_device({:dns_rr_opt, _, _, _, _, _, _, _}, device) do
    device
  end

  def get_device(ip, record, state) do
    orig_device = Enum.concat(Map.values(state.devices))
    |> Enum.find(%Device{:ip => ip}, fn(device) ->
      device.ip == ip
    end)
    Enum.reduce(record.anlist ++ record.arlist, orig_device, fn(r, acc) -> handle_device(r, acc) end)
  end

  def create_namespace_devices(query, device, devices, state) do
    namespace = String.to_atom(query)
    {namespace, cond do
      Enum.any?(Map.get(state.devices, namespace, []), fn(dev) -> dev.ip == device.ip end) ->
        Map.merge(devices, %{namespace => merge_device(device, namespace, state)})
      true -> Map.merge(devices, %{namespace => [device | Map.get(state.devices, namespace, [])]})
    end}
  end

  def merge_device(device, namespace, state) do
    Enum.map(Map.get(state.devices, namespace, []), fn(d) ->
      cond do
        device.ip == d.ip -> Map.merge(d, device)
        true -> d
      end
    end)
  end
end
