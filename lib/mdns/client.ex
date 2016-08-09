defmodule Mdns.Client do
    use GenServer
    require Logger

    @mdns_group {224,0,0,251}
    @port 5353
    @query_packet %DNS.Record{
        header: %DNS.Header{},
        qdlist: [
            %DNS.Query{domain: to_char_list("_services._dns-sd._udp.local"), type: :ptr, class: :in},
            %DNS.Query{domain: to_char_list("_http._tcp.local"), type: :ptr, class: :in},
            %DNS.Query{domain: to_char_list("_googlecast._tcp.local"), type: :ptr, class: :in},
            %DNS.Query{domain: to_char_list("_workstation._tcp.local"), type: :ptr, class: :in},
            %DNS.Query{domain: to_char_list("_sftp-ssh._tcp.local"), type: :ptr, class: :in},
            %DNS.Query{domain: to_char_list("_ssh._tcp.local"), type: :ptr, class: :in},
            %DNS.Query{domain: to_char_list("b._dns-sd._udp.local"), type: :ptr, class: :in},
        ]
    }

    defmodule State do
        defstruct devices: [],
            udp: nil,
            events: nil,
            handlers: [],
            ips: []
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

    def discover do
        GenServer.call(__MODULE__, :discover)
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
        Process.send_after(self(), :discover, 100)
        {:ok, %State{:udp => udp, :events => events, :handlers => [{Mdns.Handler, self}], :ips => ips}}
    end

    def handle_call({:handler, handler}, {pid, _} = from, state) do
        GenEvent.add_mon_handler(state.events, handler, pid)
        {:reply, :ok, %{state | :handlers => [{handler, pid} | state.handlers]}}
    end

    def handle_call(:devices, _from, state) do
        {:reply, state.devices, state}
    end

    def handle_info({:gen_event_EXIT, handler, reason}, state) do
        Enum.each(state.handlers, fn(h) ->
            GenEvent.add_mon_handler(state.events, elem(h, 0), elem(h, 1))
        end)
        {:noreply, state}
    end

    def handle_info(:discover, state) do
        :gen_udp.send(state.udp, @mdns_group, @port, DNS.Record.encode(@query_packet))
        Process.send_after(self(), :discover, 10000)
        {:noreply, state}
    end

    def handle_info({:udp, socket, ip, port, data}, state) do
        {:noreply, cond do
            Enum.any?(state.ips, fn(i) -> i == ip end) -> state
            true -> handle_packet(ip, data, state) |> IO.inspect
        end}
    end

    def handle_packet(ip, data, state) do
        {:ok, record} = :inet_dns.decode(data)
        qs = :inet_dns.msg(record, :qdlist)
        cond do
            Enum.any?(qs) -> state
            true -> handle_device(ip, record, state)
        end
    end

    def handle_device(ip, record, state) do
        Logger.debug "<----------------------- New Packet (#{inspect ip}) ------------------------>"
        orig_device = Enum.find(state.devices, %Device{:ip => ip}, fn(d) -> d.ip == ip end)
        device = rr(:inet_dns.msg(record, :anlist)) ++ rr(:inet_dns.msg(record, :arlist))
        |> Enum.reduce(orig_device, fn(r, acc) -> handle_record(r, acc) end)
        GenEvent.notify(state.events, {:device, device})
        cond do
            Enum.any?(state.devices, fn(dev) -> dev.ip == device.ip end) ->
                %State{state | :devices => Enum.map(state.devices, fn(d) ->
                    cond do
                        device.ip == d.ip -> Map.merge(d, device)
                        true -> d
                    end
                end)}
            true -> %State{state | :devices => [device | state.devices]}
        end
    end

    def handle_record(%{:type => :ptr} = record, device) do
        %Device{device | :services => Enum.uniq([to_string(record.data) | device.services])}
    end

    def handle_record(%{:type => :a} = record, device) do
        %Device{device | :domain => to_string(record.domain)}
    end

    def handle_record(%{:type => :txt} = record, device) do
        %Device{device | :payload => Enum.reduce(record.data, %{}, fn(kv, acc) ->
            case String.split(to_string(kv), "=", parts: 2) do
                [k, v] -> Map.put(acc, String.to_atom(String.downcase(k)), String.strip(v))
                _ -> nil
            end
        end)}
    end

    def handle_record(%{:type => type} = record, device) do
        device
    end

    def other(record) do
        header = :inet_dns.header(:inet_dns.msg(record, :header))
        Logger.debug("Header: #{inspect header}")
        record_type = :inet_dns.record_type(record)
        Logger.debug("Record Type: #{inspect record_type}")
        authorities = rr(:inet_dns.msg(record, :nslist))
        Logger.debug("Authorities: #{inspect authorities}")
    end

    def rr(resources) do
        for resource <- resources, do: :maps.from_list(:inet_dns.rr(resource))
    end

end
