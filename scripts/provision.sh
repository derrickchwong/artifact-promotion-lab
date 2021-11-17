# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Overview
# This script provisions the project using Terraform 0.13+

# Load customer variables
source ./vars.sh
source ./helper.sh

# Verify required environment variables are set
echo -e "${FANCY_NONE} Verifying Required Environment Variables"
REQ_ENVS=("GOOGLE_PROJECT_ID" "REGION" "QWIKLAB_USER_EMAIL")
verify_env_vars "${REQ_ENVS}"

# Verify required CLI tools are on PATH used gcloud, terraform, gsutil
echo -e "${FANCY_NONE} Verifying Required CLI tools"
REQUIRED=("gcloud" "gsutil")
verify_cli_tools "${REQUIRED}"

# these two take a LONG time and terraform is async, run this ahead of time to ensure brand new projects enable these services
echo -e "${FANCY_NONE} Enable services"
gcloud services enable container.googleapis.com compute.googleapis.com binaryauthorization.googleapis.com cloudkms.googleapis.com containeranalysis.googleapis.com cloudresourcemanager.googleapis.com secretmanager.googleapis.com  cloudbuild.googleapis.com > /dev/null 2>&1


KEYRING="binary-authorization"

#############################
# Service Accounts
#############################

DEV_ATTESTOR_SA="development-attestor-sa"
QA_ATTESTOR_SA="qa-attestor-sa"

DEV_ATTESTOR_SA_EMAIL=${DEV_ATTESTOR_SA}@${PROJECT_ID}.iam.gserviceaccount.com
QA_ATTESTOR_SA_EMAIL=${QA_ATTESTOR_SA}@${PROJECT_ID}.iam.gserviceaccount.com

echo -e "${FANCY_NONE} Create attestation Service Accounts"

gcloud iam service-accounts create ${DEV_ATTESTOR_SA} \
   --display-name="Development Attestor Service Account"

gcloud iam service-accounts create ${QA_ATTESTOR_SA} \
   --display-name="QA Attestor Service Account"

gcloud iam service-accounts add-iam-policy-binding ${DEV_ATTESTOR_SA_EMAIL} \
    --member="user:${QWIKLAB_USER_EMAIL}" \
    --role="roles/iam.serviceAccountAdmin"

gcloud iam service-accounts add-iam-policy-binding ${QA_ATTESTOR_SA_EMAIL} \
    --member="user:${QWIKLAB_USER_EMAIL}" \
    --role="roles/iam.serviceAccountAdmin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member=serviceAccount:${DEV_ATTESTOR_SA_EMAIL} \
    --role=roles/containeranalysis.occurrences.editor

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member=serviceAccount:${QA_ATTESTOR_SA_EMAIL} \
    --role=roles/containeranalysis.occurrences.editor

#############################
# GKE clusters
#############################


echo -e "${FANCY_NONE} Create qa-cluster"
gcloud container clusters create "qa-cluster" \
  --project "${PROJECT_ID}" \
  --machine-type "n1-standard-1" \
  --region "${REGION}" \
  --num-nodes "1" \
  --node-locations "${ZONE}" \
  --enable-binauthz &

QA_CLUSTER_PID=$!

echo -e "${FANCY_NONE} Create prod-cluster"
gcloud container clusters create "prod-cluster" \
  --project "${PROJECT_ID}" \
  --machine-type "n1-standard-1" \
  --region "${REGION}" \
  --num-nodes "1" \
  --node-locations "${ZONE}" \
  --enable-binauthz &

PROD_CLUSTER_PID=$!

#############################
# KMS
#############################

echo -e "${FANCY_NONE} Create keyring"
gcloud kms keyrings create "${KEYRING}" \
  --project "${PROJECT_ID}" \
  --location "${REGION}"

echo -e "${FANCY_NONE} Create development-signer"
gcloud kms keys create "development-signer" \
  --project "${PROJECT_ID}" \
  --location "${REGION}" \
  --keyring "${KEYRING}" \
  --purpose "asymmetric-signing" \
  --default-algorithm "rsa-sign-pkcs1-4096-sha512"

echo -e "${FANCY_NONE} Create qa-signer"
gcloud kms keys create "qa-signer" \
  --project "${PROJECT_ID}" \
  --location "${REGION}" \
  --keyring ${KEYRING} \
  --purpose "asymmetric-signing" \
  --default-algorithm "rsa-sign-pkcs1-4096-sha512"

#############################
# DEV attestation
#############################


echo -e "${FANCY_NONE} Create development note"
curl "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/?noteId=development-note" \
  --request "POST" \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $(gcloud auth print-access-token)" \
  --header "X-Goog-User-Project: ${PROJECT_ID}" \
  --data-binary @- <<EOF
    {
      "name": "projects/${PROJECT_ID}/notes/development-note",
      "attestation": {
        "hint": {
          "human_readable_name": "Development Attestation note"
        }
      }
    }
EOF


