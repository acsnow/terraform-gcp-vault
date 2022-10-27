## Setup superuser for that can be used in performance cluster

```
vault policy write superuser -<<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

vault auth enable userpass
vault write auth/userpass/users/tester password="changeme" policies="superuser"
```

## Setup performance replication on primary cluster
```
vault write -f sys/replication/performance/primary/enable primary_cluster_addr=https://10.10.11.202:8201
vault write sys/replication/performance/primary/secondary-token id=performance
```

## Switch to performance cluster 
```
vault write sys/replication/performance/secondary/enable primary_api_addr=https://10.10.11.202:8200 token=<TOKEN> ca_file=/vault/userconfig/vault/ca.pem
```

## Login to performance cluster using the superuser account 
```
vault login -method=userpass username=tester
```

## This will give you a token that can be used to do admin stuff on performance clsuter and setup DR 
```
export VAULT_TOKEN=<TOKEN>
```

## Get status of performance cluster from Primary cluster
```
vault read -format=json sys/replication/performance/status
```

## Setup DR from performance replica
```
vault write -f sys/replication/dr/primary/enable primary_cluster_addr=https://10.10.11.206:8201
vault write sys/replication/dr/primary/secondary-token id=secondary
```

## Switch to performance DR cluster
```
vault write sys/replication/dr/secondary/enable primary_api_addr=https://10.10.11.206:8200 token=<TOKEN> ca_file=/vault/userconfig/vault/ca.pem
```

## Switch back to performance cluster and check status of DR
```
vault read -format=json sys/replication/dr/status
```

## Setup new root token this command with give the OTP which you will need later 

```
vault operator generate-root -init
```

## The next command will require the recovery keys from the primary cluster and you will need to do it 3 times with 3 different keys.

```
vault operator generate-root
```

## This will decode the encoded root key

```
vault operator generate-root -decode=<ENCODED ROOT TOKEN> -otp=<OTP>
```

