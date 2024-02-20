#!/bin/bash

source ./env_vars.sh

export EKS_CLUSTER_NAME=${1:-eks-workshop}
curl -fsSL https://raw.githubusercontent.com/${REPOSITORY_OWNER}/${REPOSITORY_NAME}/${REPOSITORY_REF}/cluster/eksctl/cluster.yaml | envsubst | eksctl create cluster -f -

use-cluster $EKS_CLUSTER_NAME
