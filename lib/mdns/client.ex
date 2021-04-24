defmodule Mdns.Client do
  use GenServer
  require Logger
  alias Mdns.Utilities.Network

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
              port: nil,
              services: [],
              domain: nil,
              payload: %{}
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def query(namespace \\ "_services._dns-sd._udp.local") do
    GenServer.cast(__MODULE__, {:query, namespace})
  end

  def devices do
    GenServer.call(__MODULE__, :devices)
  end

  def start(udp_opts \\ []) do
    GenServer.call(__MODULE__, {:start, udp_opts})
  end

  def stop() do
    GenServer.call(__MODULE__, :stop)
  end

  def init(:ok) do
    {:ok, %State{}}
  end

  def handle_call({:start, udp_opts}, _from, state) do
    base_udp_opts = [
      :binary,
      broadcast: true,
      active: true,
      reuseaddr: true
    ] ++ Network.reuse_port()

    overridable_udp_opts =
      [
        ip: {0, 0, 0, 0},
        ifaddr: {0, 0, 0, 0},
        add_membership: {Network.mdns_group(), {0, 0, 0, 0}},
        multicast_if: {0, 0, 0, 0},
        multicast_loop: true,
        multicast_ttl: 32
      ]

    udp_opts = Keyword.merge(overridable_udp_opts, udp_opts)

    {:ok, udp} = :gen_udp.open(Network.mdns_port(), base_udp_opts ++ udp_opts)
    {:reply, :ok, %State{state | udp: udp}}
  end

  def handle_call(:devices, _from, state) do
    {:reply, state.devices, state}
  end

  def handle_call(:stop, _from, %State{udp: nil} = state), do: {:reply, :ok, state}

  def handle_call(:stop, _from, %State{udp: udp} = state) do
    :gen_udp.close(udp)
    {:reply, :ok, %State{state | udp: nil}}
  end

  def handle_cast({:query, namespace}, state) do
    packet = %DNS.Record{
      @query_packet
      | :qdlist => [
          %DNS.Query{domain: to_charlist(namespace), type: :ptr, class: :in}
        ]
    }

    p = DNS.Record.encode(packet)
    :gen_udp.send(state.udp, Network.mdns_group(), Network.mdns_port(), p)
    {:noreply, %State{state | :queries => Enum.uniq([namespace | state.queries])}}
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
    Logger.debug("mDNS got response: #{inspect(record)}")
    device = get_device(ip, record, state)

    devices =
      Enum.reduce(state.queries, %{:other => []}, fn query, acc ->
        cond do
          Enum.any?(device.services, fn service -> String.ends_with?(service, query) end) ->
            {namespace, devices} = create_namespace_devices(query, device, acc, state)
            Mdns.EventManager.notify({namespace, device})
            Logger.debug("mDNS device: #{inspect({namespace, device})}")
            devices

          true ->
            Map.merge(acc, state.devices)
        end
      end)

    %State{state | :devices => devices}
  end

  def handle_device(%DNS.Resource{:type => :ptr} = record, device) do
    %Device{
      device
      | :services =>
          Enum.uniq([to_string(record.data), to_string(record.domain)] ++ device.services)
    }
  end

  def handle_device(%DNS.Resource{:type => :a} = record, device) do
    %Device{device | :domain => to_string(record.domain)}
  end

  def handle_device(%DNS.Resource{:type => :txt, data: data}, device) do
    %Device{
      device
      | :payload =>
          Enum.reduce(data, %{}, fn kv, acc ->
            case String.split(to_string(kv), "=", parts: 2) do
              [k, v] -> Map.put(acc, String.downcase(k), String.trim(v))
              _ -> nil
            end
          end)
    }
  end

  def handle_device(%DNS.Resource{:type => :srv, data: {_priority, _weight, port, _target}}, device) do
    %Device{
      device
      | :port => port
    }
  end

  def handle_device(%DNS.Resource{}, device) do
    device
  end

  def handle_device(%DNS.ResourceOpt{}, device) do
    device
  end

  def handle_device({:dns_rr, _, _, _, _, _, _, _, _, _}, device) do
    device
  end

  def handle_device({:dns_rr_opt, _, _, _, _, _, _, _}, device) do
    device
  end

  def get_device(ip, record, state) do
    orig_device =
      Enum.concat(Map.values(state.devices))
      |> Enum.find(%Device{:ip => ip}, fn device ->
        device.ip == ip
      end)

    Enum.reduce(record.anlist ++ record.arlist, orig_device, fn r, acc ->
      handle_device(r, acc)
    end)
  end

  def create_namespace_devices(query, device, devices, state) do
    namespace = String.to_atom(query)

    {namespace,
     cond do
       Enum.any?(Map.get(state.devices, namespace, []), fn dev -> dev.ip == device.ip end) ->
         Map.merge(devices, %{namespace => merge_device(device, namespace, state)})

       true ->
         Map.merge(devices, %{namespace => [device | Map.get(state.devices, namespace, [])]})
     end}
  end

  def merge_device(device, namespace, state) do
    Enum.map(Map.get(state.devices, namespace, []), fn d ->
      cond do
        device.ip == d.ip -> Map.merge(d, device)
        true -> d
      end
    end)
  end
end
