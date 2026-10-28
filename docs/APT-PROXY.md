# Making `apt` usable on this network

`apt update` on the phone pulled ~1 KB/s from `releases.droidian.org`, so an
update or an install could take hours. This note records what the problem
actually is and the workaround that is in place.

## What it is not

* Not the phone's Wi-Fi: the same phone pulls 13 MB from `ftp.fau.de` at
  ~1 MB/s and 13 MB from `mirror.yandex.ru` at ~1.4 MB/s.
* Not the server: the Windows box on the same LAN, behind the same NAT
  (identical public IP), downloads the same file at 1–2 MB/s.
* Not MTU, not TCP window scaling, not SACK, not `tcp_rmem`, not power save:
  changing each of those on the phone changed nothing (see below).
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
no response to the FIN. The server simply stops writing, i.e. it is waiting for
something that never arrives, or its retransmissions are dropped before they
reach the phone. Wi-Fi counters (`rx_dropped`, `rx_errors`, `missed`) stay at 0.

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

Same symptom from a phone on the 2.4 GHz band with `signal -73 dBm` and
repeated `wma_roam_stats_event_handler` warnings in `dmesg`; the suspicion is
the AP/station path for this particular destination, but it was not pinned down
further because the workaround below removes the need.

## Is there a mirror?

No. `mirrors.droidian.org` does not resolve, and TUNA / USTC / SJTU / Yandex
have no `droidian` directory (404/403). Droidian publishes only
`releases.droidian.org`, and the frozen snapshots (`/snapshots/102/`) are not
mirrored anywhere. HTTPS on that host is not served at all (port 443 refuses),
which is also why `https://` sources cannot be used.

## Workaround: cache on the LAN

`tools/aptproxy/proxy.py` is a small caching HTTP proxy. It runs on the Windows
box (which reaches the server at full speed), fetches each URL once, keeps it in
`cache/`, and serves the phone over the LAN at ~5 MB/s.

Setup:

```powershell
# on the Windows box
D:\python\pythonw.exe D:\umi\work\aptproxy\proxy.py     # port 3142
```

```bash
# on the phone
echo 'Acquire::http::Proxy "http://192.168.1.12:3142";' \
    > /etc/apt/apt.conf.d/99proxy
apt update
```

Measured after the switch:

| | before | after |
|---|---|---|
| `apt update` (34 MB of indexes) | stalls, effectively never | 21 s first run, 1 s warm |
| `apt-get download libgtk-3-0t64` (2.6 MB) | — | 2 s |

Notes:

* The proxy only handles `http://` (our sources are `http`). `CONNECT` is
  tunnelled but not cached, so an `https` source would work but stay slow.
* Entries never expire; that is fine for a frozen snapshot. Delete
  `D:\umi\work\aptproxy\cache` to start over.
* If the Windows box is off, apt on the phone fails with
  `Connection failed [IP: 192.168.1.12 3142]`. Either start the proxy or drop
  the setting for one run:
  `apt-get -o Acquire::http::Proxy=false update`.
* The proxy is started from the user's Startup folder
  (`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\umi-apt-proxy.lnk`),
  so it comes up at logon. No Windows network settings are touched.
* Under `pythonw.exe` there is no stdout/stderr; the proxy logs to
  `D:\umi\work\aptproxy\proxy.log`.
