defmodule Mdns.Client do
    use GenServer
    require Logger

    @mdns_group {224,0,0,251}
    @port 5353
    @query_packet %DNS.Record{
        header: %DNS.Header{},
        qdlist: []
    }

    @default_queries [
        %DNS.Query{domain: to_char_list("_services._dns-sd._udp.local"), type: :ptr, class: :in},
        %DNS.Query{domain: to_char_list("_http._tcp.local"), type: :ptr, class: :in},
        %DNS.Query{domain: to_char_list("_googlecast._tcp.local"), type: :ptr, class: :in},
        %DNS.Query{domain: to_char_list("_workstation._tcp.local"), type: :ptr, class: :in},
        %DNS.Query{domain: to_char_list("_sftp-ssh._tcp.local"), type: :ptr, class: :in},
        %DNS.Query{domain: to_char_list("_ssh._tcp.local"), type: :ptr, class: :in},
        %DNS.Query{domain: to_char_list("b._dns-sd._udp.local"), type: :ptr, class: :in},
    ]

    defmodule State do
        defstruct devices: %{},
            udp: nil,
            events: nil,
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

    def add_handler(handler) do
        GenServer.call(__MODULE__, {:handler, handler})
    end

    def start do
        GenServer.call(__MODULE__, :start)
    end

    def init(:ok) do
        {:ok, events} = GenEvent.start_link([{:name, Mdns.Client.Events}])
        {:ok, %State{:events => events}}
    end

    def handle_call(:start, _from, state) do
        udp_options = [
            :binary,
            active:          true,
            add_membership:  {@mdns_group, {0,0,0,0}},
            multicast_if:    {0,0,0,0},
            multicast_loop:  true,
            multicast_ttl:   255,
            reuseaddr:       true
        ]
        {:ok, udp} = :gen_udp.open(@port, udp_options)
        {:reply, :ok, %State{state | udp: udp}}
    end

    def handle_call({:handler, handler}, {pid, _} = from, state) do
        GenEvent.add_mon_handler(state.events, handler, pid)
        {:reply, :ok, %{state | :handlers => [{handler, pid} | state.handlers]}}
    end

    def handle_call(:devices, _from, state) do
        {:reply, state.devices, state}
    end

    def handle_cast({:query, namespace}, state) do
        packet = %DNS.Record{@query_packet | :qdlist => [
            %DNS.Query{domain: to_char_list(namespace), type: :ptr, class: :in}
        ]}
        :gen_udp.send(state.udp, @mdns_group, @port, DNS.Record.encode(packet))
        {:noreply,  %State{state | :queries => Enum.uniq([namespace | state.queries])}}
    end

    def handle_info({:gen_event_EXIT, handler, reason}, state) do
        Enum.each(state.handlers, fn(h) ->
            GenEvent.add_mon_handler(state.events, elem(h, 0), elem(h, 1))
        end)
        {:noreply, state}
    end

    def handle_info({:udp, socket, ip, port, packet}, state) do
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
        Logger.debug("Got Response: #{inspect record}")
        device = get_device(ip, record, state)
        devices =
            Enum.reduce(state.queries, %{:other => []}, fn(query, acc) ->
                cond do
                    Enum.any?(device.services, fn(service) -> String.ends_with?(service, query) end) ->
                        {namespace, devices} = create_namespace_devices(query, device, acc, state)
                        GenEvent.notify(state.events, {namespace, device})
                        Logger.debug("Device: #{inspect {namespace, device}}")
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

    def handle_device({:dns_rr, d, :txt, id, _, _, data, _, _, _} = record, device) do
        %Device{device | :payload => Enum.reduce(data, %{}, fn(kv, acc) ->
            case String.split(to_string(kv), "=", parts: 2) do
                [k, v] -> Map.put(acc, String.downcase(k), String.strip(v))
                _ -> nil
            end
        end)}
    end

    def handle_device(%DNS.Resource{:type => type} = record, device) do
        device
    end

    def handle_device({:dns_rr, _, _, _, _, _, _, _, _, _} = record, device) do
        device
    end

    def handle_device({:dns_rr_opt, _, _, _, _, _, _, _} = record, device) do
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
