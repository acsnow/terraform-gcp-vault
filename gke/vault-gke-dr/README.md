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

* The Vault Cluster
  * Our HA Vault cluster
* [A Vault Agent Injector](https://www.vaultproject.io/docs/platform/k8s/injector)
  * A K8s mutating webhook that allows you to annotate pods to get Vault Secrets

### Configuration

* Build out the [config.yaml](config.yaml)
  * This file will provide overrides to the [Helm Chart](https://www.vaultproject.io/docs/platform/k8s/helm)

