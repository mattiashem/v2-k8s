# HRB v2-k8s — Claude Guide

## Kubernetes Access
- **Kubeconfig:** `~/.kube/confighrb`
- **API server:** `https://10.13.13.1:6443` (router proxy, skip TLS validation)
- **Cluster:** Talos Linux, k8s v1.32.5

```bash
kubectl --kubeconfig=/home/mattias/.kube/confighrb get all -n hrb
```

## Repo Structure
```
hrb/          # HRB namespace — mail stack
code/         # Code namespace
core/         # Core infra — traefik, cert-manager, metallb, etc.
home/         # Home namespace
pbx/          # PBX
runners/      # CI runners
zoe/          # Zoe namespace
```

## Mail Stack (namespace: hrb)
| Component    | Description                        |
|--------------|------------------------------------|
| postfix      | SMTP server                        |
| dovecot      | Runs inside postfix pod, SASL auth |
| amavisd      | Spam/virus filter                  |
| opendkim     | DKIM signing                       |
| mail-admin   | PostfixAdmin UI                    |
| mail-web     | Webmail                            |
| main-mysql   | MySQL StatefulSet (PostfixAdmin DB)|

### MySQL
- Root password in secret `mysql-cluster` → `ROOT_PASSWORD`
- PostfixAdmin DB: host `main-mysql-master`, db `postfixadmin`
- Shell: `kubectl --kubeconfig=~/.kube/confighrb exec -n hrb main-mysql-0 -c mysql -- mysql -uroot -p<password> postfixadmin`

### Dovecot password config
- Mounted via configmap `postfix-config-main` → key `dovecot-sql.conf`
- `default_pass_scheme = BLF-CRYPT`
- MD5-legacy hashes prefixed with `{MD5-CRYPT}` in DB

## Cert-Manager
- ClusterIssuer: `http` (HTTP-01 via Traefik)
- Traefik runs on NodePort — needs router portforward 80→NodePort for cert renewal
- Known issue: `chat.robots.beer` cert stuck pending (port 80 not reachable externally)

## Common Commands
```bash
# List all in hrb namespace
kubectl --kubeconfig=~/.kube/confighrb get all -n hrb

# Check cert issues
kubectl --kubeconfig=~/.kube/confighrb get certificates,challenges -n hrb

# Restart postfix
kubectl --kubeconfig=~/.kube/confighrb rollout restart deployment/postfix -n hrb

# MySQL shell
kubectl --kubeconfig=~/.kube/confighrb exec -n hrb main-mysql-0 -c mysql -- mysql -uroot -pasyd5675ahskdhka postfixadmin
```
