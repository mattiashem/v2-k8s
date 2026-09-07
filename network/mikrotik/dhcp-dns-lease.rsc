# dhcp-dns-lease -- body of the core-router DHCP lease script.
#
# PURPOSE
#   Maintain exactly one A record per bound DHCP lease in /ip dns static, named
#   <sanitised-hostname>.lan, so that REVERSE (PTR) lookups of LAN client
#   addresses return a name. That is what makes client names -- rather than bare
#   IPs -- appear on the Pi-hole dashboard: both Pi-hole instances
#   conditional-forward 1.168.192.in-addr.arpa to this router (dns.revServers),
#   so anything registered here shows up within one cache TTL.
#
# WHY A RECORDS AND NOT PTR RECORDS
#   RouterOS cannot store PTR records -- /ip dns static rejects type=PTR
#   outright ("bad type value PTR"; valid types are A AAAA CNAME TXT SRV NS MX
#   FWD NXDOMAIN). It does, however, DERIVE PTR from static A records. Verified
#   on 7.24.2, 2026-09-07:
#     dig -x 192.168.1.25 @192.168.1.1  ->  plex.v2.ollebo.com.
#     dig -x 192.168.1.42 @192.168.1.1  ->  mqqt.v2.local.
#   So one A record per lease is all that is needed.
#
# WHY THE ".lan" SUFFIX AND NOT ".v2.local"
#   /ip dns static already holds a regex entry .*\.v2\.local$ -> 192.168.1.16
#   (traefik, the cluster LAN ingress). Regex entries are matched BEFORE later
#   specific entries, so a lease record called <host>.v2.local would be shadowed
#   for forward lookups anyway -- and a client that happens to call itself
#   "plex" or "grafana" would be one ordering change away from hijacking an
#   ingress hostname. ".lan" is a separate namespace with no wildcard over it,
#   and it matches the LAN DHCP server's existing add-dns-entries-suffix="lan".
#   PTR derivation does not care about the suffix, so names still work.
#
# SAFETY
#   - Only ever touches entries whose comment is exactly "dhcp-lease-dns".
#     The 12 hand-made static entries have other comments and are never seen.
#   - Whole body wrapped in :do/on-error, so a client with a pathological
#     hostname logs a warning instead of breaking DHCP for that lease.
#   - Hostnames are sanitised to a single DNS label: lowercased, anything
#     outside [a-z0-9-] dropped, no leading/trailing dash, capped at 63 chars.
#     A client that sends no usable hostname simply gets no record.
#
# Inputs are passed as globals by the lease-script shim (see INSTALL.md):
#   $lsBound  "1" on bind, "0" on release/expire
#   $lsIP     the leased address
#   $lsHost   the client-supplied hostname (may be empty)

:global lsBound
:global lsIP
:global lsHost

:local suffix "lan"
:local tag "dhcp-lease-dns"

:do {
    # Drop whatever we previously owned for this address, bound or not.
    :foreach r in=[/ip dns static find where comment=$tag address=$lsIP] do={
        /ip dns static remove $r
    }

    :if ($lsBound = "1") do={
        :local raw [:tostr $lsHost]
        :local up "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        :local lo "abcdefghijklmnopqrstuvwxyz"
        :local ok "abcdefghijklmnopqrstuvwxyz0123456789-"
        :local safe ""

        :for i from=0 to=([:len $raw] - 1) do={
            :local c [:pick $raw $i ($i + 1)]
            :local u [:find $up $c]
            :if ([:typeof $u] = "num") do={ :set c [:pick $lo $u ($u + 1)] }
            :if ([:typeof [:find $ok $c]] = "num") do={
                :if ($c = "-") do={
                    # never start a label with a dash
                    :if ([:len $safe] > 0) do={ :set safe ($safe . $c) }
                } else={
                    :set safe ($safe . $c)
                }
            }
        }

        # trailing dash, then max label length
        :if ([:len $safe] > 0) do={
            :if ([:pick $safe ([:len $safe] - 1) [:len $safe]] = "-") do={
                :set safe [:pick $safe 0 ([:len $safe] - 1)]
            }
        }
        :if ([:len $safe] > 63) do={ :set safe [:pick $safe 0 63] }

        :if ([:len $safe] > 0) do={
            :local fqdn ($safe . "." . $suffix)
            # the same name may have moved to a new address
            :foreach r in=[/ip dns static find where comment=$tag name=$fqdn] do={
                /ip dns static remove $r
            }
            /ip dns static add name=$fqdn address=$lsIP type=A ttl=5m comment=$tag
        }
    }
} on-error={
    :log warning "dhcp-dns-lease: failed for $lsIP host=$lsHost bound=$lsBound"
}
