## create irsa for EKS FIS experiments
aws iam create-role --role-name fis-eks-experiment-$AWS_REGION \
  --assume-role-policy-document file://fis_data/setup/eks_fis_trust.json
#
aws iam put-role-policy --role-name fis-eks-experiment-$AWS_REGION \
  --policy-name fis-eks-policy-$AWS_REGION \
  --policy-document file://fis_data/setup/eks_fis_policy.json
#
eksctl create iamidentitymapping \
  --cluster $EKS_CLUSTER_NAME --region $AWS_REGION \
  --arn arn:aws:iam::810918113647:role/fis-eks-experiment-$AWS_REGION \
  --username fis-experiment
#
kubectl apply -f fis_rbac.yaml

## create iam role for EC2 FIS experiments
aws iam create-role --role-name fis-ec2-experiment-$AWS_REGION \
  --assume-role-policy-document file://fis_data/setup/ec2_fis_trust.json
#
aws iam put-role-policy --role-name fis-ec2-experiment-$AWS_REGION \
  --policy-name fis-eks-policy-$AWS_REGION \
  --policy-document file://fis_data/setup/ec2_fis_policy.json

##
#
$(cat eks_stress_disk.sh | envsubst)

## Create schedule
#
aws iam create-role --role-name fis-scheduler-$AWS_REGION \
  --assume-role-policy-document file://fis_data/setup/scheduler_trust.json
#
aws iam put-role-policy --role-name fis-scheduler-$AWS_REGION \
  --policy-name fis-eks-policy-$AWS_REGION \
  --policy-document file://fis_data/setup/scheduler_policy.json

#
aws scheduler create-schedule-group --name fisScheduler --region $AWS_REGION

#
aws scheduler create-schedule --region $AWS_REGION 
