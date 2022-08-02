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
helm install vault-primary hashicorp/vault -f config.yaml
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

Setup DR example

On Primary (The ip-address needs to be the active loadbalancer for the primary)
```
kubectl exec -ti vault-primary-0 -- vault write -f sys/replication/dr/primary/enable primary_cluster_addr=https://10.10.51.12:8201
```


This command creates a token that is used by the secondary cluster
```
kubectl exec -ti vault-primary-0 -- vault write sys/replication/dr/primary/secondary-token id=secondary
```

Run this command on the secondary cluster to have it connect to the primary change the token to the what was given in the last command
```
kubectl exec -ti vault-secondary-0 -- vault write sys/replication/dr/secondary/enable primary_api_addr=https://10.10.51.12:8200 token=eyJhbGciOiJFUzUxMiIsInR5cCI6IkpXVCJ9.eyJhY2Nlc3NvciI6IiIsImFkZHIiOiJodHRwczovLzEwLjIzNi4xLjc6ODIwMCIsImV4cCI6MTY1OTM4OTI5MSwiaWF0IjoxNjU5Mzg3NDkxLCJqdGkiOiJodnMudkRwM2ZaYzJTV1NuTTc1TFRlZkdVcTRMIiwibmJmIjoxNjU5Mzg3NDg2LCJ0eXBlIjoid3JhcHBpbmcifQ.ATymVKEHfAlDSAXGsTuJfdyVTGoqr7quuUECBLBQ95x9AyFFboj1T9cjNybtlr87hgkhhSS0mr6ckiRYcK9wq4J7AdNu8CN1V2VI0PnLjKehYpFmb1ZBuQ7Y1Hx20sluwmh161viS8A4kxha3PYvq-w-LXGmbhJAEiLAXZrWhZJPgftB ca_file=/vault/userconfig/vault/ca.pem
```

Monitoring DR setup
```
kubectl exec -ti vault-primary-0 -- vault read -format=json sys/replication/dr/status
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

This site had information on how to promot the secondary to primary and back.

* https://learn.hashicorp.com/tutorials/vault/disaster-recovery


