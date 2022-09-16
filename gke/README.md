# Vault on GKE

## Goal

The goal of this repo is to document and demo spinning up Vault Enterprise on GKE in a production-ready manner.
This includes vault running as a cluster with end-to-end-TLS encryption and the service available to the GKE
as well as VMs within GCP.

## Components

* Vault Enterprise
* GCP Load Balancer w/static IP
* GKE Cluster

## Design Decisions

* Using RAFT for the backend
* Using Self-signed TLS Certs
* Enabling GCP and K8s Auth Methods
* Enable Auto-Unseal via KMS

## Resources

* https://learn.hashicorp.com/tutorials/vault/kubernetes-raft-deployment-guide?in=vault/kubernetes#configure-vault-helm-chart
* https://www.vaultproject.io/docs/platform/k8s/helm/run#architecture
* https://kubernetes.io/docs/tasks/administer-cluster/securing-a-cluster/
* https://www.vaultproject.io/docs/platform/k8s/helm/examples/enterprise-dr-with-raft
* https://learn.hashicorp.com/tutorials/vault/kubernetes-google-cloud-gke?in=vault/kubernetes
* https://www.vaultproject.io/docs/platform/k8s/helm/run#google-kms-auto-unseal
* https://www.vaultproject.io/docs/platform/k8s/helm/examples/injector-tls-cert-manager
* https://github.com/kelseyhightower/vault-on-google-kubernetes-engine

## System Requirements

* helm
* cfssl
* kubectl
* vault
* gcloud

## GCP

We need to setup a runtime environment before we get moving.

### Basic Setup

The following may already be provided for you

* Create a GCP project
* Enable the GKE API and Secrets API
* Create a GKE Cluster

### Vault Specific Setup

* Create an internal static IP address reservation
* Create a custom role to Unlock Vault with the following permissions
  ![Perms](docs/vault-kms.png)
* Create a service account and assign the above role
* Create a key for the Service Account `credentials.json`

  ```bash
  gcloud iam service-accounts keys create key-file \
      --iam-account=${sa-name}@${project-id}.iam.gserviceaccount.com
  ```

## TLS

Best practice for vault is to use end-to-end TLS encryption.
The customer may have their own CA or want to use a signed cert, if that's the case then just ignore this step and use their provided certs.

### Generate TLS Certs

* Update [ssl_gen.sh](tls/ssl_gen.sh) modify the first 3 lines to reflect your environment then run the script to generate certs

```bash
export VAULT_LOAD_BALANCER_IP=10.138.15.207
export VAULT_DEPLOYMENT_NAME=vault
export VAULT_NAMESPACE=vault
```

This will output a number of intermedery files, the imporant ones are:

* ca.pem
* vault-combined.pem
* key.pem

## GKE

Now we should prep the GKE cluster to handle our vault instances.

* Create a `vault` namespace
* Create a K8s secret for the TLS certs

  ```bash
  kubectl create secret -n vault generic vault  \
    --from-file=ca.pem \
    --from-file=vault.pem=vault-combined.pem \
    --from-file=vault-key.pem
  ```

* Add your Vault Enterprise License as a secret

  ```bash
    secret=$(cat vault-enterprise.hclic)
    kubectl create secret -n vault generic vault-ent-license --from-literal="license=${secret}"
  ```

* Add the un-seal Service Account credentials as a secret

  ```bash
  kubectl create secret -n vault generic kms-creds --from-file=credentials.json
  ```

## Helm



We'll use Helm to install and create the pods The chart can be configured to create 2 things:

In the vault-gke-primary directory run this command to install the primary cluster.  Make sure you are pointing to your primary gke cluster

```
cd vault-gke-primary
```

```
helm install vault-primary hashicorp/vault -f config.yaml
```

## Install CSI provider
```
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi secrets-store-csi-driver/secrets-store-csi-driver     --set syncSecret.enabled=true
```

After all of the pods have started then initialize the primary cluster
```
kubectl exec -ti vault-primary-0 -- vault operator init |tee keys.txt
```

There are two loadbalancers one for the main access and one for the active raft node.  The active one is used for replication
```
kubectl apply -f lb-primary.yaml
kubectl apply -f lb-active.yaml
```

In the vault-gke-dr directory run this command to install the secondary cluster.  Make sure you are pointing to your secondary gke cluster
```
helm install vault-secondary hashicorp/vault -f config.yaml
```

After all of the pods have started then initalize the secondary cluster
```
kubectl exec -ti vault-secondary-0 -- vault operator init |tee keys.txt
```

There are two loadbalancers one for the main access and one for the active raft node.  The active one is used for replication
```
kubectl apply -f lb-dr.yaml 
kubectl apply -f lb-active.yaml 
```

## Setup DR example

On Primary (The ip-address needs to be the active loadbalancer for the primary)
```
vault write -f sys/replication/dr/primary/enable primary_cluster_addr=https://10.10.51.12:8201
```


This command creates a token that is used by the secondary cluster
```
vault write sys/replication/dr/primary/secondary-token id=secondary
```

Run this command on the secondary cluster to have it connect to the primary change the token to the what was given in the last command
```
vault write sys/replication/dr/secondary/enable primary_api_addr=https://10.10.51.12:8200 token=<TOKEN> ca_file=/vault/userconfig/vault/ca.pem
```

Monitoring DR setup from Primary cluster
```
vault read -format=json sys/replication/dr/status
```

