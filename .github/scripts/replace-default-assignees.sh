#! /bin/bash
# --------------------------------------------------------------------------------------------------------------------
# [L483] replace-default-assignees.sh
#        Replaces the "assignees" field of a GitHub "issue form" YAML file with the specified assignees.
#        The file is modified in-place.
#        For further information, consult --help.
# --------------------------------------------------------------------------------------------------------------------

# script run options: start ------------------------------------------------------------------------------------------

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # do not hide errors within pipes
# set -o verbose # trace every executed command (before variable expansion)
# set -o xtrace  # trace what gets actually executed (after variable expansion)

# script run options: end --------------------------------------------------------------------------------------------
# functions: start ---------------------------------------------------------------------------------------------------

# Function:
#   find_assignees_start
# Description:
#   Finds the index of the "assignees" field in a GitHub "issue form" YAML file.
# Arguments:
#   @param file: the path to the file to be processed
# Returns:
#   @return: the index of the line via echo
find_assignees_start() {
    # extract arguments
    local -r file="${1}"
    
    # setup regex patterns
    local -r assignees_field_start="^assignees:\s*$"
    
    # find the index of the line marking the start of the "assignees" field's entries
    local -r start_line=$(grep -n -m 1 -P "${assignees_field_start}" "${file}" | cut -d: -f1)
    
    # use echo's output as a return value substitute
    echo "${start_line}"
}

# Function:
#   count_assignees
# Description:
#   Counts the number of entries in the "assignees" field of a GitHub "issue form" YAML file.
# Arguments:
#   @param file: the path to the file to be processed
#   @param start_line: the index of the line beginning the "assignees" field
# Returns:
#   @return: the number of entries via echo
count_assignees() {
    # extract arguments
    local -r file="${1}"
    local -r start_line="${2}"
    
    # create utility variable
    local -r sed_start_line=$((start_line+1))
    
    # setup regex patterns
    # username pattern for GitHub usernames:
    #   - must be at least 1 character long
    #   - must be at most 39 characters long
    #   - must start and end with an alphanumeric character
    #   - must contain only alphanumeric characters or hyphens
    #   - cannot have multiple consecutive hyphens
    local -r username_pattern="[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,38}"
    # assignee line pattern:
    #   - must be indented with at least one space
    #   - must start with a hyphen followed by a space (after the indentation)
    #   - must end with a GitHub username
    local -r assignee_line="^\s+- ${username_pattern}\s*$"
    # variable to store the most recent matching result
    local match
    
    # create a counter variable to keep track of the number of matching lines
    local number_of_assignees=0
    # consecutively read lines until matching a line to assignee_line fails
    while IFS= read -r line; do
        match=$(echo "${line}" | grep -iP "${assignee_line}" || true)
        if [[ -n "${match}" ]]; then
            number_of_assignees=$((number_of_assignees+1))
        else
            break
        fi
        # red from sed_start_line to the end of the file, and only use these lines as input for the while loop
    done < <(sed -n "${sed_start_line},\$p" "${file}") # process substitution to not lose the value of number_of_assignees
    
    # use echo's output as a return value substitute
    echo "${number_of_assignees}"
}

# Function:
#   remove_assignees
# Description:
#   Removes the entries of the "assignees" field of a GitHub "issue form" YAML file.
# Arguments:
#   @param file: the path to the file to be processed
#   @param start_line: the index of the line beginning the "assignees" field
#   @param number_of_assignees: the number of entries in the "assignees" field
# Returns:
#   Nothing
remove_assignees() {
    # extract arguments
    local -r file="${1}"
    local -r start_line="${2}"
    local -r number_of_assignees="${3}"
    
    # create utility variable
    local -r sed_start_line=$((start_line+1))
    
    # delete old assignees from file, if there are any
    if [[ "${number_of_assignees}" -gt 0 ]]; then
        local -r end_line=$((start_line+number_of_assignees))
        sed -arg "${sed_start_line},${end_line}d" "${file}"
    fi
}

# Function:
#   append_assignees
# Description:
#   Appends a list of entries to the "assignees" field of a GitHub "issue form" YAML file.
# Arguments:
#   @param file: the path to the file to be processed
#   @param start_line: the index of the line beginning the "assignees" field
#   @param assignees: the list of assignees to be appended
# Returns:
#   Nothing
append_assignees() {
    # extract arguments
    local -r file="${1}"
    local -r start_line="${2}"
    local -r assignees=("${@:3}")
    
    # create new assignees entries
    local new_assignees=""
    for assignee in "${assignees[@]}"
    do
        # currently, the indentation level is hard-coded as 2 spaces
        new_assignees+="  - ${assignee}\n"
    done
    
    # remove trailing newline "\n"
    new_assignees=${new_assignees::-2}
    
    # append new assignees
    sed -arg "${start_line}a\\${new_assignees}" "${file}"
}

