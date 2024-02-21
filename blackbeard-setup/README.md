### Automated scripts to create complete infrastructure for sample retail app and perform clean up

Follow below steps to create complete infrastructure and deploy applications to EKS for sample retail app.

#### Prerequisites:

Before executing below steps make sure you have required packages installed in your system.
And you have aws cli access enabled using ~/.aws/credentials file or environment variables.

```
kubectl
helm
eksctl
yq
amazon-ec2-instance-selector
aws cli v2  

sudo apt-get install -y findutils jq tar gzip zsh git diffutils wget netcat tree unzip openssl gettext bash-completion python3 python3-pip
pip3 install -q awscurl==0.28 urllib3==1.26.6
```

#### Installation steps

1. Run script setup_machine.sh. This script will install some packages and also create some aliases that will be used by subsequent scripts.
2. Run install_cluster.sh. This script creates EKS cluster with a managed node group (min size = 3, max size = 6)
3. Run install_app.sh. This script installs the application, logging and observability tools on the cluster.

Components installed by install_app.sh script.
  - sample retail application
  - ingress for exposing ui component of sample app
  - export control plane logs to cloudwatch
  - export application pod logs to cloudwatch
  - create opensearch domain and send application pod logs to opensearch
  - create amazon managed prometheus workspace and send metrics using open telemetry collector (adot operator). Installs grafana as well
  - send container-insights metrics to aws cloudwatch using open telemetry collector (adot operator)
  - create dynamodb table using EKS ACK (ACK operator for dynamodb) and configure carts deployment to use aws managed dynamodb table

```
bash ./setup_machine.sh
bash ./install_cluster.sh
bash ./install_app.sh
```

#### Changing default variables

All three scripts use env.vars.sh file as source of environment variables.Below are the default but customizable varibale values.

```
AWS_REGION="${AwsRegion:-us-east-1}"
REPOSITORY_OWNER="${RepositoryOwner:-ankursharma-devops}"
REPOSITORY_NAME="${RepositoryName:-eks-workshop-v2}"
REPOSITORY_REF="${RepositoryRef:-main}"
RESOURCES_PRECREATED="${ResourcesPrecreated:-false}"
USERNAME="${UserName:-$(whoami)}"
```
e.g. to change REPOSITORY_REF from default value of main to stable execute, before running any of the install scripts:
`export RepositoryRef="stable"`

### Clean up after usage

To perform clean up of the resources and delete EKS cluster execute below command.

```
DESTROY="true" bash install_app.sh
```
