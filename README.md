# vault-cluster-primary

## This is an example repo for using the hashicorp starter module

https://github.com/hashicorp/terraform-gcp-vault-ent-starter

# Initialize clusters
```
vault operator init
```

##check raft status
```
vault operator raft list-peers
```

# vault-cluster-primary

On primary enable dr

```
vault write -f sys/replication/dr/primary/enable
vault write sys/replication/dr/primary/secondary-token id="secondary"
```

## Setting up DR requires adding the ca_file to the end of the write command on the secondary

```
vault write sys/replication/dr/secondary/enable token="<WRAP TOKEN>" ca_file=/opt/vault/tls/vault-ca.pem
```

## Setting up the primary for DR

```
vault operator init
export VAULT_TOKEN=<root token>
vault operator raft list-peers

vault write -f sys/replication/dr/primary/enable
vault write sys/replication/dr/primary/secondary-token id="secondary"

vault policy list

vault policy write dr-secondary-promotion - <<EOF
path "sys/replication/dr/secondary/promote" {
  capabilities = [ "update" ]
}

# To update the primary to connect

path "sys/replication/dr/secondary/update-primary" {
    capabilities = [ "update" ]
}

# Only if using integrated storage (raft) as the storage backend

# To read the current autopilot status

path "sys/storage/raft/autopilot/state" {
    capabilities = [ "update" , "read" ]
}
EOF

vault policy list
vault write auth/token/roles/failover-handler     allowed_policies=dr-secondary-promotion     orphan=true     renewable=false     token_type=batch
vault token create -role=failover-handler -ttl=8h
vault secrets enable kv
vault kv put kv/username username=csnow
vault kv get kv/username

vault write sys/replication/dr/secondary/promote      dr_operation_token="<batch token>"

vault read -format=json sys/replication/dr/status

```

