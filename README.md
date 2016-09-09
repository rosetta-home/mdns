# Mdns

A simple [mDNS](https://en.wikipedia.org/wiki/Multicast_DNS) client for device discovery on your local network.

## Installation

    1. git clone https://github.com/NationalAssociationOfRealtors/mdns.git
    2. mix do deps.get, deps.compile
    3. iex -S mix

## Server Usage
To add a service to the server call `Mdns.Server.add_service(%Mdns.Server.Service{})` an example service might looks like this.

    Mdns.Server.add_service(%Mdns.Server.Service{
        domain: "_nerves._tcp.local",
        data: "_rosetta._tcp.local",
        ttl: 120,
        type: :ptr
    })

You can also add `:a` records so that your service is available from a web browser.

    Mdns.Server.add_service(%Mdns.Server.Service{
        domain: "rosetta.local",
        data: {192, 168, 1, 4},
        ttl: 120,
        type: :a
    })

And `:txt` records as well.

    Mdns.Server.add_service(%Mdns.Server.Service{
        domain: "_nerves._tcp.local",
        data: ["id=123123", "port=8800"],
        ttl: 120,
        type: :txt
    })

To see the server and client in action run `mix test` and view the code in `test/mdns_test.exs`

Once an `:a` record has been added(with the correct ip) you should be able to run `ping rosetta.local`

    :~$ ping rosetta.local
    PING rosetta.local (192.168.1.4) 56(84) bytes of data.
    64 bytes from 192.168.1.4: icmp_seq=1 ttl=64 time=0.279 ms
    64 bytes from 192.168.1.4: icmp_seq=2 ttl=64 time=0.261 ms
    64 bytes from 192.168.1.4: icmp_seq=3 ttl=64 time=0.329 ms
    64 bytes from 192.168.1.4: icmp_seq=4 ttl=64 time=0.270 ms
    64 bytes from 192.168.1.4: icmp_seq=5 ttl=64 time=0.227 ms
    64 bytes from 192.168.1.4: icmp_seq=6 ttl=64 time=0.215 ms
    ^C
    --- rosetta.local ping statistics ---
    6 packets transmitted, 6 received, 0% packet loss, time 4998ms
    rtt min/avg/max/mdev = 0.215/0.263/0.329/0.040 ms


## Client Usage
To discover a device in a namespace call `Mdns.Client.query(namespace \\ "_services._dns-sd._udp.local")`. Compliant devices will respond with a DNS response. `Mdns.Client` will notify the event bus, available at `Mdns.Client.Events`, of any devices it finds.

Calling `Mdns.Client.query("_googlecast._tcp.local")`

assuming you have a Chromecast on your network, an event is broadcast on `Mdns.Client.Events` that looks like this

    {:"_googlecast._tcp.local",
        %Mdns.Client.Device{
            domain: "CRT-Labs.local",
            ip: {192, 168, 1, 138},
            payload: %{
                "bs" => "FA8FCA79C426",
                "ca" => "4101",
                "fn" => "CRT-Labs",
                "ic" => "/setup/icon.png",
                "id" => "e0617de7e2df63476fab257c8327ef3b",
                "md" => "Chromecast",
                "rm" => "E81C9A486980AA48",
                "rs" => "",
                "st" => "0",
                "ve" => "05"
            },
            services: [
                "CRT-Labs._googlecast._tcp.local"
            ]
        }
    }

After calling `Mdns.Client.query("_ssh._tcp.local")` in addition to the Chromecast call above, `Mdns.Client.devices` will return a devices map similar to this. Assuming you have a device on the network that supports `ssh`.

    %{"_googlecast._tcp.local": [
            %Mdns.Client.Device{
                domain: "CRT-Labs.local",
                ip: {192, 168, 1, 138},
                payload: %{
                    "bs" => "FA8FCA79C426",
                    "ca" => "4101",
                    "fn" => "CRT-Labs",
                    "ic" => "/setup/icon.png",
                    "id" => "e0617de7e2df63476fab257c8327ef3b",
                    "md" => "Chromecast",
                    "rm" => "E81C9A486980AA48",
                    "rs" => "",
                    "st" => "0",
                    "ve" => "05"
                },
                services: [
                    "CRT-Labs._googlecast._tcp.local"
                ]
            }
        ],
        "_ssh._tcp.local": [
            %Mdns.Client.Device{
                domain: "pc-6105006P.local",
                ip: {192, 168, 1, 26},
                payload: nil,
                services: [
                    "pc-6105006P._ssh._tcp.local"
                ]
            }
        ],
        other: []
    }
