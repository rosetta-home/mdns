defmodule Mdns.Server do
  use GenServer
  require Logger

  @mdns_group {224, 0, 0, 251}
  @port Application.get_env(:mdns, :port, 5353)

  @response_packet %DNS.Record{
    header: %DNS.Header{
      aa: true,
      qr: true,
      opcode: 0,
      rcode: 0
    },
    anlist: []
  }

  defmodule State do
    defstruct udp: nil,
              services: [],
              ip: {0, 0, 0, 0}
  end

  defmodule Service do
    defstruct domain: "_nerves._tcp.local",
              data: "_myapp._tcp.local",
              ttl: 120,
              type: :ptr
  end

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def add_service(%Service{} = service) do
    GenServer.call(__MODULE__, {:add_service, service})
  end

  def set_ip(ip) do
    GenServer.call(__MODULE__, {:ip, ip})
  end

  def start(opts \\ []) do
    GenServer.call(__MODULE__, {:start, opts})
  end

  def stop() do
    GenServer.call(__MODULE__, :stop)
  end

  def init(:ok) do
    {:ok, %State{}}
  end

  def handle_call({:start, opts}, _from, state) do
    interface = opts[:interface] || {0, 0, 0, 0}

    udp_options = [
      :binary,
      active: true,
      add_membership: {@mdns_group, interface},
      multicast_if: interface,
      multicast_loop: true,
      multicast_ttl: 255,
      reuseaddr: true
    ]

    {:ok, udp} = :gen_udp.open(@port, udp_options)
    {:reply, :ok, %State{state | udp: udp}}
  end

  def handle_call(:stop, _from, state) do
    if state.udp do
      :gen_udp.close(state.udp)
    end

    {:reply, :ok, %State{state | udp: nil}}
  end

  def handle_call({:ip, ip}, _from, state) do
    {:reply, :ok, %State{state | ip: ip}}
  end

  def handle_call({:add_service, service}, _from, state) do
    {:reply, :ok, %State{state | :services => Enum.uniq([service | state.services])}}
  end

  def handle_info({:udp, _socket, ip, _port, packet}, state) do
    {:noreply, handle_packet(ip, packet, state)}
  end

  def handle_packet(ip, packet, state) do
    record = DNS.Record.decode(packet)

    case record.header.qr do
      false -> handle_query(ip, record, state)
      _ -> state
    end
  end

  def handle_query(_ip, record, state) do
    # Logger.debug("mDNS got query: #{inspect record}")
    Enum.flat_map(record.qdlist, fn %DNS.Query{} = q ->
      Enum.reduce(state.services, [], fn service, answers ->
        cond do
          service.domain == to_string(q.domain) ->
            data =
              case service.data do
                :ip ->
                  state.ip

                _ ->
                  case String.valid?(service.data) do
                    true -> to_charlist(service.data)
                    _ -> service.data
                  end
              end

            [
              %DNS.Resource{
                class: :in,
                type: service.type,
                ttl: service.ttl,
                data: data,
                domain: to_charlist(service.domain)
              }
              | answers
            ]

          true ->
            answers
        end
      end)
    end)
    |> send_service_response(record, state)

    state
  end

  def send_service_response(services, _record, state) do
    cond do
      length(services) > 0 ->
        packet = %DNS.Record{@response_packet | :anlist => services}
        :gen_udp.send(state.udp, @mdns_group, @port, DNS.Record.encode(packet))

      true ->
        nil
    end
  end
end
