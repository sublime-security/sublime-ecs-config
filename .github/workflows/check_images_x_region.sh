#!/bin/bash

set -e

function checkImages() {
  repo=$1
  tag=$2
  primary_sha=$(aws ecr describe-images --region us-east-1 --repository-name $repo --image-ids imageTag=$tag | jq -r '.imageDetails[0].imageDigest')
  if [[ "" == "$primary_sha" ]]; then
    echo "Image was not found in us-east-1! Image has not been pushed!"
    return 1
  fi

  for region in us-east-2 us-west-1 us-west-2 eu-west-1 eu-west-2; do
    sha=$(aws ecr describe-images --region $region --repository-name $repo --image-ids imageTag=$tag | jq -r '.imageDetails[0].imageDigest')

    if [[ "$sha" != "$primary_sha" ]]; then
      echo "Incomplete ECR propagation for repo $repo (tag $tag) in $region. Expected $primary_sha but found $sha."
      return 1
    fi

    echo "ECR propagation for repo $repo (tag $tag) in $region is complete. Found $sha"
  done

  checkImageResult="true"

  return 0
}

