#!/bin/bash
export CCE_USER=$(terraform output -raw user_name)
export CCE_CA_CERT=$(terraform output -raw ca_cert)
export CCE_USER_CERT=$(terraform output -raw user_cert)
export CCE_USER_KEY=$(terraform output -raw user_key)
export CCE_CLUSTER_ADDR=$(terraform output -raw cluster_address)
export CCE_CLUSTER_NAME=$(terraform output -raw cluster_name)

read -r -d '' KUBECONFIG <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $CCE_CA_CERT
    server: $CCE_CLUSTER_ADDR
  name: $CCE_CLUSTER_NAME
contexts:
- context:
    cluster: $CCE_CLUSTER_NAME
    user: $CCE_USER
  name: $CCE_CLUSTER_NAME
current-context: $CCE_CLUSTER_NAME
kind: Config
preferences: {}
users:
- name: $CCE_USER
  user:
    client-certificate-data: $CCE_USER_CERT
    client-key-data: $CCE_USER_KEY
EOF
echo "${KUBECONFIG}" > kubeconfig
