#!/bin/bash

# Usage information
usage() {
    echo "Usage: $0 [-h|-c|-u|-g|-t] [-i <id>] [-f <filepath>]"
    echo "  -h: Display usage information"
    echo "  -c: Create custom rule"
    echo "  -u: Update custom rule"
    echo "  -g: Get rule by ID"
    echo "  -t: Create template for new rule"
    echo "  -i <id>: ID to fetch a rule or create a template based on this ID"
    echo "  -f <filepath>: Path to JSON file (only required for Rule Creation and Updates)"
    exit 1
}

# Check if TOKEN environment variable is set
if [ -z "$AO_TOKEN" ]; then
    echo "Error: AO_TOKEN environment variable is not set"
    exit 1
fi

# Check if TENANT environment variable is set
# Check if TOKEN environment variable is set
if [ -z "$TENANT" ]; then
    echo "Error: TENANT environment variable is not set"
    exit 1
fi

# Parse command-line options
while getopts ":hcugtf:i:" opt; do
    case $opt in
        h)
            usage
            ;;
        c)
            method="POST"
            ;;
        u)
            method="PATCH"
            ;;
        g)
            method="GET"
            ;;
        t)
            template_flag=true
            method="GET"
            ;;
        i)
            id="$OPTARG"
            ;;
        f)
            filepath="$OPTARG"
            ;;
        \?)
            echo "Error: Invalid option -$OPTARG"
            usage
            ;;
        :)
            echo "Error: Option -$OPTARG requires an argument"
            usage
            ;;
    esac
done

# Check if method is provided
if [ -z "$method" ]; then
    usage
fi


# Construct URL based on method
base_url="https://$TENANT.appomni.com/api/v1/detection/rule"

if [ "$method" == "GET" ]; then
    if [ -z "$id" ]; then
        echo "Error: ID is required for GET request"
        usage
    fi
    url="$base_url/$id/"
elif [ "$method" == "PATCH" ] || [ "$method" == "POST" ]; then
    if [ "$method" == "PATCH" ]; then
        action="update"
    else
        action="create"
    fi

    if [ -z "$filepath" ]; then
        echo "Error: Filepath is required for $action request"
        usage
    fi

    json_data=$(cat "$filepath")
    echo "$filepath"
    if [ "$method" == "PATCH" ]; then
        if ! jq -e 'has("id") and has("ruleset_id")' <<< "$json_data" >/dev/null; then
            echo "Error: 'id' and 'ruleset_id' keys must exist in the JSON payload for $action requests"
            exit 1
        fi
        rid=$(jq -r '.id' <<< "$json_data")
    else
        if ! jq -e 'has("ruleset_id")' <<< "$json_data" >/dev/null; then
            echo "Error: 'ruleset_id' key must exist in the JSON payload for $action requests"
            exit 1
        fi
    fi

    url="$base_url/"
    if [ "$method" == "PATCH" ]; then
        url="$base_url/$rid/"
    fi
fi


# Make curl request
if [ "$method" == "GET" ]; then
    response=$(curl -X "$method" \
        -H "Authorization: Bearer $AO_TOKEN" \
        -H "Content-Type: application/json" \
        "$url")
else
    response=$(curl -X "$method" \
        -H "Authorization: Bearer $AO_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$json_data" \
        "$url")
fi

# Create template
create_template() {
    local response="$1"
    # delete keys that cause problems id, ruleset_name - this avoids issues with using AO managed rulesets
    response=$(jq 'del(.id, .ruleset_name)' <<< "$response")
    # clear out the ruleset_id value and make empty string
    response=$(jq '.ruleset_id = ""' <<< "$response")
    rule_name=$(jq -r '.name' <<< "$response")
    # Convert all letters to lowercase
    filename=$(echo "${rule_name// /_}_template.json" | tr '[:upper:]' '[:lower:]')
    mkdir -p "./rules" && echo "$response" | jq '.' > "./rules/$filename"
    echo "Success: $filename created"
}

# Check if curl request was successful - this needs improved
if [ $? -ne 0 ]; then
    echo "Error: request failed"
    exit 1
else
  # remove the rule_config from all returned data - it causes problems for creating/updating rules
  response=$(jq 'del(.rule_config)' <<< "$response")
  resp_id=$(jq -r '.id' <<< "$response")
  if [ "$method" == "GET" ]; then
      if [ "$template_flag" == true ]; then
          create_template "$response"
      else
          echo "$response"
      fi
  elif [ "$method" == "POST" ]; then
      echo "Success: Rule $resp_id created"
  else
      echo "Success: Rule $resp_id updated"
  fi
fi

# Update JSON file with response for POST and PATCH requests
if [ "$method" == "POST" ] || [ "$method" == "PATCH" ]; then
    echo "$response" | jq '.' > "$filepath"
fi

