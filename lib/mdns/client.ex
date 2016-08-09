defmodule Mdns.Client do
    use GenServer
    require Logger

    @mdns_group {224,0,0,251}
    @port 5353
    @query_packet %DNS.Record{
        header: %DNS.Header{},
        qdlist: [
            %DNS.Query{domain: to_char_list("_services._dns-sd._udp.local"), type: :ptr, class: :in},
            #%DNS.Query{domain: to_char_list("_http._tcp.local"), type: :ptr, class: :in},
            #%DNS.Query{domain: to_char_list("_googlecast._tcp.local"), type: :ptr, class: :in},
            #%DNS.Query{domain: to_char_list("_workstation._tcp.local"), type: :ptr, class: :in},
            #%DNS.Query{domain: to_char_list("_sftp-ssh._tcp.local"), type: :ptr, class: :in},
            #%DNS.Query{domain: to_char_list("_ssh._tcp.local"), type: :ptr, class: :in},
            #%DNS.Query{domain: to_char_list("b._dns-sd._udp.local"), type: :ptr, class: :in},
        ]
    }

    defmodule State do
        defstruct devices: [],
            udp: nil,
            events: nil,
            handlers: []
    end

    defmodule Device do
        defstruct ip: nil,
            answers: []
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
        GenEvent.add_mon_handler(events, Mdns.Handler, self)
        {:ok, udp} = :gen_udp.open(@port, udp_options)
        Process.send_after(self(), :discover, 100)
        {:ok, %State{:udp => udp, :events => events, :handlers => [{Mdns.Handler, self}]}}
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
        Logger.debug "<----------------------- New Packet (#{inspect ip}) ------------------------>"
        {:ok, record} = :inet_dns.decode(data)
        qs = :inet_dns.msg(record, :qdlist)
        Logger.debug("QS: #{inspect qs}")
        questions = for q <- qs, do: :maps.from_list(:inet_dns.dns_query(q))
        Logger.debug("Questions: #{inspect questions}")
        answers = rr(:inet_dns.msg(record, :anlist))
        Logger.debug("Answers: #{inspect answers}")
        resources = rr(:inet_dns.msg(record, :arlist))
        Logger.debug("Resources: #{inspect resources}")
        header = :inet_dns.header(:inet_dns.msg(record, :header))
        Logger.debug("Header: #{inspect header}")
        record_type = :inet_dns.record_type(record)
        Logger.debug("Record Type: #{inspect record_type}")
        authorities = rr(:inet_dns.msg(record, :nslist))
        Logger.debug("Authorities: #{inspect authorities}")
        #GenEvent.notify(state.events, {:device, %Device{:ip => ip, :answers => answers}})
        {:noreply, state}
    end

    def handle_info({:device, device}, state) do
        new_state =
            cond do
                Enum.any?(state.devices, fn(dev) -> dev.ip == device.ip end) ->
                    %State{state | :devices => Enum.map(state.devices, fn(d) ->
                        cond do
                            device.ip == d.ip -> %Device{d | :answers => Enum.uniq(device.answers ++ d.answers)}
                            true -> d
                        end
                    end)}
                true ->
                    cond do
                        Enum.any?(device.answers) ->
                            Logger.debug "New Device #{inspect device}"
                            %State{state | :devices => [device | state.devices]}
                        true ->
                            state
                    end
            end
        {:noreply, new_state}
    end

    def rr(resources) do
        for resource <- resources, do: :maps.from_list(:inet_dns.rr(resource))
    end

end
