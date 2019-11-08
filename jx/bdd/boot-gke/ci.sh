#!/usr/bin/env bash
set -e
set -x

export GH_USERNAME="jenkins-x-bot-test"
export GH_OWNER="cb-kubecd"
export GH_EMAIL="jenkins-x@googlegroups.com"

# fix broken `BUILD_NUMBER` env var
export BUILD_NUMBER="$BUILD_ID"

JX_HOME="/tmp/jxhome"
KUBECONFIG="/tmp/jxhome/config"

mkdir -p $JX_HOME

jx --version
jx step git credentials

gcloud auth activate-service-account --key-file $GKE_SA

# lets setup git 
git config --global --add user.name JenkinsXBot
git config --global --add user.email $GH_EMAIL

echo "running the BDD tests with JX_HOME = $JX_HOME"

# setup jx boot parameters
export JX_VALUE_ADMINUSER_PASSWORD="$JENKINS_PASSWORD"
export JX_VALUE_PIPELINEUSER_USERNAME="$GH_USERNAME"
export JX_VALUE_PIPELINEUSER_EMAIL="$GH_EMAIL"
export JX_VALUE_PIPELINEUSER_GITHUB_USERNAME="$GH_USERNAME"
export JX_VALUE_PIPELINEUSER_GITHUB_TOKEN="$GH_ACCESS_TOKEN"
export JX_VALUE_PIPELINEUSER_TOKEN="$GH_ACCESS_TOKEN"
export JX_VALUE_PROW_HMACTOKEN="$GH_ACCESS_TOKEN"


# override checking for diffs in jx-requirements.yaml as we need to change it before booting
export OVERRIDE_DIFF_CHECK="true"

# TODO temporary hack until the batch mode in jx is fixed...
export JX_BATCH_MODE="true"

wget https://storage.googleapis.com/artifacts.jenkinsxio.appspot.com/binaries/cjxd/prerelease/0.0.0-SNAPSHOT-PR-1-9/artifacts.tgz
tar -xvf artifacts.tgz
export PATH=$(pwd)/linux:$PATH

jx profile cloudbees

# use the current git SHA being built in the version stream
if [[ -n "${PULL_PULL_SHA}" ]]; then
  sed -i "/^ *versionStream:/,/^ *[^:]*:/s/ref: .*/ref: ${PULL_PULL_SHA}/" jx/bdd/boot-gke/jx-requirements.yml
fi

echo "Using jx/bdd/boot-gke/jx-requirements.yml"
cat jx/bdd/boot-gke/jx-requirements.yml

helm init --client-only
helm repo add jenkins-x https://storage.googleapis.com/chartmuseum.jenkins-x.io

mkdir /workspace/source/reports
export REPORTS_DIR=/workspace/source/reports

mkdir boot-source
cd boot-source

cp ../jx/bdd/boot-gke/jx-requirements.yml .

jx step bdd \
    --use-revision \
    --version-repo-pr \
    --versions-repo https://github.com/cloudbees/cloudbees-jenkins-x-versions.git \
    --gopath /tmp \
    --git-provider=github \
    --config ../jx/bdd/boot-gke/cluster.yaml \
    --git-username $GH_USERNAME \
    --git-owner $GH_OWNER \
    --git-api-token $GH_ACCESS_TOKEN \
    --default-admin-password $JENKINS_PASSWORD \
    --no-delete-app \
    --no-delete-repo \
    --tests install \
    --tests test-verify-pods \
    --tests test-create-spring \
    --tests test-supported-quickstarts \
    --tests test-import
