#! /bin/bash
# --------------------------------------------------------------------------------------------------------------------
# [L483] replace-default-assignees.sh
#        Replaces the "assignees" field's entries of a GitHub issue template with the specified assignees.
#        Assignees are inserted in the same order they are passed as arguments.
#        It distinguishes between GitHub "issue form" .yml files, and "classic" GitHub issue template .md files.
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
#   Finds the index of the "assignees" field in a GitHub "issue form" .yml file, or a "classic" GitHub issue template .md file.
# Arguments:
#   @param file: the path to the file to be processed
#   @param is_issue_form: if "true", it expects a GitHub "issue form" .yml file, otherwise a "classic" GitHub issue template .md file
# Returns:
#   @return: the index of the line via echo
find_assignees_start() {
    # extract arguments
    local -r file="${1}"
    local -r is_issue_form="${2}"
    
    # setup regex patterns
    local assignees_field_start
    if [[ "${is_issue_form}" == true ]]; then
        assignees_field_start="^assignees:\s*$"
    else
        assignees_field_start="^assignees:((\s*)|(\s+.*))$"
    fi
    
    # find the index of the line marking the start of the "assignees" field's entries
    local -r start_line=$(grep -n -m 1 -P "${assignees_field_start}" "${file}" | cut -d: -f1)
    
    # use echo's output as a return value substitute
    echo "${start_line}"
}

