#!/bin/bash

source ./env_vars.sh
export EKS_CLUSTER_NAME=${1:-eks-workshop}
use-cluster $EKS_CLUSTER_NAME
source ~/.bashrc.d/*.bash

base_application(){
  echo -e "\n\n####################\nDeploying base application\n\n#######################"
  # prepare setup for base application components deployment
  prepare-environment introduction/getting-started
  # deploy all base application components using kustomize
  kubectl apply -k ~/environment/eks-workshop/base-application
  # Wait for all pods to become ready
  kubectl wait --for=condition=Ready --timeout=180s pods -l app.kubernetes.io/created-by=eks-workshop -A
  echo -e "\n\n####################\nBase application deployment completed\n\n#######################"
}

ingress () {
  echo -e "\n\n####################\nSetup Ingress\n\n#######################"
  # prepare environment for ingress
  prepare-environment exposing/ingress
  # deploy ingress for UI service
  kubectl apply -k ~/environment/eks-workshop/modules/exposing/ingress/creating-ingress
  # display loadBalancer URL
  echo -e "\n\n\n#####################LoadBalancer URL to access UI service#################\n\n"
  kubectl get ingress -n ui ui -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}"
  echo -e "\n\n##############################################################################\n\n"
  # wait for AWS loadBalancer to become ready
  wait-for-lb $(kubectl get ingress -n ui ui -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}")
  echo -e "\n\n####################\nIngress setup completed\n\n#######################"
}

controlplane_logs () {
  echo -e "\n\n####################\nUpdate EKS to send controlplane logs to cloudwatch\n\n#######################"
  # prepare environment for enabling control plane logs to cloudwatch
  prepare-environment observability/logging/cluster
  # update cluster config using aws cli
  aws eks update-cluster-config \
      --region $AWS_REGION \
      --name $EKS_CLUSTER_NAME \
      --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
  # sleep for 30 seconds
  sleep 30
  # wait for cluster to become active
  aws eks wait cluster-active --name $EKS_CLUSTER_NAME
  echo -e "\n\n####################\nEKS update completed\n\n#######################"
}

opensearch () {
  echo -e "\n\n###############\nSetup Opensearch\nThis may take up to 30 minutes\n\n#####################"
  # prepare environment for using opensearch and sending application logs to opensearch
  prepare-environment observability/opensearch
  # get env values for opensearch access
  export OPENSEARCH_HOST=$(aws ssm get-parameter \
        --name /eksworkshop/$EKS_CLUSTER_NAME/opensearch/host \
        --region $AWS_REGION | jq .Parameter.Value | tr -d '"')

  export OPENSEARCH_USER=$(aws ssm get-parameter \
        --name /eksworkshop/$EKS_CLUSTER_NAME/opensearch/user  \
        --region $AWS_REGION --with-decryption | jq .Parameter.Value | tr -d '"')

  export OPENSEARCH_PASSWORD=$(aws ssm get-parameter \
        --name /eksworkshop/$EKS_CLUSTER_NAME/opensearch/password \
        --region $AWS_REGION --with-decryption | jq .Parameter.Value | tr -d '"')

  export OPENSEARCH_DASHBOARD_FILE=~/environment/eks-workshop/modules/observability/opensearch/opensearch-dashboards.ndjson

  # load pre-created dashboards to opensearch
  curl -s https://$OPENSEARCH_HOST/_dashboards/auth/login \
        -H 'content-type: application/json' -H 'osd-xsrf: osd-fetch' \
        --data-raw '{"username":"'"$OPENSEARCH_USER"'","password":"'"$OPENSEARCH_PASSWORD"'"}' \
        -c dashboards_cookie | jq .
  curl -s -X POST https://$OPENSEARCH_HOST/_dashboards/api/saved_objects/_import?overwrite=true \
          --form file=@$OPENSEARCH_DASHBOARD_FILE \
          -H "osd-xsrf: true" -b dashboards_cookie | jq .

  # display login URL and creds for opensearch
  echo -e "\n\n\n############################# Opensearch URL and user########################\n\n"
  printf "\nOpenSearch dashboard: https://%s/_dashboards/app/dashboards \nUserName: %q \nPassword: %q \n\n" \
        "$OPENSEARCH_HOST" "$OPENSEARCH_USER" "$OPENSEARCH_PASSWORD"
  echo -e "\n\n#############################################################################\n\n"

  #Install and configure filebeat to send application logs to opensearch
  helm repo add eks https://aws.github.io/eks-charts
  helm upgrade fluentbit eks/aws-for-fluent-bit --install \
      --namespace opensearch-exporter --create-namespace \
      -f ~/environment/eks-workshop/modules/observability/opensearch/config/fluentbit-values.yaml \
      --set="opensearch.host"="$OPENSEARCH_HOST" \
      --set="opensearch.awsRegion"=$AWS_REGION \
      --set="opensearch.httpUser"="$OPENSEARCH_USER" \
      --set="opensearch.httpPasswd"="$OPENSEARCH_PASSWORD" \
      --wait
  echo -e "\n\n####################\nOpensearch Setup Completed\n\n#######################"
}

managed_prometheus () {
  echo -e "\n\n####################\nSetup observability with AMP\n\n#######################"
  # Prepare environment for AMP (Amazon managed prometheus)
  prepare-environment observability/oss-metrics
  # setup adot to send metrics to AMP
  kubectl kustomize ~/environment/eks-workshop/modules/observability/oss-metrics/adot | envsubst | kubectl apply -f-
  echo -e "\n\n####################\nAMP setup completed\n\n#######################"
}

ack_dynamodb () {
  echo -e "\n\n####################\nSetup managed dynamodb using ACK\n\n#######################"
  # prepare environment for ACK dynamodb controller
  prepare-environment automation/controlplanes/ack
  # Use IRSA to provision dynamodb
  eksctl create iamserviceaccount --name carts-ack \
    --namespace carts --cluster $EKS_CLUSTER_NAME \
    --role-name ${EKS_CLUSTER_NAME}-carts-ack \
    --attach-policy-arn $DYNAMODB_POLICY_ARN --approve
  # create dynamodb table and update carts deployment to use ACK created dynamodb
  kubectl kustomize ~/environment/eks-workshop/modules/automation/controlplanes/ack/dynamodb | envsubst | kubectl apply -f-
  # check deployment status
  kubectl rollout status -n carts deployment/carts --timeout=120s
  # check if dynamodb table created and is active
  kubectl wait table.dynamodb.services.k8s.aws items -n carts --for=condition=ACK.ResourceSynced --timeout=15m
  kubectl get table.dynamodb.services.k8s.aws items -n carts -ojson | yq '.status."tableStatus"'
  echo -e "\n\n####################\nManaged dynamodb created using ACK\n\n#######################"
}

base_application
ingress
controlplane_logs
opensearch
managed_prometheus
ack_dynamodb
