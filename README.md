# vault-cluster-primary

## This is an example repo for using the hashicorp starter module

https://github.com/hashicorp/terraform-gcp-vault-ent-starter


The vpc directory is there as examples to build the network for usage with the module. 

The tls directory is sample code to create a self signed cert with a local CA that is then added into the GCP secrets manager and used during the node creations.

The license file and the startup script template are both local files and we can change the modules to not require them to be passed in but to pull them from a pre-defined location.
