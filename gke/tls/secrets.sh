kubectl create secret generic vault    --from-file=ca.pem   --from-file=vault.pem=vault-combined.pem   --from-file=vault-key.pem
secret=$(cat vault-enterprise.hclic)
kubectl create secret generic vault-ent-license --from-literal="license=${secret}"
kubectl create secret generic kms-creds --from-file=credentials.json

