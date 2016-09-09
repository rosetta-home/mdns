defmodule MdnsTest do
    use ExUnit.Case
    doctest Mdns

    test "the truth" do
        assert 1 + 1 == 2
    end

    test "server and client events" do
        Mdns.Server.start
        Mdns.Client.start
        Mdns.Client.add_handler(Mdns.Handler)
        Mdns.Server.set_ip {192, 168, 1, 4}
        Mdns.Server.add_service(%Mdns.Server.Service{
            domain: "_nerves._tcp.local",
            data: "_rosetta._tcp.local",
            ttl: 120,
            type: :ptr
        })
        Mdns.Server.add_service(%Mdns.Server.Service{
            domain: "rosetta.local",
            data: :ip,
            ttl: 120,
            type: :a
        })
        Mdns.Server.add_service(%Mdns.Server.Service{
            domain: "_nerves._tcp.local",
            data: ["id=123123", "port=8800"],
            ttl: 120,
            type: :txt
        })

        Mdns.Client.query("_nerves._tcp.local")
        Mdns.Client.query("rosetta.local")

        assert_receive {:"_nerves._tcp.local", device}, 10_000

    end
end
