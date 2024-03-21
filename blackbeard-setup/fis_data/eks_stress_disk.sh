aws fis create-experiment-template --region $AWS_REGION \
    --cli-input-json '{
        "description": "Inject increasing disk utilization on one or more EKS pods, targeting based on cluster and application label",
        "targets": {
                "EksStressDiskTarget": {
                        "resourceType": "aws:eks:pod",
                        "selectionMode": "ALL",
                        "parameters": {
                                "availabilityZoneIdentifier": "${AWS_REGION}b",
                                "clusterIdentifier": "arn:aws:eks:$AWS_REGION:810918113647:cluster/$EKS_CLUSTER_NAME",
                                "namespace": "carts",
                                "selectorType": "deploymentName",
                                "selectorValue": "carts",
                                "targetContainerName": "carts"
                        }
                }
        },
        "actions": {
                "EksStressDiskAction-010-Disk": {
                        "actionId": "aws:eks:pod-io-stress",
                        "parameters": {
                                "duration": "PT5M",
                                "kubernetesServiceAccount": "fis-experiment",
                                "percent": "60"
                        },
                        "targets": {
                                "Pods": "EksStressDiskTarget"
                        }
                },
                "EksStressDiskAction-020-Disk": {
                        "actionId": "aws:eks:pod-io-stress",
                        "parameters": {
                                "duration": "PT3M",
                                "kubernetesServiceAccount": "fis-experiment",
                                "percent": "70"
                        },
                        "targets": {
                                "Pods": "EksStressDiskTarget"
                        },
                        "startAfter": [
                                "EksStressDiskAction-010-Disk"
                        ]
                },
                "EksStressDiskAction-030-Disk": {
                        "actionId": "aws:eks:pod-io-stress",
                        "parameters": {
                                "duration": "PT3M",
                                "kubernetesServiceAccount": "fis-experiment",
                                "percent": "80"
                        },
                        "targets": {
                                "Pods": "EksStressDiskTarget"
                        },
                        "startAfter": [
                                "EksStressDiskAction-020-Disk"
                        ]
                }
        },
        "stopConditions": [
                {
                        "source": "none"
                }
        ],
        "roleArn": "arn:aws:iam::810918113647:role/fis-eks-experiment-$AWS_REGION",
        "tags": {
                "Name": "EKS Stress: Disk"
        },
        "logConfiguration": {
                "cloudWatchLogsConfiguration": {
                        "logGroupArn": "arn:aws:logs:$AWS_REGION:810918113647:log-group:/aws/fis:*"
                },
                "logSchemaVersion": 2
        },
        "experimentOptions": {
                "accountTargeting": "single-account",
                "emptyTargetResolutionMode": "fail"
        }
}'
