#!/bin/bash

# Usage information
usage() {
    echo "Usage: $0 [-h|-c|-u|-g|-t|-s] [-i <id>] [-f <filepath>]"
    echo "  -h: Display usage information"
    echo "  -c: Create custom rule"
    echo "  -u: Update custom rule"
    echo "  -g: Get rule by ID"
    echo "  -t: Create template for new rule"
    echo "  -s: Sync all rules from tenant into folders"
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
if [ -z "$TENANT" ]; then
    echo "Error: TENANT environment variable is not set"
    exit 1
fi

# Parse command-line options
while getopts ":hcugtsf:i:" opt; do
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
        s)
            sync_flag=true
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

# Function to prepare trigger and triage docs
prepare_trigger_triage_docs(){
    local filepath="$1"
    local triage_filename="${filepath%.*}_triage.md"
    local trigger_filename="${filepath%.*}_trigger.md"
    if [ ! -f "$triage_filename" ]; then
        triage_doc=""
    else
        triage_doc=$(cat "$triage_filename")
    fi
    if [ ! -f "$trigger_filename" ]; then
        trigger_doc=""
    else
        trigger_doc=$(cat "$trigger_filename")
    fi
    jq --arg triage_doc "$triage_doc" --arg trigger_doc "$trigger_doc" '. + {triage_doc: $triage_doc, trigger_doc: $trigger_doc}' "$filepath"
}

# Sync all rules with pagination
sync_all_rules() {
    local url="https://$TENANT.appomni.com/api/v1/detection/rule/"
    while [ -n "$url" ]; do
        response=$(curl -s -X GET \
            -H "Authorization: Bearer $AO_TOKEN" \
            -H "Content-Type: application/json" \
            "$url")

        # Extract pagination and results
        next_url=$(jq -r '.next' <<< "$response")
        results=$(jq '.results' <<< "$response")

        # Loop through all rules in the current page
        rule_count=$(jq '. | length' <<< "$results")
        if [ "$rule_count" -gt 0 ]; then
            for ((i=0; i<rule_count; i++)); do
                rule=$(jq ".[$i]" <<< "$results")
                rule_name=$(jq -r '.logic.name' <<< "$rule" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
                rule_dir="./rules/$rule_name"

                # Create directory for the rule
                mkdir -p "$rule_dir"

                # Create trigger and triage docs
                trigger_doc=$(jq -r '.trigger_doc' <<< "$rule")
                triage_doc=$(jq -r '.triage_doc' <<< "$rule")
                echo -e "$trigger_doc" > "$rule_dir/${rule_name}_trigger.md"
                echo -e "$triage_doc" > "$rule_dir/${rule_name}_triage.md"

                # Save rule JSON without trigger and triage docs
                rule=$(jq '.trigger_doc = "" | .triage_doc = ""' <<< "$rule")
                echo "$rule" | jq '.' > "$rule_dir/${rule_name}.json"

                echo "Success: Rule $rule_name synced"
            done
        else
            echo "No rules found for tenant."
        fi

        # Update the URL to the next page (or exit loop if none)
        if [ "$next_url" == "null" ]; then
            url=""
        else
            url="$next_url"
        fi
    done
}

# Sync all rules if -s flag is provided
if [ "$sync_flag" == true ]; then
    sync_all_rules
    exit 0
fi

# Handle other method-based operations
if [ -z "$method" ]; then
    usage
fi

# take the filepath arg and check if a corresponding _triage.md and _triage.md file exists
# if not, set the triage and trigger object keys to empty strings
# if they do exist, set the triage and trigger object keys to the contents of the files
prepare_trigger_triage_docs(){
    local filepath="$1"
    local triage_filename="${filepath%.*}_triage.md"
    local trigger_filename="${filepath%.*}_trigger.md"
    if [ ! -f "$triage_filename" ]; then
        triage_doc=""
    else
        triage_doc=$(cat "$triage_filename")
    fi
    if [ ! -f "$trigger_filename" ]; then
        trigger_doc=""
    else
        trigger_doc=$(cat "$trigger_filename")
    fi
    jq --arg triage_doc "$triage_doc" --arg trigger_doc "$trigger_doc" '. + {triage_doc: $triage_doc, trigger_doc: $trigger_doc}' "$filepath"
}


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
    json_data=$(prepare_trigger_triage_docs "$filepath")

    if [ "$method" == "PATCH" ]; then
        enabled=$(echo "$json_data" | jq -r '.enabled')
        if ! jq -e 'has("id") and has("ruleset_id")' <<< "$json_data" >/dev/null; then
            echo "Error: 'id' and 'ruleset_id' keys must exist in the JSON payload for $action requests"
            exit 1
        # check if "enabled" is true and if not set it - wierd issue with API
        elif [ "$enabled" = "null" ]; then
            # Set the enabled to true in json_data
            json_data=$(jq '.enabled = true' <<< "$json_data")
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
######### - Post Response Activity - #########

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
    # Convert all letters to lowercase
    rule_name=$(jq -r '.logic.name' <<< "$response")
    filename=$(echo "${rule_name// /_}_template.json" | tr '[:upper:]' '[:lower:]')
    # delete keys that cause problems id, ruleset_name - this avoids issues with using AO managed rulesets
    response=$(jq 'del(.id, .ruleset_name, .name)' <<< "$response")
    # clear out the ruleset_id value and make empty string
    response=$(jq '.ruleset_id = ""' <<< "$response")
    mkdir -p "./rules"
    # create a trigger doc with _trigger appended to the filename
    trigger_filename="${filename%.*}_trigger.md"
    trigger_doc=$(echo "$response" | jq -r '.trigger_doc')
    echo -e "$trigger_doc" > "./rules/$trigger_filename"
    triage_filename="${filename%.*}_triage.md"
    triage_doc=$(echo "$response" | jq -r '.triage_doc')
    echo -e "$triage_doc" > "./rules/$triage_filename"
    # Set the trigger_doc and triage_doc to empty strings and write the rule file
    response=$(jq '.trigger_doc = "" | .triage_doc = ""' <<< "$response")
    echo "$response" | jq '.' > "./rules/$filename"
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
   # set trigger and triage keys to empty
    response=$(jq '.trigger_doc = "" | .triage_doc = ""' <<< "$response")
    echo "$response" | jq '.' > "$filepath"
fi

