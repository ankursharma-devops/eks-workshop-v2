set -e

##
## Prerequisites:
## Install below components on your machine:
 # terraform
 # findutils jq tar gzip zsh git diffutils wget nc
 # tree unzip openssl gettext bash-completion python3 pip3 python3-pip

source ./env_vars.sh

#export AWS_REGION="${AwsRegion:-us-east-1}"
#export REPOSITORY_OWNER="${RepositoryOwner:-ankursharma-devops}"
#export REPOSITORY_NAME="${RepositoryName:-eks-workshop-v2}"
#export REPOSITORY_REF="${RepositoryRef:-main}"
#export RESOURCES_PRECREATED="${ResourcesPrecreated:-false}"
#export USERNAME="${UserName}"

#  export CLOUD9_ENVIRONMENT_ID="${EksWorkshopC9Instance}"
#  export ANALYTICS_ENDPOINT="${AnalyticsEndpoint}"

curl -fsSL https://raw.githubusercontent.com/${RepositoryOwner}/${RepositoryName}/${RepositoryRef}/lab/scripts/installer.sh | bash
sudo -E -H bash -c "curl -fsSL https://raw.githubusercontent.com/${RepositoryOwner}/${RepositoryName}/${RepositoryRef}/lab/scripts/setup.sh | bash"