echo -e "${FANCY_NONE} Create development note IAM"
curl "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/development-note:setIamPolicy" \
  --request POST \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $(gcloud auth print-access-token)" \
  --header "X-Goog-User-Project: ${PROJECT_ID}" \
  --data-binary @- <<EOF
    {
      "resource": "projects/${PROJECT_ID}/notes/development-note",
      "policy": {
        "bindings": [
          {
            "role": "roles/containeranalysis.notes.occurrences.viewer",
            "members": [
              "serviceAccount:${DEV_ATTESTOR_SA_EMAIL}",
              "serviceAccount:${QA_ATTESTOR_SA_EMAIL}"
            ]
          },
          {
            "role": "roles/containeranalysis.notes.attacher",
            "members": [
              "serviceAccount:${DEV_ATTESTOR_SA_EMAIL}"
            ]
          }
        ]
      }
    }
EOF


echo -e "${FANCY_NONE} Create development attestor"
gcloud container binauthz attestors create "development-attestor" \
  --project "${PROJECT_ID}" \
  --attestation-authority-note-project "${PROJECT_ID}" \
  --attestation-authority-note "development-note" \
  --description "Development attestor"

echo -e "${FANCY_NONE} Create development attestor public-keys "
gcloud beta container binauthz attestors public-keys add \
  --project "${PROJECT_ID}" \
  --attestor "development-attestor" \
  --keyversion "1" \
  --keyversion-key "development-signer" \
  --keyversion-keyring "${KEYRING}" \
  --keyversion-location "${REGION}" \
  --keyversion-project "${PROJECT_ID}"

echo -e "${FANCY_NONE} Create development attestor iam-policy-binding"
gcloud container binauthz attestors add-iam-policy-binding "development-attestor" \
  --project "${PROJECT_ID}" \
  --member "serviceAccount:${DEV_ATTESTOR_SA_EMAIL}" \
  --role "roles/binaryauthorization.attestorsViewer"

echo -e "${FANCY_NONE} development-signer iam-policy"
gcloud kms keys add-iam-policy-binding "development-signer" \
  --project "${PROJECT_ID}" \
  --location "${REGION}" \
  --keyring "${KEYRING}" \
  --member "serviceAccount:${DEV_ATTESTOR_SA_EMAIL}" \
  --role 'roles/cloudkms.signerVerifier'


#############################
# QA attestation
#############################



echo -e "${FANCY_NONE} Create qa-note"
curl "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/?noteId=qa-note" \
  --request "POST" \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $(gcloud auth print-access-token)" \
  --header "X-Goog-User-Project: ${PROJECT_ID}" \
  --data-binary @- <<EOF
    {
      "name": "projects/${PROJECT_ID}/notes/qa-note",
      "attestation": {
        "hint": {
          "human_readable_name": "QA Attestation note"
        }
      }
    }
EOF

echo -e "${FANCY_NONE} Create qa-note iam-policy"
curl "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/qa-note:setIamPolicy" \
  --request POST \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $(gcloud auth print-access-token)" \
  --header "X-Goog-User-Project: ${PROJECT_ID}" \
  --data-binary @- <<EOF
    {
      "resource": "projects/${PROJECT_ID}/notes/qa-note",
      "policy": {
        "bindings": [
          {
            "role": "roles/containeranalysis.notes.occurrences.viewer",
            "members": [
              "serviceAccount:${DEV_ATTESTOR_SA_EMAIL}",
              "serviceAccount:${QA_ATTESTOR_SA_EMAIL}"
            ]
          },
          {
            "role": "roles/containeranalysis.notes.attacher",
            "members": [
              "serviceAccount:${QA_ATTESTOR_SA_EMAIL}"
            ]
          }
        ]
      }
    }
EOF


echo -e "${FANCY_NONE} Create qa-attestor"
gcloud container binauthz attestors create "qa-attestor" \
  --project "${PROJECT_ID}" \
  --attestation-authority-note-project "${PROJECT_ID}" \
  --attestation-authority-note "qa-note" \
  --description "QA attestor"

echo -e "${FANCY_NONE} Create qa-attestor public-key"
gcloud beta container binauthz attestors public-keys add \
  --project "${PROJECT_ID}" \
  --attestor "qa-attestor" \
  --keyversion "1" \
  --keyversion-key "qa-signer" \
  --keyversion-keyring "${KEYRING}" \
  --keyversion-location "${REGION}" \
  --keyversion-project "${PROJECT_ID}"

echo -e "${FANCY_NONE} Create qa-attestor binding"


gcloud container binauthz attestors add-iam-policy-binding "qa-attestor" \
  --project "${PROJECT_ID}" \
  --member "serviceAccount:${QA_ATTESTOR_SA_EMAIL}" \
  --role "roles/binaryauthorization.attestorsViewer"


echo -e "${FANCY_NONE} Create qa-signer policy-binding"
gcloud kms keys add-iam-policy-binding "qa-signer" \
  --project "${PROJECT_ID}" \
  --location "${REGION}" \
  --keyring "${KEYRING}" \
  --member "serviceAccount:${QA_ATTESTOR_SA_EMAIL}" \
  --role 'roles/cloudkms.signerVerifier'


echo -e "${FANCY_NONE} Wait for GKE clsuter creation to finish"
wait $QA_CLUSTER_PID
wait $PROD_CLUSTER_PID


echo -e "${FANCY_OK} Done"
#
# echo -e "${FANCY_NONE} Sleeping"
# 
# sleep 1800
