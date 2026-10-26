# Dual-stack mode (IPv6)

```bash
./labctl reset --ipv6            # or: ./labctl up --ipv6
```

The lab boots IPv4-only as usual. Then `ipv6/node-setup.sh` adds IPv6 to every node, derived
from the IPv4 plan:

| What | IPv4 | IPv6 |
|---|---|---|
| Fabric links (one /64 per link) | 10.0.X.Y/31 | fd00:0:X:(Y/2)::1 and ::2 |
| Loopbacks | 10.255.A.B/32 | fd00:255:A::B/128 |
| Server VLANs (gateway = leaf SVI ::1) | 10.10.V.H/24 | 2001:db8:10:V::H/64 |
| "Internet" | 203.0.113.0/24 | 2001:db8:113::/64 |

- **BGP:** separate IPv6 sessions between the same routers, carrying the IPv6 prefixes
  (`show bgp ipv6 unicast summary`).
- **No NAT for IPv6.** Customers reach lb1's own address `2001:db8:10:10::10` directly, and the fw
  only filters. Compare that with the IPv4 DNAT.
- **The app tier stays IPv4-only:** web servers talk to db1 over IPv4, which is a common
  real-world half-way state. DNS has AAAA records for lb1, shop, web1 and web2.
- **The customer probe tests both families separately** (`curl -4` and `curl -6`). `./labctl
  status` shows two lines. Plain `curl` on inet-client prefers IPv6 and falls back to IPv4, so
  some faults only show up as "a bit slower" there.
- **The IPv6 faults are only used in this mode.** IPv4 faults still apply. A ticket written
  for "all customers" may then really mean "IPv4 customers", which is realistic too.

**First run: validate it.** My test environment had no IPv6. I tested the key IPv6 failure
mechanisms on a real kernel, but not this whole lab end to end. Before you use it for practice:

```bash
./labctl reset --ipv6 && ./labctl selftest     # both customer lines (IPv4 + IPv6) must be green
./labctl selftest-faults                        # spoilers! just look at the pass/fail summary
```

If something fails, the error output is what to share for a fix.
