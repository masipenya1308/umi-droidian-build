# apt is throttled on this network (unresolved)

`apt update` on the phone pulls ~1 KB/s from `releases.droidian.org`, so
refreshing the indexes or installing anything large takes hours. This note
records what the problem is, what was ruled out, and why the workaround that
was in place is gone.

Status: **unresolved**. The plan is a VPN on the phone; nothing on the build
host or the LAN does any caching any more.

## What it is not

* Not the phone's Wi-Fi: the same phone pulls 13 MB from `ftp.fau.de` at
  ~1 MB/s, 13 MB from `mirror.yandex.ru` at ~1.4 MB/s and 13 MB from
  `deb.debian.org` at ~1.9 MB/s.
* Not the server: the Windows box on the same LAN, behind the same NAT
  (identical public IP), downloads the same file at 1–2 MB/s.
* Not MTU, TCP window scaling, SACK, timestamps, `tcp_rmem` or power save:
  changing each of those changed nothing (table below).
* Not DNS: both machines resolve `releases.droidian.org` to `91.107.236.237`.
* Not HTTP caching: a `?nocache=<random>` request behaves identically.

## What it is

Every TCP flow from the phone to `91.107.236.237:80` dies after **exactly
~33 KB** and never recovers:

```
$ curl -o /dev/null -w '%{size_download}\n' http://releases.droidian.org/.../Packages.gz
33340
$ curl -r 0-1048575 ...        # same
33309
$ ip link set wlan0 mtu 1400   # 32061, scales with MSS -> same segment count
$ ip link set wlan0 mtu 1300   # 29661
```

`tcpdump` on the phone shows the server sending 24 × 1400-byte segments, the
phone ACKing all of them (`ack 33601`), and then nothing: no retransmissions,
no response to the FIN. Wi-Fi counters (`rx_dropped`, `rx_errors`, `missed`)
stay at 0.

Tried and rejected on the phone, each with a fresh measurement:

| Change | Result |
|---|---|
| `net.ipv4.tcp_window_scaling=0` | 33309 bytes |
| `net.ipv4.tcp_timestamps=0` | 33597 bytes |
| `net.ipv4.tcp_sack=0` | 33309 bytes |
| `tcp_rmem` 6 MB, `tcp_moderate_rcvbuf=0` | 33340 bytes |
| MTU 1400 / 1300 | 32061 / 29661 bytes |
| browser User-Agent, `wget`, HTTP/1.0 | 33340 bytes |
| 4 parallel connections | 4 × ~33 KB |
| HTTP request with the `Host:` header split across two packets | 32200 bytes |

## Is there a mirror?

No. `mirrors.droidian.org` does not resolve, and TUNA / USTC / SJTU / Yandex
have no `droidian` directory (404/403). Droidian publishes only
`releases.droidian.org`, and the frozen snapshots (`/snapshots/102/`) are not
mirrored anywhere. HTTPS on that host is not served at all (port 443 refuses),
which is also why `https://` sources cannot be used.

## Which blocking mechanisms are in play

Measured from the phone:

* **DNS filtering**: `speed.hetzner.de` does not resolve at all.
* **SNI-based TLS blocking**: `openssl s_client -connect 88.198.248.254:443
  -servername www.hetzner.com` hangs, while the *same* connection with
  `-servername example.com` completes the handshake immediately.
* **Throttling by destination**: `releases.droidian.org` connects, serves
  ~33 KB and stops; `mirror.hetzner.com` is dead outright over both HTTP and
  HTTPS.

So a DPI-desync tool (zapret / `nfqws`) would address the first two, not the
throttle: it defeats *classification*, not a bandwidth limit on an address
range. Flowseal's `zapret-discord-youtube` is a Windows bundle (`winws.exe` +
`.bat`); the Linux core is `bol-van/zapret`. NFQUEUE is compiled into this
kernel (`/proc/net/netfilter/nfnetlink_queue` exists and `iptables -j NFQUEUE`
accepts a rule even though `modprobe nfnetlink_queue` fails), but there is no
compiler on the phone — the snapshot cannot satisfy `gcc-16` (those URLs answer
`302` without a `Location`) — so `nfqws` would have to be cross-compiled, e.g.
by a GitHub Actions job producing a static aarch64 binary.

## What was tried and removed

A caching HTTP proxy ran on the work PC (port 3142, `Acquire::http::Proxy` on
the phone). It worked — `apt update` went from "never" to 21 s cold / 1 s warm —
but it **broke the PC's connection to the print plotter over the LAN**, so it
was removed completely: process, Startup shortcut, cache, the phone-side
`99proxy` config and the detect script. Do not reintroduce a service on the
build host for this; solve it on the phone (VPN) instead.

## What still works without any workaround

* `apt install` of a package that the snapshot redirects to `deb.debian.org`
  runs at full speed — `deb.debian.org` is fast from the phone and the snapshot
  answers many package URLs with a `302` there.
* `apt install` of a package hosted on the snapshot itself and larger than
  ~33 KB stalls.
* `apt update` (34 MB of indexes on the snapshot) stalls and keeps the old
  lists.

Everything that matters is held or already installed, so in practice the phone
is usable; the missing piece is a way to refresh the indexes.
