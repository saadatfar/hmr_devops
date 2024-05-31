#!/bin/bash

# Check if the GitLab API token is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <Your GitLab API Token> [--dry-run]"
  exit 1
fi

TOKEN=$1
DRY_RUN=$2

# Iterate over each subfolder in the current directory
for dir in */; do
  if [ -d "$dir" ]; then
    echo -n "$dir --> "
    result=$(cd "$dir" && curl -s https://raw.githubusercontent.com/saadatfar/hmr_devops/main/migrate_helper.sh | bash -s "$TOKEN" $DRY_RUN)
    echo "$result"
  fi
done
