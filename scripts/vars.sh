#!/bin/bash
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

# Google project ID number to deploy resources into
# 3 ways to set this variable:
#   1. Create an environment variable called "PROJECT_ID" with the value of the project-id (no code changes needed)
#   2. Use the current gcloud configuration's value (default if PROJECT_ID is not set)
#   3. Replace the value with your google project in quotes
export GOOGLE_PROJECT_ID="${PROJECT_ID:-$(gcloud config list --format 'value(core.project)')}"

# Name of the GCS bucket for the terraform state. Changing this is optional, by default a
# bucket will be created using the <project-id>-tf-state format within the project.
# 2 ways to change:
#   1. Set an environment variable "TF_STATE_BUCKET" to the name of the bucket (no code changes needed)
#   2. Replace the value with your bucket name in quotes
export TF_STATE_BUCKET="${TF_STATE_BUCKET:-${GOOGLE_PROJECT_ID}-tf-state}"

# Google Service Account
# Should the script create a Google Service Account (GSA) specific to buildling the infrastructure?
# "TRUE" will create a GSA and activate that service account with gcloud so all infrastructre created
# during the provision.sh file will be conducted with that GSA. 'TRUE' is the ONLY recognized value
#
# "FALSE" (default) will use the current user logged into gcloud.
# 2 ways to change:
#   1. Create an environment variable CREATE_INFRA_GSA with the intended value before running this script (no code changes needed)
#   2. Replace the value below with the intended value
export CREATE_INFRA_GSA="${CREATE_INFRA_GSA}:-FALSE"
