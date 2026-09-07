# MikroTik core-router scripts

Router-side config for the home core-router (`core-router`, `admin@192.168.1.1`,
CCR1016-12S-1S+, RouterOS 7.24.2). **Nothing in this directory is deployed by ArgoCD** — no
`core/<name>.yaml` Application points at it, so it is inert to the GitOps loop. It lives here
purely so the router's scripts are version-controlled instead of existing only on the device.

## `dhcp-dns-lease.rsc` + `dhcp-dns-backfill.rsc` — client names in Pi-hole

### Why

Since 2026-09-07 LAN clients query the Pi-hole VIPs directly (`192.168.1.17`, `192.168.1.19`)
instead of going through the router, so Pi-hole finally sees per-client source IPs. It showed
them as bare IPs, because a *name* requires a reverse (PTR) lookup and **RouterOS answers no PTR
for its DHCP leases**:

```
dig -x 192.168.1.70 @192.168.1.1      # -> empty, before this script
```

Both Pi-hole instances already conditional-forward `1.168.192.in-addr.arpa` to the router
(`dns.revServers` in `home/pihole.yaml`), so anything the router can answer shows up on the
dashboard. These scripts give it something to answer.

### The trick

RouterOS **cannot store PTR records** — `/ip dns static` rejects `type=PTR` outright
(`bad type value PTR`; valid types are A AAAA CNAME TXT SRV NS MX FWD NXDOMAIN). But it
**derives PTR from static A records**. Verified on 7.24.2:

```
dig -x 192.168.1.25 @192.168.1.1   ->  plex.v2.ollebo.com.
dig -x 192.168.1.42 @192.168.1.1   ->  mqqt.v2.local.
```

So the lease script maintains one A record per bound lease and PTR comes for free.

Records are named `<sanitised-hostname>.lan`, **not** `.v2.local`: `/ip dns static` already has a
regex entry `.*\.v2\.local$ -> 192.168.1.16` (traefik, the cluster LAN ingress), regex entries
match before later specific ones, and a client calling itself `plex` or `grafana` should never be
able to shadow an ingress hostname. `.lan` also matches the LAN DHCP server's pre-existing
`add-dns-entries-suffix="lan"`. PTR derivation ignores the suffix, so names work either way.

Every record carries the comment `dhcp-lease-dns`; the script only ever touches entries with that
exact comment, so the hand-made static entries are never at risk.

### Install

```bash
# 1. upload the two bodies (avoids escaping the script into a RouterOS string)
scp dhcp-dns-lease.rsc dhcp-dns-backfill.rsc admin@192.168.1.1:

# 2. create the scripts from the uploaded file contents
/system script add name=dhcp-dns-lease    policy=read,write,test source=[/file get dhcp-dns-lease.rsc contents]
/system script add name=dhcp-dns-backfill policy=read,write,test source=[/file get dhcp-dns-backfill.rsc contents]

# 3. hook the LAN DHCP server. The shim only marshals the lease variables into
#    globals, because /system script run does not inherit the caller's locals.
/ip dhcp-server set [find name=LAN] lease-script=":global lsBound \$leaseBound; :global lsIP \$leaseActIP; :global lsHost \$\"lease-hostname\"; /system script run dhcp-dns-lease"

# 4. populate from the leases that are already bound (the hook only fires on
#    future events, and LAN lease-time is 1d)
/system script run dhcp-dns-backfill
```

### Verify

```bash
dig -x 192.168.1.70 @192.168.1.1        # -> base.lan.
dig -x 192.168.1.70 @192.168.1.17       # -> base.lan.   (through Pi-hole)
```

Then check the dashboard: `GET /api/stats/top_clients` should report
`{"ip": "192.168.1.70", "name": "base.lan"}`. FTL caches client names and only re-resolves on its
periodic cycle (`resolver.refreshNames = "IPV4_ONLY"`), so after a bulk backfill either wait for
the next refresh or `kubectl rollout restart deployment/pihole -n home` — one instance at a time,
since clients now depend on these VIPs.

### Uninstall

```
/ip dhcp-server set [find name=LAN] lease-script=""
:foreach r in=[/ip dns static find where comment="dhcp-lease-dns"] do={/ip dns static remove $r}
/system script remove [find name~"dhcp-dns"]
```

### Notes

- Clients that send no usable hostname simply get no record — at install time that was 14 of 54
  bound LAN leases.
- Forward lookups of `*.lan` work against the router directly, but **not** through Pi-hole: FTL
  ships `[dns.domain] name = "lan", local = true`, i.e. dnsmasq `local=/lan/`, so it answers `.lan`
  authoritatively rather than forwarding. Only PTR is needed for names, so this is left alone. To
  change it, add `true,192.168.1.0/24,192.168.1.1,lan` to `FTLCONF_dns_revServers`.
- The hook is attached to the **LAN** server only. Guest (`192.168.44.0/24`) can be added the same
  way once guest clients are repointed at Pi-hole.