# Function:
#   handle_issue_form
# Description:
#   Replaces the "assignees" field of a GitHub "issue form" YAML file with the specified assignees.
#   The file is modified in-place.
#   If both the "append_only" and "delete_only" arguments are "true", the file remains unchanged.
# Arguments:
#   @param file: the path to the file to be processed
#   @param append_only: if "true", no assignees are deleted
#   @param delete_only: if "true", no assignees are appended
#   @param assignees: the list of assignees to be appended
# Returns:
#   Nothing
handle_issue_form() {
    # file append_only delete_only assignees
    # extract arguments
    local -r file="${1}"
    local -r append_only="${2}"
    local -r delete_only="${3}"
    local -r assignees=("${@:4}")
    
    # get information about assignees the file lists
    local -r start_line=$(find_assignees_start "${file}")
    local number_of_assignees
    number_of_assignees=$(count_assignees "${file}" "${start_line}")
    
    # conditionally remove assignees
    if [[ "${append_only}" == false ]]; then
        remove_assignees "${file}" "${start_line}" "${number_of_assignees}"
        number_of_assignees=0
    fi
    
    # conditionally append assignees
    if [[ "${delete_only}" == false ]]; then
        local -r append_line=$((start_line+number_of_assignees))
        append_assignees "${file}" "${append_line}" "${assignees[@]}"
    fi
}

# Function:
#   usage
# Description:
#   Prints the script's documentation to stdout.
# Arguments:
#   None
# Returns:
#   Nothing
usage() {
    echo "Usage: ${0} [-a|--append-only] [-d|--delete-only] [assignees...]"
    echo "Replaces the \"assignees\" field of a GitHub \"issue form\" YAML file with the specified assignees."
    echo "The file is modified in-place."
    echo ""
    echo "Options:"
    echo "  -a | --append-only      no assignees are deleted"
    echo "  -d | --delete-only      no assignees are appended"
    echo "  -h | --help             print this usage information"
    echo ""
    echo "Arguments:"
    echo "  assignees: the list of assignees to be appended"
    echo ""
    echo "Exit status:"
    echo "  0: if the script was executed successfully"
    echo "  1: if an unexpected option was passed"
    echo ""
    echo "If both the \"append-only\" and \"delete-only\" options are set, the file remains unchanged."
    echo "If no arguments are passed, the script prints this usage information."
    echo "To clear the \"assignees\" field, pass the \"delete-only\" option without any assignees."
}

# functions: end -----------------------------------------------------------------------------------------------------
# main script: start -------------------------------------------------------------------------------------------------

# if no arguments are passed, print usage and exit
if [[ "${#}" -eq 0 ]]; then
    usage && exit 0
fi

# if arguments contain "-h" or "--help", print usage and exit
for arg in "${@}"
do
    if [[ "${arg}" == "-h" ]] || [[ "${arg}" == "--help" ]]; then
        usage && exit 0
    fi
done

# define script options
readonly short_options=a,d,h
readonly long_options=append-only,delete-only,help

# setup getopt
options=$(getopt --options "${short_options}" --longoptions "${long_options}" -- "${@}")
eval set -- "${options}"

# setup option variables
append_only=false
delete_only=false

# process options
while :
do
    case "${1}" in
        -a | --append-only )
            append_only=true
            shift
        ;;
        -d | --delete-only )
            delete_only=true
            shift
        ;;
        --)
            shift;
            break
        ;;
        *)
            echo "Unexpected option: ${1}"
            usage && exit 1
        ;;
    esac
done

# get current script directory
script_dir="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"

# get paths to issue forms and templates
readonly issue_form_dir="${script_dir}/../ISSUE_TEMPLATE"
# readonly issue_template_dir="${script_dir}/../classic-issue-templates"
readonly meta_dir="${script_dir}/../meta-templates"

issue_forms=("${issue_form_dir}"/*".yml")
issue_forms+=("${meta_dir}/meta-form.yml")

for file in "${issue_forms[@]}"; do
    if [[ -f "${file}" ]] && [[ "${file}" != *"config.yml" ]]; then
        handle_issue_form "${file}" "${append_only}" "${delete_only}" "${@}"
    fi
done
exit 0

# main script: end ---------------------------------------------------------------------------------------------------