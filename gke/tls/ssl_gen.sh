export VAULT_LOAD_BALANCER_IP=10.10.51.11,10.10.51.12,10.10.51.13,10.10.51.14
export VAULT_DEPLOYMENT_NAME=vault-primary
export VAULT_DEPLOYMENT_SECONDARY=vault-secondary
export VAULT_NAMESPACE=default

export SERVICE=vault
export NAMESPACE=default
export SECRET_NAME=vault-server-tls
export TMPDIR=/tmp

cfssl gencert -initca ca-csr.json | cfssljson -bare ca

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname="${VAULT_DEPLOYMENT_NAME},${VAULT_DEPLOYMENT_NAME}-0.${VAULT_NAMESPACE}-internal,${VAULT_DEPLOYMENT_NAME}.default.svc.cluster.local,localhost,127.0.0.1,${VAULT_LOAD_BALANCER_IP}",${VAULT_DEPLOYMENT_SECONDARY},${VAULT_DEPLOYMENT_SECONDARY}-0.${VAULT_NAMESPACE}-internal,${VAULT_DEPLOYMENT_SECONDARY}.default.svc.cluster.local \
  -profile=default \
  vault-csr.json | cfssljson -bare vault

cat vault.pem ca.pem > vault-combined.pem

