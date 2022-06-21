# vault-cluster-primary

## This is an example repo for using the hashicorp starter module

https://github.com/hashicorp/terraform-gcp-vault-ent-starter

# Initialize both clusters
```
vault operator init
```
## check raft status
```
export VAULT_TOKEN=<root token>
vault operator raft list-peers
```

# vault-cluster-primary

# On primary enable dr

## On Primary

```
vault write -f sys/replication/dr/primary/enable
vault write sys/replication/dr/primary/secondary-token id="secondary"
```

# On DR cluster configure replication
### If you have self signed certs it will require the ca_file at the end
```
vault write sys/replication/dr/secondary/enable token="<WRAP TOKEN>" ca_file=/opt/vault/tls/vault-ca.pem
```


## On Primary
```
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
```
## On Primary
```
vault policy list

vault write auth/token/roles/failover-handler     allowed_policies=dr-secondary-promotion     orphan=true     renewable=false     token_type=batch

vault token create -role=failover-handler -ttl=8h
```

## On DR
```
vault write sys/replication/dr/secondary/promote      dr_operation_token="<batch token>"
```
## On Primary
```
vault write -f sys/replication/dr/primary/demote
```

## Get status of DR replication on primary cluster
```
vault read -format=json sys/replication/dr/status

```

