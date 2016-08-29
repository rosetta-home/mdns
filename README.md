# Mdns

A simple [mDNS](https://en.wikipedia.org/wiki/Multicast_DNS) client for device discovery on your local network.

## Installation

    1. git clone https://github.com/NationalAssociationOfRealtors/mdns.git
    2. mix do deps.get, deps.compile
    3. iex -S mix

## Usage
To discover a device in a namespace call `Mdns.Client.query(namespace \\ "_services._dns-sd._udp.local")`. Compliant devices will respond with a DNS response. `Mdns.Client` will notify the event bus, available at `Mdns.Client.Events`, of any devices it finds.

Calling `Mdns.Client.query("_googlecast._tcp.local")`

assuming you have a Chromecast on your network, an event is broadcasted on `Mdns.Client.Events` that looks like this

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
