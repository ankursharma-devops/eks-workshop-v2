#!/bin/bash

source $(dirname $0)/env_vars.sh
export EKS_CLUSTER_NAME=${1:-eks-workshop}
use-cluster $EKS_CLUSTER_NAME
source ~/.bashrc.d/*.bash

export ACCOUNT_ID=${1:-"810918113647"}

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

cloudwatch_pod_logs () {
  # prepare environment for sending pod logs to cloudwatch
  prepare-environment observability/logging/pods
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
  echo -e "\n GRAFANA INGRESS URL:"
  kubectl get ingress -n grafana grafana -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}'
  echo -e "\nGRAFANA admin USER PASSWORD:\n"
  kubectl get -n grafana secrets/grafana -o=jsonpath='{.data.admin-password}' | base64 -d
  echo -e "\n\n####################\nAMP setup completed\n\n#######################"
}

cloudwatch_metrics () {
  # prepare environment for sending metrics to cloudwatch
  prepare-environment observability/container-insights
  # setup ADOT to send metrics to cloudwatch
#  export ADOT_IAM_ROLE_CI="arn:aws:iam::$ACCOUNT_ID:role/eks-workshop-adot-collector"
  kubectl kustomize ~/environment/eks-workshop/modules/observability/container-insights/adot | envsubst | kubectl apply -f-
  kubectl rollout status -n other daemonset/adot-container-ci-collector --timeout=120s
}

ack_dynamodb () {
  echo -e "\n\n####################\nSetup managed dynamodb using ACK operator\n\n#######################"
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

ack_rds () {
  if [ "$DESTROY" == "true" ]
  then
    # vars
    RDS_SUBNET_GROUP_NAME="ack-rds-subnet-group"
    RDS_NAMESPACE=rds-ack
    ## delete rds instance catalog db
    #
    RDS_INSTANCE_NAME="catalog-ack-mysql"
    APP_NAMESPACE="catalog"
    kubectl delete dbinstance $RDS_INSTANCE_NAME -n $APP_NAMESPACE
    ## delete rds instance orders db
    #
    RDS_INSTANCE_NAME="orders-ack-mysql"
    APP_NAMESPACE="orders"
    kubectl delete dbinstance $RDS_INSTANCE_NAME -n $APP_NAMESPACE
    ## delete rds subnet group
    kubectl delete dbsubnetgroup ${RDS_SUBNET_GROUP_NAME} -n $RDS_NAMESPACE
    ## delete security group
    aws ec2 delete-security-group --region $AWS_REGION  \
      --group-name "${RDS_SUBNET_GROUP_NAME}"
    ## delete rds-ack-controller
    helm delete -n $RDS_NAMESPACE ack-rds
    # delete irsa 
    eksctl delete iamserviceaccount --name ack-rds-controller --region $AWS_REGION \
      --cluster $EKS_CLUSTER_NAME

  else
    echo -e "\n\n####################\nSetup RDS MYSQL instance using ACK operator\n\n#######################"
    # generate required variables
    RDS_NAMESPACE=rds-ack
    RDS_SUBNET_GROUP_NAME="ack-rds-subnet-group"
    RDS_SUBNET_GROUP_DESCRIPTION="RDS subnet group"
    EKS_VPC_ID=$(aws eks describe-cluster --name="${EKS_CLUSTER_NAME}" --region $AWS_REGION \
     --query "cluster.resourcesVpcConfig.vpcId" \
     --output text)
    EKS_SUBNET_IDS=$(aws ec2 describe-subnets --region $AWS_REGION \
      --filters "Name=vpc-id,Values=${EKS_VPC_ID}" \
      --query 'Subnets[*].SubnetId' \
      --output text)
    EKS_CIDR_RANGE=$(aws ec2 describe-vpcs \
     --vpc-ids $EKS_VPC_ID \
     --query "Vpcs[].CidrBlock" \
     --output text)
    # create namespace if not exist
    kubectl create namespace $RDS_NAMESPACE --dry-run=client -o yaml | kubectl apply -f-
    # Use irsa and attach role to service account in k8s
    eksctl create iamserviceaccount --name ack-rds-controller --region $AWS_REGION \
      --namespace $RDS_NAMESPACE --cluster $EKS_CLUSTER_NAME \
      --role-name ${EKS_CLUSTER_NAME}-ack-rds-controller \
      --attach-policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess --approve
    aws ecr-public get-login-password  | helm registry login --username AWS --password-stdin public.ecr.aws # --region $AWS_REGION
    # Install ack-rds-controller using helm
    helm upgrade --install -n $RDS_NAMESPACE ack-rds oci://public.ecr.aws/aws-controllers-k8s/rds-chart --version=0.0.27 --set=aws.region=$AWS_REGION --set serviceAccount.create=false
    # create manifest for rds subnet group
cat <<-EOF > db-subnet-groups.yaml
apiVersion: rds.services.k8s.aws/v1alpha1
kind: DBSubnetGroup
metadata:
  name: ${RDS_SUBNET_GROUP_NAME}
  namespace: ${RDS_NAMESPACE}
spec:
  name: ${RDS_SUBNET_GROUP_NAME}
  description: ${RDS_SUBNET_GROUP_DESCRIPTION}
  subnetIDs:
$(printf "    - %s\n" ${EKS_SUBNET_IDS})
EOF
    # apply manifest
    kubectl apply -f db-subnet-groups.yaml
    # Wait for subnet grup to complete
    for i in $(seq 6)
    do
      STATUS=$(kubectl get dbsubnetgroup $RDS_SUBNET_GROUP_NAME -ojson -n ${RDS_NAMESPACE} | jq -r '.status.subnetGroupStatus')
      if [ "$STATUS" == "Complete" ]
      then
        break
      else
        echo "waiting for rds subnet group creation to complete"
        sleep 10s
      fi
    done
    # create security group and add inbound traffic rule
    RDS_SECURITY_GROUP_ID=$(aws ec2 create-security-group --region $AWS_REGION  \
      --group-name "${RDS_SUBNET_GROUP_NAME}" \
      --description "${RDS_SUBNET_GROUP_DESCRIPTION}" \
      --vpc-id "${EKS_VPC_ID}" \
      --output text)
    aws ec2 authorize-security-group-ingress --region $AWS_REGION \
       --group-id "${RDS_SECURITY_GROUP_ID}" \
       --protocol tcp \
       --port 3306 \
       --cidr "${EKS_CIDR_RANGE}"


    ## create rds db instance for catalog app
    ##

    echo -e "###  Creating RDS postgresql for catalog app \n"
    RDS_INSTANCE_NAME="catalog-ack-mysql"
    APP_NAMESPACE="catalog"
    DB_ENGINE="mysql"
    export RDS_DB_NAME="catalog"
    # Set password for DB
    #
    kubectl create secret generic -n $APP_NAMESPACE "${RDS_INSTANCE_NAME}-password" \
    --from-literal=password='beard!#black' --from-literal=username=admin --dry-run=client -o yaml | kubectl apply -f-
    # create instance
    #
    cat ~/environment/eks-workshop/modules/ack-rds/rds-mysql.yaml | envsubst  | kubectl apply -f-
    # wait for rds to create and generate endpoint
    #
    for i in $(seq 10)
    do
      STATUS=$(kubectl get dbinstance $RDS_INSTANCE_NAME  -n ${APP_NAMESPACE} -o json | jq -r '.status.dbInstanceStatus')
      if [ "$STATUS" == "available" ] || [ "$STATUS" == "backing-up" ]
      then
        break
      else
        echo -e "rds not active retrying....\nwaiting for rds creation to complete"
        sleep 30s
      fi
    done
    #
    RDS_DB_ENDPOINT=$(kubectl get dbinstance $RDS_INSTANCE_NAME -n ${APP_NAMESPACE} -o json | jq -r '.status.endpoint.address')
    cat ~/environment/eks-workshop/modules/ack-rds/catalog-patch.yaml | envsubst  | kubectl apply -f-
    kubectl create secret generic -n $APP_NAMESPACE "catalog-db-ack" \
      --from-literal=password='beard!#black' --from-literal=username=admin --dry-run=client -o yaml | kubectl apply -f-
    # Update catalog app to use rds
    kubectl kustomize ~/environment/eks-workshop/modules/ack-rds/catalog-kustomize | envsubst | kubectl apply -f-
    echo -e "### RDS for catalog app created and application updated\n"

    ## create rds db instance for orders app
    ##
    echo -e "###  Creating RDS postgresql for orders app \n"
    RDS_INSTANCE_NAME="orders-ack-mysql"
    APP_NAMESPACE="orders"
    DB_ENGINE="mysql"
    export RDS_DB_NAME="orders"
    # set password for db
    kubectl create secret generic -n $APP_NAMESPACE "${RDS_INSTANCE_NAME}-password" \
    --from-literal=password='beard!#black'
    # create instance
    cat ~/environment/eks-workshop/modules/ack-rds/rds-mysql.yaml | envsubst  | kubectl apply -f-
    # wait for rds to create and generate endpoint
    for i in $(seq 10)
    do
      STATUS=$(kubectl get dbinstance $RDS_INSTANCE_NAME  -n ${APP_NAMESPACE} -o json | jq -r '.status.dbInstanceStatus')
      if [ "$STATUS" == "available" ] || [ "$STATUS" == "backing-up" ]
      then
        break
      else
        echo -e "rds not active retrying....\nwaiting for rds creation to complete"
        sleep 30s
      fi
    done
    #
    RDS_DB_ENDPOINT=$(echo "$(kubectl get dbinstance $RDS_INSTANCE_NAME -n ${APP_NAMESPACE} -o json | jq -r '.status.endpoint.address')")
    export ORDERS_DB_URL=$(echo "jdbc:mariadb://$RDS_DB_ENDPOINT:3306/$RDS_DB_NAME" | base64 -w 0 )
    cat ~/environment/eks-workshop/modules/ack-rds/orders-patch.yaml | envsubst  | kubectl apply -f-
    # Update catalog app to use rds
    kubectl kustomize ~/environment/eks-workshop/modules/ack-rds/orders-kustomize | envsubst | kubectl apply -f-
    echo -e "### RDS for orders app created and application updated\n"
  fi
}


if [ "$DESTROY" == "true" ]
then
  log_file=/eks-workshop/logs/action-$(date +%s).log

  exec 7>&1

  logmessage() {
    echo "$@" >&7
    echo "$@" >&1
  }
  export -f logmessage
  # Remove ack RDS resources; manifests/module/ack-rds
  ack_rds
  export TF_VAR_eks_cluster_id="$EKS_CLUSTER_NAME"
  #remove all installed modules
  for module in automation/controlplanes/ack observability/container-insights observability/oss-metrics observability/opensearch observability/logging/pods observability/logging/cluster exposing/ingress
  do
    echo -e "\n############################REMVOING LAB MODULE: $module \n############################\n"
    if [ -f "/eks-workshop/hooks/$module/cleanup.sh" ]; then
      bash /eks-workshop/hooks/$module/cleanup.sh
    fi
    tf_dir=$(realpath --relative-to="$PWD" "/eks-workshop/terraform/$module")
    terraform -chdir="$tf_dir" init -upgrade
    terraform -chdir="$tf_dir" destroy --auto-approve
    rm -rf /eks-workshop/terraform/$module/addon*.tf
    rm -rf /eks-workshop/hooks/$module
  done
  echo -e "\n############################REMVOING BASE APPLICATION \n############################\n"
  kubectl delete -k /eks-workshop/manifests/base-application
  kubectl delete -k ~/environment/eks-workshop/modules/exposing/ingress/creating-ingress
  eksctl delete cluster --name=$EKS_CLUSTER_NAME --region=$AWS_REGION
else
  base_application
  ingress
  controlplane_logs
  cloudwatch_pod_logs
  opensearch
  managed_prometheus
  cloudwatch_metrics
  ack_dynamodb
  ack_rds
fi