# Function:
#   count_assignees_yml
# Description:
#   Counts the number of entries in the "assignees" field of a GitHub "issue form" .yml file.
# Arguments:
#   @param file: the path to the file to be processed
#   @param start_line: the index of the line beginning the "assignees" field
# Returns:
#   @return: the number of entries via echo
count_assignees_yml() {
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
#   remove_assignees_yml
# Description:
#   Removes the entries of the "assignees" field of a GitHub "issue form" .yml file.
# Arguments:
#   @param file: the path to the file to be processed
#   @param start_line: the index of the line beginning the "assignees" field
#   @param number_of_assignees: the number of entries in the "assignees" field
# Returns:
#   Nothing
remove_assignees_yml() {
    # extract arguments
    local -r file="${1}"
    local -r start_line="${2}"
    local -r number_of_assignees="${3}"
    
    # create utility variable
    local -r sed_start_line=$((start_line+1))
    
    # delete old assignees from file, if there are any
    if [[ "${number_of_assignees}" -gt 0 ]]; then
        local -r end_line=$((start_line+number_of_assignees))
        sed -i "${sed_start_line},${end_line}d" "${file}"
    fi
}

# Function:
#   remove_assignees_md
# Description:
#   Removes the entries of the "assignees" field of a "classic" GitHub issue template .md file.
# Arguments:
#   @param file: the path to the file to be processed
#   @param line_index: the index of the line of the "assignees" field
# Returns:
#   Nothing
remove_assignees_md() {
    # extract arguments
    local -r file="${1}"
    local -r line_index="${2}"
    
    # create empty assignees field string
    local -r empty_assignees="assignees: "
    
    # delete old assignees from file
    sed -i "${line_index}s/.*/${empty_assignees}/" "${file}"
}

# Function:
#   append_assignees_yml
# Description:
#   Appends a list of entries to the "assignees" field of a GitHub "issue form" .yml file.
# Arguments:
#   @param file: the path to the file to be processed
#   @param start_line: the index of the line beginning the "assignees" field
#   @param assignees: the list of assignees to be appended
# Returns:
#   Nothing
append_assignees_yml() {
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
    sed -i "${start_line}a\\${new_assignees}" "${file}"
}

# Function:
#   append_assignees_md
# Description:
#   Appends a list of entries to the "assignees" field of a "classic" GitHub issue template .md file.
# Arguments:
#   @param file: the path to the file to be processed
#   @param line_index: the index of the line of the "assignees" field
#   @param assignees: the list of assignees to be appended
# Returns:
#   Nothing
append_assignees_md() {
    # extract arguments
    local -r file="${1}"
    local -r line_index="${2}"
    local -r assignees=("${@:3}")
    
    # get old assignees line
    local -r old_assignees_line=$(sed -n "${line_index}p" "${file}")
    
    
    # if ending on space, then no space needed
    # if ending on entry, comma needed
    
    # gracefully prepare the start of the new assisgnees string for a seamless append
    local new_assignees=""
    local match
    match=$(grep -m 1 -P "^assignees:\s+[a-zA-Z0-9].*$" "${file}" || true)
    # add a ", " if the old assignees line has at least one entry
    if [[ -n "${match}" ]]; then
        new_assignees+=", "
    else
        match=$(grep -m 1 -P "^assignees:\s+$" "${file}" || true)
        # add a " " if the old assignees line is empty and does not end on a space
        if [[ -z "${match}" ]]; then
            new_assignees+=" "
        fi
    fi
    
    # create new assignees entries
    for assignee in "${assignees[@]}"
    do
        new_assignees+="${assignee}, "
    done
    
    # remove trailing comma ", "
    new_assignees=${new_assignees::-2}
    
    # append new assignees
    sed -i "${line_index}s/${old_assignees_line}/${old_assignees_line}${new_assignees}/" "${file}"
}

# Function:
#   handle_file
# Description:
#   Replaces the "assignees" field's entries of a GitHub issue template with the specified assignees.
#   It distinguishes between GitHub "issue form" .yml files, and "classic" GitHub issue template .md files.
#   The file is modified in-place.
#   If both the "append_only" and "delete_only" arguments are "true", the file remains unchanged.
# Arguments:
#   @param file: the path to the file to be processed
#   @param append_only: if "true", no assignees are deleted
#   @param delete_only: if "true", no assignees are appended
#   @param is_issue_form: if "true", it expects a GitHub "issue form" .yml file, otherwise a "classic" GitHub issue template .md file
#   @param assignees: the list of assignees to be appended
# Returns:
#   Nothing
handle_file() {
    # file append_only delete_only assignees
    # extract arguments
    local -r file="${1}"
    local -r append_only="${2}"
    local -r delete_only="${3}"
    local -r is_issue_form="${4}"
    local -r assignees=("${@:5}")
    
    # get information about assignees the file lists
    local -r start_line=$(find_assignees_start "${file}" "${is_issue_form}")
    
    # treat the file as a GitHub "issue form" .yml file
    if [[ "${is_issue_form}" == true ]]; then
        # get the number of assignees the file lists
        local number_of_assignees
        number_of_assignees=$(count_assignees_yml "${file}" "${start_line}")
        
        # conditionally remove assignees
        if [[ "${append_only}" == false ]]; then
            remove_assignees_yml "${file}" "${start_line}" "${number_of_assignees}"
            number_of_assignees=0
        fi
        
        # conditionally append assignees
        if [[ "${delete_only}" == false ]]; then
            local -r append_line=$((start_line+number_of_assignees))
            append_assignees_yml "${file}" "${append_line}" "${assignees[@]}"
        fi
        # treat the file as a "classic" GitHub issue template .md file
    else
        # conditionally remove assignees
        if [[ "${append_only}" == false ]]; then
            remove_assignees_md "${file}" "${start_line}"
        fi
        
        # conditionally append assignees
        if [[ "${delete_only}" == false ]]; then
            append_assignees_md "${file}" "${start_line}" "${assignees[@]}"
        fi
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
    cat << EOF

    Usage: ${0} [-a|--append-only] [-d|--delete-only] [assignees...]

    Description:
    Replaces the "assignees" field's entries of a GitHub issue template with the specified assignees.
    Assignees are inserted in the same order they are passed as arguments.
    It distinguishes between GitHub "issue form" .yml files, and "classic" GitHub issue template .md files.
    The file is modified in-place.

    Options:
        -a | --append-only      no assignees are deleted
        -d | --delete-only      no assignees are appended
        -h | --help             print this usage information, do nothing else

    Arguments:
        assignees: the list of assignees to be appended

    Exit status:
        0: if the script was executed successfully
        1: if an unexpected option was passed

    Caveats:
        1. If both the "append-only" and "delete-only" options are set, the file remains unchanged.
        2. If no arguments are passed, the script prints this usage information.
           To clear the "assignees" field, pass the "delete-only" option without any assignees.
        3. Currently, the script makes specific and static assumptions about the file locations.
           The meta templates must be inside the ".github/meta-templates" directory.
           All other GitHub "issue form" .yml files must be inside the ".github/ISSUE_TEMPLATE" directory.
           All other "classic" GitHub issue template .md files must be inside the ".github/classic-issue-templates" directory.
        4. The script expects that the provided files are correct.
           It does not make any effort to validate the files and may fail if the files are malformed.
        5. Currently, the script expects that the provided assignees are valid GitHub usernames.
           It does not make any effort to validate the assignees and just inserts them.
        6. Currently, the script expects that the provided assignees are unique, even when only appending assignees.
           It does not make any effort to create a duplicate-free list of assignees.
        7. Currently, all indentations are hard-coded as 2 spaces.
        8. The script is not the most efficient solution. But it is a working solution.
           It is expected that the script is only run once during the setup of a repository and sparingly afterwards.

        Caveats starting with "Currently" may be addressed in future versions if requested.
EOF
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
readonly issue_template_dir="${script_dir}/../classic-issue-templates"
readonly meta_dir="${script_dir}/../meta-templates"

issue_forms=("${issue_form_dir}"/*".yml")
issue_forms+=("${meta_dir}/meta-form.yml")

for file in "${issue_forms[@]}"; do
    if [[ -f "${file}" ]] && [[ "${file}" != *"config.yml" ]]; then
        handle_file "${file}" "${append_only}" "${delete_only}" true "${@}"
    fi
done

classic_issue_templates=("${issue_template_dir}"/*".md")
classic_issue_templates+=("${meta_dir}/meta-template.md")

for file in "${classic_issue_templates[@]}"; do
    if [[ -f "${file}" ]]; then
        handle_file "${file}" "${append_only}" "${delete_only}" false "${@}"
    fi
done
exit 0

# main script: end ---------------------------------------------------------------------------------------------------