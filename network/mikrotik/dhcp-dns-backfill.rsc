# dhcp-dns-backfill -- one-shot population of the lease-derived DNS records.
#
# The lease script only fires on future lease events, so without this the ~59
# already-bound LAN leases would trickle in over a full day (LAN lease-time=1d).
# This walks every currently-bound lease on the LAN server and runs the exact
# same logic, by setting the same globals the lease-script shim sets.
#
# Reuses dhcp-dns-lease rather than duplicating the sanitiser, so there is only
# ever one definition of what a lease record looks like.
#
# Run once after installing dhcp-dns-lease:
#   /system script run dhcp-dns-backfill
#
# Safe to re-run: dhcp-dns-lease removes its own prior record for an address
# before adding the new one.

:global lsBound
:global lsIP
:global lsHost

:local n 0
:foreach l in=[/ip dhcp-server lease find where status=bound] do={
    :local srv [/ip dhcp-server lease get $l active-server]
    :if ($srv = "LAN") do={
        :set lsBound "1"
        :set lsIP [/ip dhcp-server lease get $l active-address]
        :set lsHost [/ip dhcp-server lease get $l host-name]
        /system script run dhcp-dns-lease
        :set n ($n + 1)
    }
}
:log info "dhcp-dns-backfill: processed $n bound LAN leases"
:put "processed $n bound LAN leases"
