defmodule MdnsTest do
  use ExUnit.Case
  require Logger
  doctest Mdns

  def get_address() do
    :inet.getifaddrs()
    |> elem(1)
    |> Enum.find(fn {_interface, attr} ->
      Logger.debug("#{inspect attr}")
      case attr |> Keyword.get(:addr) do
        nil -> false
        {127, 0, 0, 1} -> false
        {_, _, _, _, _, _, _, _} -> false
        {_, _, _, _} -> true
      end
    end)
    |> elem(1)
    |> Keyword.fetch(:addr)
    |> elem(1)
  end

  def random_string(length) do
    :crypto.strong_rand_bytes(length) |> Base.url_encode64 |> binary_part(0, length)
  end

  test "client and server" do
    Logger.debug "Testing Server"
    address = get_address()
    Logger.debug "#{inspect address}"
    host_name = "#{random_string(10)}.local"
    Logger.debug("Address: #{inspect address}")
    Logger.debug("Hostname: #{host_name}")
    Mdns.Server.start
    Mdns.EventManager.add_handler(Mdns.Handler)
    Mdns.Server.set_ip address
    Mdns.Server.add_service(%Mdns.Server.Service{
      domain: host_name,
      data: :ip,
      ttl: 10,
      type: :a
    })
    char_host =  host_name |> String.to_charlist()
    lookup = :inet.gethostbyname(char_host, :inet)
    Logger.debug("#{inspect lookup}")
    assert {:ok, {:hostent, char_host , [], :inet, 4, [address]}} = lookup

    Logger.debug "Testing Client"
    Mdns.Client.start
    Mdns.Server.add_service(%Mdns.Server.Service{
      domain: "_nerves._tcp.local",
      data: "_rosetta._tcp.local",
      ttl: 10,
      type: :ptr
    })
    Mdns.Client.query("_nerves._tcp.local")
    assert_receive {:"_nerves._tcp.local", %Mdns.Client.Device{ip: address}}, 10_000

  end
end
