#!/bin/bash

export AWS_REGION="${AwsRegion:-us-east-1}"
export REPOSITORY_OWNER="${RepositoryOwner:-ankursharma-devops}"
export REPOSITORY_NAME="${RepositoryName:-eks-workshop-v2}"
export REPOSITORY_REF="${RepositoryRef:-main}"
export RESOURCES_PRECREATED="${ResourcesPrecreated:-false}"
export USERNAME="${UserName:-$(whoami)}"
