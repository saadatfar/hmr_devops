#!/bin/bash

# Variables
converted_url=""
effective_url=""
project_id=""
is_redirected="false"

# Convert URL function
convert_url() {
    local input_url="$1"
    if [[ "$input_url" =~ ^git@gitlab\.com: ]]; then
        echo "${input_url/git@gitlab.com:/https://gitlab.com/%.git}"
    elif [[ "$input_url" =~ ^https://gitlab\.com/ ]]; then
        echo "${input_url%.git}"
    else
        echo "Invalid URL format. Please provide a valid GitLab repository URL."
        exit 1
    fi
}

# Check for redirection
check_redirection() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code} %{redirect_url}" -H "PRIVATE-TOKEN: $TOKEN" "$converted_url.git")
    local http_code effective_url
    http_code=$(echo "$response" | cut -d' ' -f1)
    effective_url=$(echo "$response" | cut -d' ' -f2)
    effective_url="${effective_url%.git}"

    if [[ "$effective_url" != "$converted_url" ]]; then
        is_redirected="true"
        echo "The URL is being redirected to: $effective_url"
    else
        echo "The URL is not being redirected."
    fi
}

# Extract project ID
get_project_id() {
    local project_api_url response
    project_api_url="https://gitlab.com/api/v4/projects/$(echo "${effective_url}" | sed 's/https:\/\/gitlab.com\///;s/\//%2F/g')"
    response=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$project_api_url")
    project_id=$(echo "$response" | jq '.id')
    if [[ "$project_id" == "null" ]]; then
        echo "Failed to get project ID. Check your token and URL."
        exit 1
    fi
}

# Check if repository is read-only
check_read_only() {
    local project_id="$1" project_access_url response archived
    project_access_url="https://gitlab.com/api/v4/projects/${project_id}"
    response=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$project_access_url")

    if [[ $? -ne 0 ]]; then
        echo "Failed to access the project API. Check your token and URL."
        exit 1
    fi

    archived=$(echo "$response" | jq '.archived')

    if [[ "$archived" == "true" ]]; then
        echo "The repository is archived. This is the description:"
        echo "$(echo "$response" | jq '.description')"
        exit 1
    else
        echo "The repository is not read-only."
    fi
}

# Convert effective URL back to original URL format
convert_back_to_original() {
    local effective_url="$1" input_url="$2"
    if [[ "$input_url" =~ ^git@gitlab\.com: ]]; then
        echo "${effective_url/https:\/\/gitlab.com\//git@gitlab.com:}.git"
    elif [[ "$input_url" =~ ^https://gitlab\.com/ ]]; then
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

TOKEN="$1"
DRY_RUN="$2"

# Check if the token is provided
if [[ -z "$TOKEN" ]]; then
    echo "Please provide a GitLab API token."
    exit 1
fi

# Get input URL from Git origin
input_url=$(git remote get-url origin)
echo "Input URL: $input_url"

converted_url=$(convert_url "$input_url")
echo "$converted_url"
check_redirection
get_project_id
check_read_only "$project_id"

if [[ "$is_redirected" == "false" ]]; then
    echo "Nothing to do."
    exit 1
fi

original_url=$(convert_back_to_original "$effective_url" "$input_url")
echo "New original URL: $original_url"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "This is a dry run. The origin URL will not be updated."
    echo "The original URL would be: $original_url"
else
    git remote set-url origin "$original_url"
    echo "Updated the origin URL to: $original_url"
fi
