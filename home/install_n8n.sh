helm upgrade --install -f n8n-valus.yaml  my-n8n oci://8gears.container-registry.com/library/n8n --namespace home
helm upgrade --install -f n8n-valus-hrb.yaml  hrb-n8n oci://8gears.container-registry.com/library/n8n --namespace home
