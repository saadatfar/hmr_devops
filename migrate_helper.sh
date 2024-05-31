#!/bin/bash

converted_url=""
effective_url=""
project_id=""
converted_url=""
input_url=""
is_redirected="false"

convert_url() {
    local input_url="$1"
    if [[ "$input_url" =~ ^git@gitlab\.com: ]]; then
        # Convert git URL to https
        local https_url="${input_url/git@gitlab.com:/https://gitlab.com/}"
        converted_url="${https_url%.git}"
    elif [[ "$input_url" =~ ^https://gitlab\.com/ ]]; then
        # Directly use the https URL
        converted_url="${input_url%.git}"
    else
        echo "Invalid URL format. Please provide a valid GitLab repository URL."
        exit 1
    fi
}

# Function to check for redirection
check_redirection() {
    response=$(curl -s -o /dev/null -w "%{http_code} %{redirect_url}" -H "PRIVATE-TOKEN: $TOKEN" "$converted_url.git")
    http_code=$(echo $response | cut -d' ' -f1)
    effective_url=$(echo $response | cut -d' ' -f2)
    effective_url="${effective_url%.git}"

    if [[ $effective_url != $converted_url ]]; then
        effective_url="${effective_url%.git}"
        is_redirected="true"
    fi
}

# Function to extract project ID from the effective URL
get_project_id() {
    project_api_url="https://gitlab.com/api/v4/projects/$(echo ${effective_url} | sed 's/https:\/\/gitlab.com\///;s/\//%2F/g')"
    response=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$project_api_url")
    project_id=$(echo $response | jq '.id')
    if [[ $project_id == "null" ]]; then
        echo "$iput_url --> Failed to get project ID. Check your token and URL."
        exit 1
    fi
}

# Function to check if the repository is read-only
check_read_only() {
    project_id=$1
    project_access_url="https://gitlab.com/api/v4/projects/${project_id}"
    response=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$project_access_url")

    if [[ $? -ne 0 ]]; then
        echo "Failed to access the project API. Check your token and URL."
        exit 1
    fi

    archived=$(echo $response | jq '.archived')

    if [[ $archived == "true" ]]; then
        echo "$iput_url --> (Archived) Description: $(echo $response | jq '.description')"
        exit 1
    fi
}

# Function to convert effective URL back to the original URL format
convert_back_to_original() {
    local effective_url="$1"
    local input_url="$2"
    if [[ "$input_url" =~ ^git@gitlab\.com: ]]; then
        # Convert https URL back to git URL
        local git_url="${effective_url/https:\/\/gitlab.com\//git@gitlab.com:}"
        echo "${git_url}.git"
    elif [[ "$input_url" =~ ^https://gitlab\.com/ ]]; then
        # Directly use the https URL
        echo "${effective_url}.git"
    else
        echo "Invalid URL format. Please provide a valid GitLab repository URL."
        exit 1
    fi
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install jq to use this script."
    exit 1
fi

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "git could not be found. Please install git to use this script."
    exit 1
fi

# Check if the current directory is a Git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Not git repository."
fi


TOKEN="$1"
DRY_RUN="$2"

# Check if the token is provided
if [[ -z $TOKEN ]]; then
    echo "Please provide a GitLab API token."
    exit 1
fi

# Get input URL from Git origin
input_url=$(git remote get-url origin)
convert_url "$input_url"

check_redirection
get_project_id
check_read_only "$project_id"
if [[ $is_redirected == "false" ]]; then
    echo "$input_url --> Nothing to do"
    exit 1
fi
original_url=$(convert_back_to_original "$effective_url" "$input_url")

if [[ $DRY_RUN == "--dry-run" ]]; then
    echo "$input_url --> ($original_url)"
else
    # Update the origin URL
    git remote set-url origin "$original_url"
    echo "$input_url --> $original_url"
fi