Example of monitoring output:
```
{
  "request_id": "14a5eb10-8475-fb63-4534-548efb8ac66e",
  "lease_id": "",
  "lease_duration": 0,
  "renewable": false,
  "data": {
    "cluster_id": "fc68a8ce-550d-bba8-7ef5-1f979009b786",
    "known_secondaries": [
      "secondary"
    ],
    "last_dr_wal": 45,
    "last_reindex_epoch": "0",
    "last_wal": 45,
    "merkle_root": "432f936d015e163c3c0e81195ec47d99c880cc28",
    "mode": "primary",
    "primary_cluster_addr": "https://10.10.51.12:8201",
    "secondaries": [
      {
        "api_address": "https://10.196.1.10:8200",
        "cluster_address": "https://vault-secondary-2.vault-secondary-internal:8201",
        "connection_status": "connected",
        "last_heartbeat": "2022-08-02T21:22:08Z",
        "node_id": "secondary"
      }
    ],
    "state": "running"
  },
  "warnings": null
}
```

This site had information on how to promote the secondary to primary and back.

* https://learn.hashicorp.com/tutorials/vault/disaster-recovery


# Example failover from Primary to DR

On Primary create batch token

Create Policy for batch token
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

Create Batch token for failover

```
vault write auth/token/roles/failover-handler     allowed_policies=dr-secondary-promotion     orphan=true     renewable=false     token_type=batch
vault token create -role=failover-handler -ttl=8h | tee batch.txt
```

On Secondary promote to primary
```
vault write sys/replication/dr/secondary/promote dr_operation_token=<DR_TOKEN>
```


On Primary demote to secondary before any secrets are written
```
vault write -f sys/replication/dr/primary/demote
```

On Secondary you have to put in new LoadBalancer so that the old primary can be a secondary

```
export VAULT_TOKEN=<PRIMARY_ROOT_TOKEN>
vault write -f sys/replication/dr/primary/enable primary_cluster_addr=https://10.10.51.14:8201
```

On Secondary create new DR wrapped token
```
vault write sys/replication/dr/primary/secondary-token id=new-secondary
```

On primary setup replication from secondary to primary.
```
vault write sys/replication/dr/secondary/update-primary primary_api_addr=https://10.10.51.14:8200 dr_operation_token=<DR_TOKEN> token=<TOKEN> ca_file=/vault/userconfig/vault/ca.pem
```

Failback to primary cluster

On Primary cluster
```
vault write sys/replication/dr/secondary/promote dr_operation_token=<DR_TOKEN>
```

On Secondary demote from primary status
```
vault write -f sys/replication/dr/primary/demote
```


On primary set the loadbalancer for the primary api again
```
vault write -f sys/replication/dr/primary/enable primary_cluster_addr=https://10.10.51.12:8201
```

On Primary create new replication token
```
vault write sys/replication/dr/primary/secondary-token id=secondary
```

On Secondary setup DR replication from primary
```
vault write sys/replication/dr/secondary/update-primary primary_api_addr=https://10.10.51.12:8200 dr_operation_token=<DR_TOKEN> token=<TOKEN> ca_file=/vault/userconfig/vault/ca.pem
```

# Setup sidecar injection of vault secrets

## Login to vault pod and setup secrets
```
kubectl exec --stdin=true --tty=true vault-0 -- /bin/sh

vault secrets enable -path=secret kv-v2
vault kv put secret/devwebapp/config username='giraffe' password='salsa'
vault kv get secret/devwebapp/config
```
## Enable kubernetes integration
```
vault auth enable kubernetes
vault write auth/kubernetes/config \
        token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
        kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
        kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```
## Create read-only policy and bind service account
```
vault policy write devwebapp - <<EOF
path "secret/data/devwebapp/config" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/devweb-app \
        bound_service_account_names=internal-app \
        bound_service_account_namespaces=default \
        policies=devwebapp \
        ttl=24h
```
## Create kubernetes service account and apply application with annotations
```

kubectl create sa internal-app
kubectl apply --filename devwebapp.yaml
kubectl exec --stdin=true --tty=true devwebapp -c devwebapp -- cat /vault/secrets/credentials.txt
```

# Setup CSI integration 


### Login to vault pod and setup secrets
```
kubectl exec --stdin=true --tty=true vault-0 -- /bin/sh

vault secrets enable -path=secret kv-v2
vault kv put secret/db-pass password="db-secret-password"
vault kv get secret/db-pass
```

### Enable kubernetes integration
```
vault auth enable kubernetes
vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"
```
### Create read-only policy and bind service account
```
vault policy write internal-app - <<EOF
path "secret/data/db-pass" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/database \
    bound_service_account_names=webapp-sa \
    bound_service_account_namespaces=default \
    policies=internal-app \
    ttl=20m

```

### Define secret provider class
```
kubectl apply -f spc-vault-database.yaml
kubectl describe SecretProviderClass vault-database
```


### Create kubernetes service account and apply application with annotations
```
kubectl create serviceaccount webapp-sa
kubectl apply -f webapp-pod.yaml
kubectl exec webapp -- cat /mnt/secrets-store/db-password
```

### Setup SYNC from vault to CSI provide which creates a kubernetes secret and presents it as an ENV variable in the POD

### Apply new secretproviderclass and then apply new application that mounts the secret
```  
kubectl apply -f spc-vault-db-sync.yaml 
kubectl apply -f webapp-sync.yaml 
```

### Get secret and view secret in pod
```
kubectl get secrets dbpass
kubectl exec webapp-sync -- env | grep DB_PASSWORD


