# collect-car

Nightly scrape of Swedish used-car listings (dinbil.se, kvd.se, bytbil.com) into the
Mantiser car API at `https://api-car.mantiser.com/api/car`, which writes them to the
`cars` Postgres database on the HRB cluster. Source lives in
[mantiser-com/collect-car](https://github.com/mantiser-com/collect-car).

It runs **here rather than on the HRB cluster on purpose**: this cluster egresses from a
residential IP, and the target sites are bot-sensitive (carla.se already returns HTTP 429
to every datacenter request, which is why it is out of scope).

## Two secrets are not in git

Create both once per cluster rebuild:

```bash
# Bearer token for the car API (same key as mcp-car's API_KEY)
kubectl -n collect-car create secret generic collect-car-api \
  --from-literal=MANTISER_CAR_API_KEY='<key>'

# Pull secret — ghcr.io/mantiser-com/collect-car is a private package
kubectl -n collect-car create secret docker-registry ghcr \
  --docker-server=ghcr.io --docker-username=<github-user> \
  --docker-password='<token with read:packages>'
```

## Operating

```bash
kubectl -n collect-car get cronjob,job,pod
kubectl -n collect-car logs -f job/<job-name>

# Run now, outside the schedule
kubectl -n collect-car create job --from=cronjob/collect-car collect-car-manual
```

A run takes roughly 11 hours, almost all of it bytbil (~78k cars, one detail page each
at ~0.5s). dinbil and kvd finish within minutes and run first, so a bytbil failure never
costs them. `backoffLimit: 0` is deliberate — retrying restarts the whole bytbil walk.

The PVC holds `state/` and `images/`. **Do not delete it**: `state/` is what keeps the
nightly run from re-submitting every car and inflating each record's `version`, and
`images/` is the only place the galleries are stored, since the car API has no image
field.
