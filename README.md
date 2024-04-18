# AppOmni Threat Detection Rule Manager

The AppOmni Threat Detection Rule Manager is a CLI tool that allows you to manage rules for the AppOmni Threat Detection platform. Today you can create, update, get rules and create templates for new rules based on pre-existing rules.

## Installation
In order to use this CLI tool, you need to ensure that you have the following dependencies installed on your machine:
- [jq](https://stedolan.github.io/jq/)
- [curl](https://curl.se/)

## Setup
1. Clone the repository
2. Run the following command to make the script executable:
```bash 
chmod +x ao_rule_manager.sh
```
4. Optionally you can add the following alias to your `.bashrc` or `.zshrc` file to make it easier to run the script from anywhere:
```bash
alias ao-rule-manager="<path-to-repo>/tools/ao-rule-manager/ao_rule_manager.sh"
or
mv ao_rule_manager.sh /usr/local/bin/ao-rule-manager
```
```bash
source ~/.bashrc
or
source ~/.zshrc
```
5. Set local environment variables for the AppOmni API Key and Tenant ID:
```bash
export AO_TOKEN = "<API_KEY>"
export TENANT = "<subdomain name>" eg "acme" for "acme.appomni.com"
```


## Usage
```bash
Usage: ./ao_rule_manager.sh [-h|-c|-u|-g|-t] [-i <id>] [-f <filepath>]
  -h: Display usage information
  -c: Create custom rule
  -u: Update custom rule
  -g: Get rule by ID
  -t: Create template for new rule
  -i <id>: ID to fetch a rule or create a template based on this ID
  -f <filepath>: Path to JSON file (only required for Rule Creation and Updates)

```

### Working with Rules  
#### Getting a Rule
```bash
ao-rule-manager -g -i <id> | jq .`  #Pipe to jq for pretty printing
```

#### Creating a Rule from Template
Each pre-existing rule belongs to a `ruleset_id` and has a unique `id`. In order to create your own rules it is recommended to create a template based on an existing rule. This can be done by running the following command:
```bash
ao-rule-manager -t -i <id>
```
This will create a template for a new rule based on the rule with the specified `id`. In order to create a new rule based on the template the only requirement is to update the `ruleset_id` field to the `ruleset_id` of a custom `ruleset` that you have created. The id can be retrieved in the browser by navigating to the `Rules` tab and selecting the `ruleset` that you want to add the rule to. The `ruleset_id` will be in the URL.   
```bash
ao-rule-manager -c -f <path-to-json-file>
```