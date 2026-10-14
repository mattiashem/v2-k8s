# openclaw credentials

Both openclaw instances read every credential from a cluster-only Secret
(`openclaw/openclaw-secrets`, `openclaw-zoe/openclaw-zoe-secrets`), loaded as env vars.
`openclaw.json` on the PVC only *references* them (`{"source":"env","id":"OC_…"}`,
or `"${OC_…}"` for IRC, whose plugin rejects ref objects).

## Change a key

1. Edit `~/.config/openclaw/<instance>.env` (outside the repo, mode 600). Fill in only
   the keys you want to change. Empty values are skipped, so the live key is kept.
2. `./apply-secrets.sh openclaw --dry-run` shows new / changed / unchanged keys.
3. `./apply-secrets.sh openclaw` merges them into the Secret and restarts the pod.

Instances: `openclaw` (dobby) and `openclaw-zoe` (zoe).

## Add a NEW credential

Adding it to the env file only creates the env var. openclaw uses it once a field
in `openclaw.json` references it. Validate the edited config on a copy first:

```bash
kubectl exec -n <ns> <ns>-0 -- sh -c 'cd ~/.openclaw && cp openclaw.json /tmp/t.json && \
  <edit /tmp/t.json> && OPENCLAW_CONFIG_PATH=/tmp/t.json openclaw config validate && \
  OPENCLAW_CONFIG_PATH=/tmp/t.json openclaw secrets audit'
```

An invalid config crash-loops the gateway with only "The CLI command failed".
