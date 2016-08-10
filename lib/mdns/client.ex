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
        defstruct devices: %{:other => []},
            udp: nil,
            events: nil,
            handlers: [],
            ips: [],
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
        GenServer.call(__MODULE__, {:query, namespace})
    end

    def devices do
        GenServer.call(__MODULE__, :devices)
    end

    def add_handler(handler) do
        GenServer.call(__MODULE__, {:handler, handler})
    end

    def init(:ok) do
        ips = Enum.map(elem(:inet.getif(), 1), fn(i) ->
            elem(i, 0)
        end)
        udp_options = [
            :binary,
            active:          true,
            add_membership:  {@mdns_group, {0,0,0,0}},
            multicast_if:    {0,0,0,0},
            multicast_loop:  true,
            multicast_ttl:   255,
            reuseaddr:       true
        ]

        {:ok, events} = GenEvent.start_link([{:name, Mdns.Client.Events}])
        {:ok, udp} = :gen_udp.open(@port, udp_options)
        {:ok, %State{:udp => udp, :events => events, :handlers => [{Mdns.Handler, self}], :ips => ips}}
    end

    def handle_call({:handler, handler}, {pid, _} = from, state) do
        GenEvent.add_mon_handler(state.events, handler, pid)
        {:reply, :ok, %{state | :handlers => [{handler, pid} | state.handlers]}}
    end

    def handle_call(:devices, _from, state) do
        {:reply, state.devices, state}
    end

    def handle_call({:query, namespace}, _from, state) do
        packet = %DNS.Record{@query_packet | :qdlist => [
            %DNS.Query{domain: to_char_list(namespace), type: :ptr, class: :in}
        ]}
        :gen_udp.send(state.udp, @mdns_group, @port, DNS.Record.encode(packet))
        {:reply, :ok,  %State{state | :queries => Enum.uniq([namespace | state.queries])}}
    end

    def handle_info({:gen_event_EXIT, handler, reason}, state) do
        Enum.each(state.handlers, fn(h) ->
            GenEvent.add_mon_handler(state.events, elem(h, 0), elem(h, 1))
        end)
        {:noreply, state}
    end

    def handle_info({:udp, socket, ip, port, packet}, state) do
        {:noreply, cond do
            Enum.any?(state.ips, fn(i) -> i == ip end) -> state
            true -> handle_packet(ip, packet, state)
        end}
    end

    def handle_packet(ip, packet, state) do
        {:ok, record} = :inet_dns.decode(packet)
        qs = :inet_dns.msg(record, :qdlist)
        cond do
            Enum.any?(qs) -> state
            true -> handle_record(ip, record, state)
        end
    end

    def handle_record(ip, record, state) do
        device = get_device(ip, record, state)
        devices =
            Enum.reduce(state.queries, %{:other => []}, fn(query, acc) ->
                cond do
                    Enum.any?(device.services, fn(service) -> String.ends_with?(service, query) end) ->
                        {namespace, devices} = create_namespace_devices(query, device, acc, state)
                        GenEvent.notify(state.events, {namespace, device})
                        devices
                    true -> Map.merge(acc, state.devices)
                end
            end)
        %State{state | :devices => devices}
    end

    def handle_device(%{:type => :ptr} = record, device) do
        %Device{device | :services => Enum.uniq([to_string(record.data) | device.services])}
    end

    def handle_device(%{:type => :a} = record, device) do
        %Device{device | :domain => to_string(record.domain)}
    end

    def handle_device(%{:type => :txt} = record, device) do
        %Device{device | :payload => Enum.reduce(record.data, %{}, fn(kv, acc) ->
            case String.split(to_string(kv), "=", parts: 2) do
                [k, v] -> Map.put(acc, String.downcase(k), String.strip(v))
                _ -> nil
            end
        end)}
    end

    def handle_device(%{:type => type} = record, device) do
        device
    end

    def get_device(ip, record, state) do
        orig_device = Enum.concat(Map.values(state.devices))
        |> Enum.find(%Device{:ip => ip}, fn(device) ->
            device.ip == ip
        end)
        rr(:inet_dns.msg(record, :anlist)) ++ rr(:inet_dns.msg(record, :arlist))
        |> Enum.reduce(orig_device, fn(r, acc) -> handle_device(r, acc) end)
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

    def rr(resources) do
        for resource <- resources, do: :maps.from_list(:inet_dns.rr(resource))
    end

    def other(record) do
        header = :inet_dns.header(:inet_dns.msg(record, :header))
        Logger.debug("Header: #{inspect header}")
        record_type = :inet_dns.record_type(record)
        Logger.debug("Record Type: #{inspect record_type}")
        authorities = rr(:inet_dns.msg(record, :nslist))
        Logger.debug("Authorities: #{inspect authorities}")
    end

end
