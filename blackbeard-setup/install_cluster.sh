#!/bin/bash

source ./env_vars.sh

export EKS_CLUSTER_NAME=${1:-eks-workshop}
curl -fsSL https://raw.githubusercontent.com/${RepositoryOwner}/${RepositoryName}/${RepositoryRef}/cluster/eksctl/cluster.yaml | envsubst | eksctl create cluster -f -

use-cluster $EKS_CLUSTER_NAME
