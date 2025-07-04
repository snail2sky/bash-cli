#!/bin/bash
# bash-cli.sh (v1.0.1)
# A robust, modular, and easy-to-use Bash Command Line Interface (CLI) framework (Bash 4.x+ required).

if [[ -z "${BASH_VERSINFO}" || "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "Error: This bundler requires Bash 4.x or higher." >&2
    exit 1
fi
# --- Global Configuration and Variables ---
declare -A _BUNDLER_PROCESSED_FILES # Tracks files already processed to avoid infinite loops and duplication.
_BUNDLER_CONTENT_QUEUE=()            # Stores file paths in the order they should be included.
_BUNDLER_CLI_RUN_LINE=""             # Stores the cli_run "$@" line from the main script.


declare -A CLI_COMMANDS       # Stores command metadata: [command_path]=function_name
declare -A CLI_COMMAND_DESCRIPTIONS # Stores command short descriptions: [command_path]=description
declare -A CLI_COMMAND_LONG_DESCRIPTIONS # Stores command long descriptions: [command_path]=long_description
declare -A CLI_COMMAND_EXAMPLES # Stores command examples: [command_path]=example
declare -A CLI_FLAGS          # Stores flag metadata: [command_path_flag_name]=value
declare -A CLI_FLAG_DESCRIPTIONS # Stores flag descriptions: [command_path_flag_name]=description
declare -A CLI_FLAG_SHORT_CHARS # Stores short flag chars: [command_path_flag_name]=short_char
declare -A CLI_FLAG_TYPES     # Stores flag types: [command_path_flag_name]=type (string/bool)
declare -A CLI_FLAG_DEFAULT_VALUES # Stores flag default values: [command_path_flag_name]=default_value
declare -A CLI_FLAG_REQUIRED  # Stores if flag is required: [command_path_flag_name]=true/false

declare -A CLI_PARSED_FLAGS   # Stores parsed flag values during runtime: [flag_name]=value
CLI_POSITIONAL_ARGS=()        # Stores positional arguments during runtime
CLI_CURRENT_COMMAND=""        # Tracks the currently executing command path
CLI_TOOL_NAME="$(basename "$0")" # The name of the main CLI script

# ANSI escape codes for coloring output
CLI_COLOR_RESET='\033[0m'
CLI_COLOR_RED='\033[0;31m'
CLI_COLOR_GREEN='\033[0;32m'
CLI_COLOR_YELLOW='\033[0;33m'
CLI_COLOR_BLUE='\033[0;34m'
CLI_COLOR_CYAN='\033[0;36m'
CLI_COLOR_BOLD='\033[1m'

# Logging functions
_bundler_log_error() { echo -e "${CLI_COLOR_RED}Error: $*${CLI_COLOR_RESET}" >&2; }
_bundler_log_success() { echo -e "${CLI_COLOR_GREEN}Success: $*${CLI_COLOR_RESET}"; }
_bundler_log_info() { echo -e "${CLI_COLOR_CYAN}Info: $*${CLI_COLOR_RESET}"; }
_bundler_log_warn() { echo -e "${CLI_COLOR_YELLOW}Warning: $*${CLI_COLOR_RESET}" >&2; }

# --- Utility Function: Get absolute path of a file ---
# This version is designed to be more robust by trying multiple resolution methods
# and explicitly checking file existence.
# Args: <path> <base_directory_for_resolution> (base_directory should be absolute)
# Output: Absolute path if file exists, otherwise empty string.
_bundler_get_abs_path() {
    local target_path="$1"
    local base_dir="$2" # This should already be an absolute physical path

    local abs_path=""

    if [[ -z "$target_path" ]]; then
        echo ""
        return 1
    fi

    # Attempt 1: If target_path is already absolute
    if [[ "$target_path" = /* ]]; then
        abs_path="$target_path"
    else # Attempt 2: Resolve relative to base_dir
        # Avoid // in path, handle /path/./file and /path/../file
        abs_path="${base_dir}/${target_path}"
        # Canonicalize the path by temporarily changing directory in a subshell
        # This resolves `.` and `..` and removes redundant slashes
        (
            cd -P "$base_dir" >/dev/null 2>&1 && \
            abs_path="$(pwd -P "$target_path" 2>/dev/null)"
        ) || abs_path="" # If cd or pwd fails, clear abs_path
    fi

    # Attempt 3: Final check for existence using simple concatenation if above failed
    if [[ -z "$abs_path" || ! -f "$abs_path" ]]; then
        # Fallback to direct concatenation if resolution methods fail, then check existence
        local simple_concat_path="${base_dir}/${target_path}"
        # Clean up potential // or /./ or /../
        simple_concat_path=$(echo "$simple_concat_path" | sed -E 's/\/\.\/|\/[^\/]+\/\.\.\/|\/\/\//g' | sed 's/\/\.$//' | sed 's/[^/]\/\.\.$//') # Simplified canonicalization
        if [[ -f "$simple_concat_path" ]]; then
            abs_path="$simple_concat_path"
        else
            echo "" # Still not found
            return 1
        fi
    fi

    # Final verification: Check if the resolved path actually points to a regular file
    if [[ -f "$abs_path" ]]; then
        echo "$abs_path"
        return 0
    else
        echo ""
        return 1
    fi
}


# --- Core Bundler Functions ---

# Helper function to extract sourced file path safely from a line.
# This is the improved logic to replace problematic regex.
# Args: <line>
# Output: sourced file path or empty string if not found.
_bundler_get_sourced_path() {
    local line="$1"
    local trimmed_line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" # Trim leading/trailing whitespace
    local path=""

    # Check for "source <path>" or ". <path>"
    # Using `case` for more robust and compatible pattern matching.
    # Prioritize 'source ' then '. '
    if [[ "$trimmed_line" == source\ * ]]; then
        path="${trimmed_line#source }"
    elif [[ "$trimmed_line" == .\ * ]]; then
        path="${trimmed_line#. }"
    else
        echo "" # Not a source line
        return 0
    fi

    # Remove quotes if present.
    # Use parameter expansion for simpler cases, sed for robustness with mixed quotes/embedded quotes.
    if [[ "$path" == \"*\" ]] || [[ "$path" == \'*\' ]]; then
        path="$(echo "$path" | sed -e "s/^['\"]//" -e "s/['\"]$//")"
    fi

    # Remove comments after path, if any.
    # Note: Bash comments are typically from '#' to end of line.
    if [[ "$path" == *"#"* ]]; then
        path="${path%%#*}" # Remove anything after #
    fi

    # Trim any remaining whitespace after quote removal or comment removal.
    path="$(echo "$path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    echo "$path"
}

# Function to recursively extract file content and queue them for bundling.
# It processes dependencies before adding itself to the content queue (depth-first).
# Args: <file_path_to_process> <current_directory_for_resolution> <is_main_script>
_bundler_extract_and_queue_content() {
    local file_path_to_process="$1"
    local current_dir="$2"
    local is_main_script="${3:-false}" # Default to false

    # Use our robust _bundler_get_abs_path instead of realpath directly
    local abs_file_path=$(_bundler_get_abs_path "$file_path_to_process" "$current_dir")
    if [[ -z "$abs_file_path" ]]; then # Check if _bundler_get_abs_path returned empty (file not found/invalid)
        _bundler_log_error "File not found or invalid during bundling: '$file_path_to_process' (resolved from '$current_dir'). Please check path, permissions, or file existence."
        return 1
    fi

    # Check if already processed to avoid infinite loops and redundant inclusion
    if [[ -v _BUNDLER_PROCESSED_FILES["$abs_file_path"] ]]; then
        # _bundler_log_info "Skipping already processed file: $abs_file_path"
        return 0 # Already processed
    fi

    # Mark as processed *before* recursively calling, to handle circular dependencies properly
    _BUNDLER_PROCESSED_FILES["$abs_file_path"]="true"
    _bundler_log_info "Processing and queuing dependencies for: $abs_file_path"

    # Important: Recursively process sourced files *first* (depth-first search)
    # This ensures that dependencies appear before the files that source them in the final bundle.
    local temp_sourced_files=() # Store sourced files in this specific file to process them.
    while IFS= read -r line || [[ -n "$line" ]]; do
        local sourced_file_raw=$(_bundler_get_sourced_path "$line")
        if [[ -n "$sourced_file_raw" ]]; then
            # Skip sourcing bash-cli.sh itself explicitly within other scripts,
            # as it will be included as the core framework at the very beginning.
            if [[ "$(basename "$sourced_file_raw")" == "bash-cli.sh" ]]; then
                 _bundler_log_warn "Skipping explicit source of 'bash-cli.sh' in '$abs_file_path': '$line'. It will be pre-pended."
                 continue
            fi
            temp_sourced_files+=("$sourced_file_raw")
        fi
    done < "$abs_file_path"

    # Now, process the collected sourced files recursively
    local source_resolution_dir="$(dirname "$abs_file_path")"
    for sourced_file in "${temp_sourced_files[@]}"; do
        local resolved_source_path=""
        # Handle $(dirname "$0") in source paths. This is a common pattern.
        if [[ "$sourced_file" == *"\$(dirname \"\$0\")"* ]]; then
            # Replace $(dirname "$0") with the absolute path of the *current file being processed*
            local temp_path_with_base="${sourced_file//\$(dirname \"\$0\")/$source_resolution_dir}"
            temp_path_with_base=$(echo "$temp_path_with_base" | sed 's/\/\//\//g') # Clean up potential double slashes
            resolved_source_path=$(_bundler_get_abs_path "$temp_path_with_base" "$source_resolution_dir") # Use our custom resolver
        else
            resolved_source_path=$(_bundler_get_abs_path "$sourced_file" "$source_resolution_dir") # Use our custom resolver
        fi

        if [[ -z "$resolved_source_path" ]]; then
            _bundler_log_error "Could not resolve source path '$sourced_file' from '$abs_file_path'. Skipping."
            continue
	fi

        # Recursively queue the sourced file. Pass its own directory for its relative sources.
        if ! _bundler_extract_and_queue_content "$resolved_source_path" "$(dirname "$resolved_source_path")"; then
            _bundler_log_error "Failed to process sourced file '$resolved_source_path'. Aborting bundle."
            return 1
        fi
    done

    # After all dependencies are processed, add the current file to the queue.
    # This ensures a topological sort (dependencies come before dependents).
    _BUNDLER_CONTENT_QUEUE+=("$abs_file_path")
    # _bundler_log_info "Added to content queue: $abs_file_path"

    return 0
}

# --- Core CLI Framework Functions ---

# Function to register a new command.
# Args: <user_command_path> <function_name> <short_description> [long_description] [example]
cli_register_command() {
    local cmd_path="$1"
    local func_name="$2"
    local short_desc="$3"
    local long_desc="${4:-}"
    local example="${5:-}"

    if [[ -z "$cmd_path" ]]; then
        cmd_path="root" # Special internal path for the root command
    fi

    if [[ -z "$func_name" || -z "$short_desc" ]]; then
        echo -e "${CLI_COLOR_RED}Error: cli_register_command requires at least command path, function name, and short description.${CLI_COLOR_RESET}" >&2
        return 1
    fi

    CLI_COMMANDS["$cmd_path"]="$func_name"
    CLI_COMMAND_DESCRIPTIONS["$cmd_path"]="$short_desc"
    CLI_COMMAND_LONG_DESCRIPTIONS["$cmd_path"]="$long_desc"
    CLI_COMMAND_EXAMPLES["$cmd_path"]="$example"
}

# Function to register a flag for a specific command or globally.
# Args: <user_command_path> <flag_name> <short_char> <default_value> <description> <type> [required]
cli_register_flag() {
    local cmd_path="$1"
    local flag_name="$2"
    local short_char="$3"
    local default_value="$4"
    local description="$5"
    local type="$6"
    local required="${7:-false}" # Default to false if not provided

    if [[ -z "$cmd_path" ]]; then
        cmd_path="root" # Special internal path for global flags
    fi

    if [[ -z "$flag_name" || -z "$description" || -z "$type" ]]; then
        echo -e "${CLI_COLOR_RED}Error: cli_register_flag requires at least command path, flag name, description, and type.${CLI_COLOR_RESET}" >&2
        return 1
    fi

    local key="${cmd_path}_${flag_name}"
    CLI_FLAGS["$key"]="$flag_name"
    CLI_FLAG_DESCRIPTIONS["$key"]="$description"
    CLI_FLAG_SHORT_CHARS["$key"]="$short_char"
    CLI_FLAG_DEFAULT_VALUES["$key"]="$default_value"
    CLI_FLAG_TYPES["$key"]="$type"
    CLI_FLAG_REQUIRED["$key"]="$required"
}

# Convenience wrapper for cli_register_flag to register global flags.
# Args: <flag_name> <short_char> <default_value> <description> <type> [required]
cli_register_global_flag() {
    cli_register_flag "root" "$@"
}

# Retrieve the parsed value of a flag for the current command context.
# Args: <flag_name>
# Returns: The flag's value or an empty string if not found/set.
cli_get_flag() {
    local flag_name="$1"
    local value="${CLI_PARSED_FLAGS["${CLI_CURRENT_COMMAND}_${flag_name}"]}"

    # Fallback to global flag if not found in current command context
    if [[ -z "$value" ]]; then
        value="${CLI_PARSED_FLAGS["root_${flag_name}"]}"
    fi
    echo "$value"
}

# Retrieve the parsed value of a specific global flag.
# Args: <flag_name>
# Returns: The global flag's value or an empty string if not found/set.
cli_get_global_flag() {
    local flag_name="$1"
    echo "${CLI_PARSED_FLAGS["root_${flag_name}"]}"
}

# Displays the help message for a given command.
# Args: [command_path]
cli_display_help() {
    local cmd_path="${1:-root}" # Default to root command help

    # If the requested path doesn't exist, fall back to root help
    if [[ ! -v CLI_COMMANDS["$cmd_path"] && "$cmd_path" != "root" ]]; then
        echo -e "${CLI_COLOR_YELLOW}Warning: Command '${cmd_path}' not found. Displaying root help instead.${CLI_COLOR_RESET}" >&2
        cmd_path="root"
    fi

    local func_name="${CLI_COMMANDS["$cmd_path"]}"
    local short_desc="${CLI_COMMAND_DESCRIPTIONS["$cmd_path"]}"
    local long_desc="${CLI_COMMAND_LONG_DESCRIPTIONS["$cmd_path"]}"
    local example="${CLI_COMMAND_EXAMPLES["$cmd_path"]}"

    echo -e "${CLI_COLOR_BOLD}USAGE:${CLI_COLOR_RESET}"
    if [[ -n "$example" ]]; then
        echo "  ${example}"
    else
        # Construct dynamic usage string for commands, showing subcommand path if applicable
        local usage_cmd_path="${cmd_path//root/}" # Remove 'root' if it's the root command
        if [[ -n "$usage_cmd_path" ]]; then
             echo "  ${CLI_TOOL_NAME} ${usage_cmd_path} [command] [flags]"
        else
            echo "  ${CLI_TOOL_NAME} [command] [flags]"
        fi
    fi
    echo ""

    if [[ -n "$short_desc" && "$cmd_path" != "root" ]]; then
        echo -e "${CLI_COLOR_BOLD}DESCRIPTION:${CLI_COLOR_RESET}"
        echo "  $short_desc"
        if [[ -n "$long_desc" ]]; then
            echo "  $long_desc"
        fi
        echo ""
    elif [[ "$cmd_path" == "root" ]]; then
        echo -e "${CLI_COLOR_BOLD}DESCRIPTION:${CLI_COLOR_RESET}"
        echo "  A powerful, modular, and easy-to-use Bash CLI framework."
        echo ""
    fi

    # Available Commands
    local sub_commands=()
    for key in "${!CLI_COMMANDS[@]}"; do
        if [[ "$key" != "root" ]]; then # 'root' is not a sub-command to itself
            if [[ "$cmd_path" == "root" ]]; then
                # Find top-level commands (e.g., "user", not "user.add")
                # Commands with dots are considered sub-commands (e.g., "user.add")
                if [[ ! "$key" =~ \. ]]; then
                    sub_commands+=("$key")
                fi
            elif [[ "$key" == "$cmd_path."* ]]; then
                # Find direct sub-commands for the current command (e.g., for "user", find "user.add", not "user.add.sub")
                local relative_path="${key#$cmd_path.}"
                if [[ ! "$relative_path" =~ \. ]]; then
                    sub_commands+=("$key")
                fi
            fi
        fi
    done

    # Sort sub-commands alphabetically
    IFS=$'\n' sub_commands=($(sort <<<"${sub_commands[*]}"))
    unset IFS

    if [[ ${#sub_commands[@]} -gt 0 ]]; then
        echo -e "${CLI_COLOR_BOLD}AVAILABLE COMMANDS:${CLI_COLOR_RESET}"
        for sub_cmd in "${sub_commands[@]}"; do
            local sub_cmd_short_desc="${CLI_COMMAND_DESCRIPTIONS["$sub_cmd"]}"
            local display_name="${sub_cmd#$cmd_path.}" # Remove parent path for display
            # If the command is a top-level command for root, ensure it's not prefixed with a dot
            if [[ "$cmd_path" == "root" ]]; then
                display_name="$sub_cmd"
            fi
            printf "  %-20s %s\n" "$display_name" "$sub_cmd_short_desc"
        done
        echo ""
    fi

    # Flags
    echo -e "${CLI_COLOR_BOLD}FLAGS:${CLI_COLOR_RESET}"
    local all_flag_keys=() # To store command_path_flag_name keys for sorting

    # Collect flags for the current command
    for key in "${!CLI_FLAGS[@]}"; do
        if [[ "$key" == "${cmd_path}_"* ]]; then
            all_flag_keys+=("$key")
        fi
    done

    # Collect global flags (if not already listed or if it's the root command help)
    for key in "${!CLI_FLAGS[@]}"; do
        if [[ "$key" == "root_"* ]]; then
            local flag_name="${key#root_}"
            local found_local_override=false
            for existing_key in "${all_flag_keys[@]}"; do
                # Check if this global flag is already overridden by a local flag with the same name
                local existing_flag_name="${existing_key##*_}"
                if [[ "$existing_flag_name" == "$flag_name" ]]; then
                    found_local_override=true
                    break
                fi
            done
            if ! $found_local_override; then
                all_flag_keys+=("$key") # Add global flag key
            fi
        fi
    done

    # Sort flags alphabetically by flag name
    IFS=$'\n' all_flag_keys=($(
        for key in "${all_flag_keys[@]}"; do
            local flag_name=""
            # Extract the actual flag name from the key (e.g., "root_verbose" -> "verbose")
            flag_name="${key##*_}"
            echo "${flag_name}___${key}" # Prefix with flag_name for sorting, then original key
        done | sort | sed 's/^.*___//' # Remove the prefix after sorting
    ))
    unset IFS

    if [[ ${#all_flag_keys[@]} -gt 0 ]]; then
        for flag_key_for_display in "${all_flag_keys[@]}"; do
            local current_flag_name=""
            local current_short_char=""
            local current_default_value=""
            local current_description=""
            local current_type=""
            local current_required=""

            # Determine the correct key for lookup based on the context (current command or root)
            local actual_flag_name_from_key="${flag_key_for_display##*_}"
            local potential_cmd_key="${cmd_path}_${actual_flag_name_from_key}"
            local potential_root_key="root_${actual_flag_name_from_key}"

            if [[ -v CLI_FLAG_DESCRIPTIONS["$potential_cmd_key"] ]]; then
                current_flag_name="${CLI_FLAGS["$potential_cmd_key"]}"
                current_short_char="${CLI_FLAG_SHORT_CHARS["$potential_cmd_key"]}"
                current_default_value="${CLI_FLAG_DEFAULT_VALUES["$potential_cmd_key"]}"
                current_description="${CLI_FLAG_DESCRIPTIONS["$potential_cmd_key"]}"
                current_type="${CLI_FLAG_TYPES["$potential_cmd_key"]}"
                current_required="${CLI_FLAG_REQUIRED["$potential_cmd_key"]}"
            elif [[ -v CLI_FLAG_DESCRIPTIONS["$potential_root_key"] ]]; then
                current_flag_name="${CLI_FLAGS["$potential_root_key"]}"
                current_short_char="${CLI_FLAG_SHORT_CHARS["$potential_root_key"]}"
                current_default_value="${CLI_FLAG_DEFAULT_VALUES["$potential_root_key"]}"
                current_description="${CLI_FLAG_DESCRIPTIONS["$potential_root_key"]}"
                current_type="${CLI_FLAG_TYPES["$potential_root_key"]}"
                current_required="${CLI_FLAG_REQUIRED["$potential_root_key"]}"
            else
                # This should ideally not happen if all_flag_keys are built correctly,
                # but as a safeguard, skip if no info is found.
                continue
            fi

            local flag_str="    "
            if [[ -n "$current_short_char" ]]; then
                flag_str+="-${current_short_char}, "
            else
                flag_str+="    " # Indent for alignment if no short char
            fi
            flag_str+="--${current_flag_name}"

            if [[ "$current_type" == "string" ]]; then
                flag_str+=" <value>"
            fi

            printf "  %-25s %s\n" "$flag_str" "$current_description"

            if [[ -n "$current_default_value" ]]; then
                if [[ "$current_type" == "bool" && "$current_default_value" == "true" ]]; then
                     printf "      ${CLI_COLOR_CYAN}(default: enabled)${CLI_COLOR_RESET}\n"
                elif [[ "$current_type" == "bool" && "$current_default_value" == "false" ]]; then
                     printf "      ${CLI_COLOR_CYAN}(default: disabled)${CLI_COLOR_RESET}\n"
                else
                    printf "      ${CLI_COLOR_CYAN}(default: %s)${CLI_COLOR_RESET}\n" "$current_default_value"
                fi
            fi
            if [[ "$current_required" == "true" ]]; then
                printf "      ${CLI_COLOR_RED}(required)${CLI_COLOR_RESET}\n"
            fi
        done
    else
        echo "  No flags available for this command."
    fi
    echo ""
}


# Internal function to parse arguments and flags.
# Args: all arguments passed to the main script
_cli_parse_args() {
    local cmd_args=("$@")
    local cmd_path_candidate="" # Stores the potential command path discovered
    local current_arg_index=0
    local is_help_requested_via_flag=false
    local has_explicit_command_arg=false # Tracks if a non-flag, non-help argument was seen as a command candidate

    # First pass: Determine command path candidate and check for --help/ -h early
    for (( i=0; i<${#cmd_args[@]}; i++ )); do
        local arg="${cmd_args[$i]}"
        if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
            is_help_requested_via_flag=true
            # If help is requested, the command path candidate is what was built so far
            # Or if it's the very first arg, then it implies root help.
            if [[ -z "$cmd_path_candidate" ]]; then
                cmd_path_candidate="root"
            fi
            break # Stop parsing, help requested
        elif [[ "$arg" == --* || "$arg" == -* ]]; then
            break # Stop at first non-help flag
        elif [[ "$arg" == "--" ]]; then
            break # Stop at argument separator
        else
            # This segment could be a command path part or a positional argument.
            # We assume it's a command path part until we can't find a matching command.
            local potential_next_cmd_path=""
            if [[ -z "$cmd_path_candidate" ]]; then
                potential_next_cmd_path="$arg"
            else
                potential_next_cmd_path="${cmd_path_candidate}.${arg}"
            fi

            # Check if this potential command path actually exists as a registered command
            # And ensure it looks like a valid command segment (not a random string)
            if [[ "$arg" =~ ^[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)*$ ]] && [[ -v CLI_COMMANDS["$potential_next_cmd_path"] ]]; then
                cmd_path_candidate="$potential_next_cmd_path"
                current_arg_index=$((i + 1)) # This argument was a command segment
                has_explicit_command_arg=true
            else
                # This argument is not part of a valid, registered command path.
                # Treat the rest as positional arguments for the command found so far (or root).
                break
            fi
        fi
    done

    # If --help or -h was found, display help for the determined command or root
    if $is_help_requested_via_flag; then
        local target_cmd_for_help="${cmd_path_candidate:-root}" # Default to root if no command candidate found
        cli_display_help "$target_cmd_for_help"
        exit 0
    fi

    # Determine the actual command path to execute
    if [[ -z "$cmd_path_candidate" ]]; then
        # No command was explicitly provided, and no help flag was seen.
        # Default to "root" command.
        CLI_CURRENT_COMMAND="root"
        current_arg_index=0 # All arguments from the beginning are positional for root
    elif [[ -v CLI_COMMANDS["$cmd_path_candidate"] ]]; then
        # A valid command was explicitly provided.
        CLI_CURRENT_COMMAND="$cmd_path_candidate"
    else
        # Command candidate found but doesn't exist. This should ideally not happen
        # if the first pass logic is robust, but as a safeguard.
        echo -e "${CLI_COLOR_RED}Error: Unknown command: '${cmd_path_candidate}'.${CLI_COLOR_RESET}" >&2
        cli_display_help "root"
        exit 1
    fi


    # Initialize parsed flags with empty strings to avoid issues
    # We do this for all potential flags for the current command context (local and global)
    local relevant_flag_keys=()
    for key in "${!CLI_FLAGS[@]}"; do
        if [[ "$key" == "${CLI_CURRENT_COMMAND}_"* ]]; then
            relevant_flag_keys+=("$key")
        elif [[ "$key" == "root_"* ]]; then
            local flag_name="${key#root_}"
            local found_local_override=false
            for local_key in "${!CLI_FLAGS[@]}"; do
                # Check if this global flag is already overridden by a local flag with the same name
                local local_flag_name="${local_key##*_}"
                if [[ "$local_flag_name" == "$flag_name" && "$local_key" == "${CLI_CURRENT_COMMAND}_${local_flag_name}" ]]; then
                    found_local_override=true
                    break
                fi
            done
            if ! $found_local_override; then
                relevant_flag_keys+=("$key")
            fi
        fi
    done

    for registered_key in "${relevant_flag_keys[@]}"; do
        local original_flag_name="${CLI_FLAGS["$registered_key"]}"
        CLI_PARSED_FLAGS["${CLI_CURRENT_COMMAND}_${original_flag_name}"]="" # Initialize with empty string
    done


    # Second pass: Parse flags and positional arguments
    local skip_flags=false
    for (( i=current_arg_index; i<${#cmd_args[@]}; i++ )); do
        local arg="${cmd_args[$i]}"

        if [[ "$arg" == "--" ]]; then
            skip_flags=true
            continue
        fi

        if $skip_flags; then
            CLI_POSITIONAL_ARGS+=("$arg")
            continue
        fi

        local parsed=false

        # Try to parse as long flag (--flag-name)
        if [[ "$arg" == --* ]]; then
            local flag_name="${arg#--}"
            local flag_value=""
            local original_flag_name="${flag_name}" # Keep original for error messages

            if [[ "$flag_name" =~ = ]]; then
                flag_value="${flag_name#*=}"
                flag_name="${flag_name%%=*}"
            fi

            local flag_key_current_cmd="${CLI_CURRENT_COMMAND}_${flag_name}"
            local flag_key_root="root_${flag_name}"

            local flag_type=""
            local flag_target_key="" # The actual key where the flag was registered

            if [[ -v CLI_FLAG_TYPES["$flag_key_current_cmd"] ]]; then
                flag_type="${CLI_FLAG_TYPES["$flag_key_current_cmd"]}"
                flag_target_key="$flag_key_current_cmd"
            elif [[ -v CLI_FLAG_TYPES["$flag_key_root"] ]]; then
                flag_type="${CLI_FLAG_TYPES["$flag_key_root"]}"
                flag_target_key="$flag_key_root"
            fi

            if [[ -z "$flag_type" ]]; then
                echo -e "${CLI_COLOR_RED}Error: Unknown flag: --${original_flag_name}${CLI_COLOR_RESET}" >&2
                cli_display_help "$CLI_CURRENT_COMMAND"
                exit 1
            fi

            if [[ "$flag_type" == "bool" ]]; then
                if [[ -n "$flag_value" && "$flag_value" != "true" && "$flag_value" != "false" ]]; then
                    echo -e "${CLI_COLOR_RED}Error: Invalid value for boolean flag --${flag_name}. Expected 'true' or 'false'.${CLI_COLOR_RESET}" >&2
                    exit 1
                fi
                CLI_PARSED_FLAGS["${CLI_CURRENT_COMMAND}_${flag_name}"]="${flag_value:-true}" # Default to true if no value provided
            else # string type
                if [[ -n "$flag_value" ]]; then
                    CLI_PARSED_FLAGS["${CLI_CURRENT_COMMAND}_${flag_name}"]="$flag_value"
                else
                    # Check next argument for value, ensuring it's not another flag
                    if (( i + 1 < ${#cmd_args[@]} )) && [[ "${cmd_args[$((i+1))]}" != --* && "${cmd_args[$((i+1))]}" != -* ]]; then
                        CLI_PARSED_FLAGS["${CLI_CURRENT_COMMAND}_${flag_name}"]="${cmd_args[$((i+1))]}"
                        i=$((i + 1)) # Consume the next argument
                    else
                        echo -e "${CLI_COLOR_RED}Error: Flag '--${flag_name}' requires a value.${CLI_COLOR_RESET}" >&2
                        cli_display_help "$CLI_CURRENT_COMMAND"
                        exit 1
                    fi
                fi
            fi
            parsed=true
        # Try to parse as short flag (-f)
        elif [[ "$arg" == -* && "$arg" != "-" ]]; then
            local short_chars="${arg#-}"
            for ((j=0; j<${#short_chars}; j++)); do
                local char="${short_chars:$j:1}"
                local found_flag_name=""
                local found_flag_type=""

                # Search current command flags
                for key in "${!CLI_FLAG_SHORT_CHARS[@]}"; do
                    if [[ "$key" == "${CLI_CURRENT_COMMAND}_"* && "${CLI_FLAG_SHORT_CHARS["$key"]}" == "$char" ]]; then
                        found_flag_name="${key#${CLI_CURRENT_COMMAND}_}"
                        found_flag_type="${CLI_FLAG_TYPES["$key"]}"
                        break
                    fi
                done
                # Search global flags if not found in current
                if [[ -z "$found_flag_name" ]]; then
                    for key in "${!CLI_FLAG_SHORT_CHARS[@]}"; do
                        if [[ "$key" == "root_"* && "${CLI_FLAG_SHORT_CHARS["$key"]}" == "$char" ]]; then
                            found_flag_name="${key#root_}"
                            found_flag_type="${CLI_FLAG_TYPES["$key"]}"
                            break
                        fi
                    done
                fi

                if [[ -z "$found_flag_name" ]]; then
                    echo -e "${CLI_COLOR_RED}Error: Unknown short flag: -${char}${CLI_COLOR_RESET}" >&2
                    cli_display_help "$CLI_CURRENT_COMMAND"
                    exit 1
                fi

                if [[ "$found_flag_type" == "bool" ]]; then
                    CLI_PARSED_FLAGS["${CLI_CURRENT_COMMAND}_${found_flag_name}"]="true"
                else # string type
                    # If it's a string flag, it must be the last short char in a group
                    if (( j + 1 < ${#short_chars} )); then
                        echo -e "${CLI_COLOR_RED}Error: String flag '-${char}' must be the last in a short flag group (e.g., -abc is ok if c is string, -acb is not).${CLI_COLOR_RESET}" >&2
                        exit 1
                    fi
                    # Check next argument for value, ensuring it's not another flag
                    if (( i + 1 < ${#cmd_args[@]} )) && [[ "${cmd_args[$((i+1))]}" != --* && "${cmd_args[$((i+1))]}" != -* ]]; then
                        CLI_PARSED_FLAGS["${CLI_CURRENT_COMMAND}_${found_flag_name}"]="${cmd_args[$((i+1))]}"
                        i=$((i + 1)) # Consume next argument
                    else
                        echo -e "${CLI_COLOR_RED}Error: Flag '-${char}' requires a value.${CLI_COLOR_RESET}" >&2
                        cli_display_help "$CLI_CURRENT_COMMAND"
                        exit 1
                    fi
                fi
            done
            parsed=true
        fi

        if ! $parsed; then
            CLI_POSITIONAL_ARGS+=("$arg")
        fi
    done
}

# Internal function to apply default flag values and validate required flags.
_cli_apply_defaults_and_validate() {
    local cmd_path="$CLI_CURRENT_COMMAND"

    # Collect all relevant flag keys (for current command and global)
    local relevant_flag_keys=()
    for key in "${!CLI_FLAGS[@]}"; do
        if [[ "$key" == "${cmd_path}_"* ]]; then
            relevant_flag_keys+=("$key")
        elif [[ "$key" == "root_"* ]]; then
            local flag_name="${key#root_}"
            local found_local_override=false
            for local_key in "${!CLI_FLAGS[@]}"; do
                # Check if this global flag is already overridden by a local flag with the same name
                local local_flag_name="${local_key##*_}"
                if [[ "$local_flag_name" == "$flag_name" && "$local_key" == "${cmd_path}_${local_flag_name}" ]]; then
                    found_local_override=true
                    break
                fi
            done
            if ! $found_local_override; then
                relevant_flag_keys+=("$key")
            fi
        fi
    done

    for registered_key in "${relevant_flag_keys[@]}"; do
        local original_flag_name="${CLI_FLAGS["$registered_key"]}"
        local full_flag_key="${CLI_CURRENT_COMMAND}_${original_flag_name}" # Key for CLI_PARSED_FLAGS

        # If flag was not parsed, set its default value
        if [[ -z "${CLI_PARSED_FLAGS["$full_flag_key"]}" ]]; then
            local default_value="${CLI_FLAG_DEFAULT_VALUES["$registered_key"]}"
            if [[ -n "$default_value" ]]; then
                CLI_PARSED_FLAGS["$full_flag_key"]="$default_value"
            fi
        fi

        # Validate required flags
        local is_required="${CLI_FLAG_REQUIRED["$registered_key"]}"
        if [[ "$is_required" == "true" ]]; then
            if [[ -z "${CLI_PARSED_FLAGS["$full_flag_key"]}" ]]; then
                echo -e "${CLI_COLOR_RED}Error: Required flag --${original_flag_name} not set for command context '${cmd_path}'.${CLI_COLOR_RESET}" >&2
                cli_display_help "$cmd_path"
                exit 1
            fi
        fi
    done
}

# Main entry point for the CLI framework.
# Args: all arguments passed to the main script (e.g., "$@")
cli_run() {
    _cli_parse_args "$@"
    _cli_apply_defaults_and_validate

    local func_to_execute="${CLI_COMMANDS["$CLI_CURRENT_COMMAND"]}"

    if [[ -z "$func_to_execute" ]]; then
        echo -e "${CLI_COLOR_RED}Error: Internal error: Command '${CLI_CURRENT_COMMAND}' function not found.${CLI_COLOR_RESET}" >&2
        cli_display_help "root"
        exit 1
    fi

    # Execute the command function with positional arguments
    "$func_to_execute" "${CLI_POSITIONAL_ARGS[@]}"
}

# --- Code Generation Tool Functions ---

# Displays help for the bash-cli.sh generator itself.
_cli_generator_display_help() {
    echo -e "${CLI_COLOR_BOLD}Usage: bash-cli.sh <command> [options]${CLI_COLOR_RESET}"
    echo ""
    echo -e "${CLI_COLOR_BOLD}DESCRIPTION:${CLI_COLOR_RESET}"
    echo "  A command-line tool for generating Bash CLI projects and commands."
    echo ""
    echo -e "${CLI_COLOR_BOLD}AVAILABLE COMMANDS:${CLI_COLOR_RESET}"
    printf "  %-20s %s\n" "init <main_script_name>" "Initializes a new Bash CLI project."
    printf "  %-20s %s\n" "add <command_path>" "Generates a new command boilerplate."
    printf "  %-25s %s\n" "bundle <main_script_name>" "The path to your main CLI script (e.g., './mycli.sh')."
    echo ""
    echo -e "${CLI_COLOR_BOLD}FLAGS:${CLI_COLOR_RESET}"
    printf "  %-25s %s\n" "    -h, --help" "Show help for generator command."
    echo ""
    echo -e "${CLI_COLOR_BOLD}COMMAND SPECIFIC OPTIONS:${CLI_COLOR_RESET}"
    echo "  init options:"
    printf "    %-25s %s\n" "--commands-dir <dir>" "Specify the directory for command files (default: commands)."
    echo ""
    echo "  add options:"
    printf "    %-25s %s\n" "--commands-dir <dir>" "Specify the directory for command files (default: commands)."
    printf "    %-25s %s\n" "--main-script <path>" "Specify the main CLI script to update (default: auto-detected)."
    echo ""
    echo "  bundle options:"
    printf "    %-25s %s\n" "--output <file>" "Specify the output bundled file name (default: <main_script_name>-bundled.sh)."
    printf "    %-25s %s\n" "--keep-shebang" "Keep the shebang (#!/bin/bash) from the main script in the bundled output."
    printf "    %-25s %s\n" "-h, --help" "Show this help message."
    echo ""
}

# Main bundling function.
# Args: <main_script_name> [--output <file>] [--keep-shebang]
_cli_generator_bundle() {
    local main_script_name="$1" # Positional argument 1 is the main script name
    local output_file=""
    local keep_shebang="false"

    # Parse arguments for bundler command
    # Use shift to consume main_script_name first
    shift # Consume the main_script_name from "$@"
    while (( "$#" )); do
        case "$1" in
            --output)
                if [[ -n "$2" ]]; then output_file="$2"; shift 2;  fi
                ;;
            --keep-shebang)
                keep_shebang="true"; shift
                ;;
            -h|--help)
                _bundler_display_help_message; return 0
                ;;
            -*) # Unknown flag for bundler command
                _bundler_log_error "Unknown flag for bundler: $1"; return 1
                ;;
            *) # Positional argument (should not happen if main_script_name is handled first)
                _bundler_log_error "Unexpected argument for bundler: $1"; return 1
                ;;
        esac
    done

    if [[ -z "$main_script_name" ]]; then
        _bundler_log_error "Bundler requires exactly one argument: <main_script_name>."
        _bundler_display_help_message
        return 1
    fi


    if [[ "$main_script_name" == "-h|--help" ]]; then
        _bundler_display_help_message
        return 0
    fi

    if [[ ! -f "$main_script_name" ]]; then
        _bundler_log_error "The $main_script_name not exist."
        _bundler_display_help_message
        return 1
    fi

    # Resolve the main script path relative to the current working directory.
    # For the main script, we will try to resolve it directly.
    local current_working_dir="$(pwd -P 2>/dev/null)" # Get the physical current working directory, suppress errors
    if [[ -z "$current_working_dir" ]]; then
        _bundler_log_error "Could not determine current working directory. Please ensure read/execute permissions."
        return 1
    fi

    local main_script_abs_path=""
    # First, try to resolve mycli.sh relative to the current directory directly
    if [[ -f "${current_working_dir}/${main_script_name}" ]]; then
        main_script_abs_path=$(_bundler_get_abs_path "${current_working_dir}/${main_script_name}" "/") # Pass root as base dir
    fi

    # Fallback if direct resolution failed (e.g. if mycli.sh is a symlink or complex path)
    if [[ -z "$main_script_abs_path" ]]; then
        main_script_abs_path=$(_bundler_get_abs_path "$main_script_name" "$current_working_dir")
    fi

    if [[ -z "$main_script_abs_path" ]]; then
        _bundler_log_error "Main script not found: '$main_script_name' (resolved to empty path). Please ensure the file exists and has read/execute permissions, or try using an absolute path for it."
        return 1
    fi


    if [[ -z "$output_file" ]]; then
        output_file="${main_script_name%.sh}-bundled.sh" # Default output file
    fi

    # Reset global bundler variables for each bundle operation
    _BUNDLER_PROCESSED_FILES=()
    _BUNDLER_CONTENT_QUEUE=()
    _BUNDLER_CLI_RUN_LINE=""

    _bundler_log_info "Starting bundling from '${main_script_name}' to '${output_file}'..."

    # Determine the absolute path to bash-cli.sh
    # We need to find bash-cli.sh relative to where this bundler script is located.
    # Use $BASH_SOURCE[0] to get the path to the currently executing script.
    local bundler_script_path="${BASH_SOURCE[0]}"
    local bundler_script_dir="$(dirname "$(_bundler_get_abs_path "$bundler_script_path" "$current_working_dir")")" # Get absolute physical directory of this bundler script
    if [[ -z "$bundler_script_dir" ]]; then
        _bundler_log_error "Could not determine bundler script's directory. Cannot locate 'bash-cli.sh'."
        return 1
    fi

    local bash_cli_path=$(_bundler_get_abs_path "bash-cli.sh" "$bundler_script_dir") # Try to find bash-cli.sh in bundler's dir
    if [[ -z "$bash_cli_path" ]]; then
        _bundler_log_error "Could not find 'bash-cli.sh'. Please ensure it's in the same directory as the bundler ('$bundler_script_dir'), or provide its absolute path within the bundler logic."
        return 1
    fi


    # --- Step 1: Write initial shebang and header ---
    exec 3>"$output_file" || { _bundler_log_error "Could not open output file '$output_file' for writing."; return 1; }

    if [[ "$keep_shebang" == "true" ]]; then
        local main_shebang_line=""
        # Read the actual shebang from the main script
        if IFS= read -r first_line < "$main_script_abs_path"; then
            if [[ "$first_line" =~ ^#\!.* ]]; then # Be more general with shebang regex
                main_shebang_line="$first_line"
            fi
        fi
        echo "${main_shebang_line:-#!/bin/bash}" >&3 # Use main shebang or default
    else
        echo "#!/bin/bash" >&3
        echo "# Generated by bash-cli.sh bundler. Version $(date +%Y%m%d%H%M%S)" >&3
    fi
    echo "" >&3 # Add a newline after shebang/header

    # --- Step 2: Include core bash-cli.sh framework functions ---
    # This ensures fundamental functions like cli_register_command are available early.
    _bundler_log_info "Including core bash-cli.sh framework definitions from '$bash_cli_path'..."
    echo "# --- Core bash-cli.sh Framework Definitions ---" >&3
    local in_framework_section=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Start at "Global Configuration" and stop before "Code Generation Tool Functions"
        if [[ "$line" =~ ^#\ ---[[:space:]]Global[[:space:]]Configuration[[:space:]]and[[:space:]]Variables[[:space:]]--- ]]; then
            in_framework_section=true
        fi
        if [[ "$line" =~ ^#\ ---[[:space:]]Code[[:space:]]Generation[[:space:]]Tool[[:space:]]Functions[[:space:]]--- ]]; then
            in_framework_section=false
            break # Stop reading, we've passed the core framework
        fi

        if $in_framework_section; then
            # Do NOT include the initial shebang of bash-cli.sh itself
            if [[ ! "$line" =~ ^#\!.* ]]; then # General shebang check
                echo "$line" >&3
            fi
        fi
    done < "$bash_cli_path"
    echo "" >&3 # Add a newline after framework content


    # --- Step 3: Recursively queue the main script and its sources ---
    # This populates _BUNDLER_CONTENT_QUEUE with files in dependency order.
    _bundler_log_info "Scanning main script and its dependencies..."
    local main_script_dir="$(dirname "$main_script_abs_path")"
    if ! _bundler_extract_and_queue_content "$main_script_abs_path" "$main_script_dir" "true"; then
        _bundler_log_error "Bundling failed during dependency scanning."
        exec 3>&- # Close file descriptor
        return 1
    fi

    # _bundler_log_info "Bundling queue (order of inclusion):"
    # for f in "${_BUNDLER_CONTENT_QUEUE[@]}"; do
    #     _bundler_log_info "  - $(basename "$f")"
    # done


    # --- Step 4: Write content of all queued files to the output file ---
    # Loop through the topologically sorted queue
    for file_to_bundle in "${_BUNDLER_CONTENT_QUEUE[@]}"; do
        echo -e "\n# --- Content from: $(basename "$file_to_bundle") (${file_to_bundle}) ---" >&3

        local current_file_is_main_script=false
        if [[ "$file_to_bundle" == "$main_script_abs_path" ]]; then
            current_file_is_main_script=true
        fi

        # Read each file and filter out shebangs, source lines, and the final cli_run from the main script.
        while IFS= read -r line || [[ -n "$line" ]]; do
            # 1. Skip shebangs in all files
            if [[ "$line" =~ ^#\!.* ]]; then
                continue
            fi
            # 2. Skip source/dot commands as content is already bundled
            local temp_sourced_path=$(_bundler_get_sourced_path "$line")
            if [[ -n "$temp_sourced_path" ]]; then
                continue
            fi

            # 3. Capture the cli_run "$@" line from the main script only, and defer its writing.
            if $current_file_is_main_script && [[ "$line" =~ ^[[:space:]]*cli_run[[:space:]]+\"\$@\"[[:space:]]*$ ]]; then
                _BUNDLER_CLI_RUN_LINE="$line"
                continue # Do not write it yet
            fi
            echo "$line" >&3
        done < "$file_to_bundle"
    done

    # --- Step 5: Finally, append the cli_run "$@" line if found in the main script ---
    if [[ -n "$_BUNDLER_CLI_RUN_LINE" ]]; then
        echo -e "\n# --- Main CLI Execution ---" >&3
        echo "$_BUNDLER_CLI_RUN_LINE" >&3
    else
        _bundler_log_warn "No 'cli_run \"\$@\"' line found in the main script '$main_script_name'. The bundled script might not execute as expected."
        echo -e "\n# Warning: No 'cli_run \"\$@\"' line found in the original main script. Add it manually if needed." >&3
    fi

    exec 3>&- # Close output file descriptor
    chmod +x "$output_file" # Make the bundled script executable

    _bundler_log_success "Bundling complete: '${output_file}'"
    return 0
}

# --- Help Message for the Bundler ---
_bundler_display_help_message() {
    echo -e "${CLI_COLOR_BOLD}Usage: $(basename "$0") <main_script_name> [options]${CLI_COLOR_RESET}"
    echo ""
    echo -e "${CLI_COLOR_BOLD}DESCRIPTION:${CLI_COLOR_RESET}"
    echo "  Bundles a Bash CLI main script and all its 'source'd dependencies into a single, standalone executable."
    echo ""
    echo -e "${CLI_COLOR_BOLD}ARGUMENTS:${CLI_COLOR_RESET}"
    printf "  %-25s %s\n" "<main_script_name>" "The path to your main CLI script (e.g., './mycli.sh')."
    echo ""
    echo -e "${CLI_COLOR_BOLD}OPTIONS:${CLI_COLOR_RESET}"
    printf "  %-25s %s\n" "--output <file>" "Specify the output bundled file name (default: <main_script_name>-bundled.sh)."
    printf "  %-25s %s\n" "--keep-shebang" "Keep the shebang (#!/bin/bash) from the main script in the bundled output."
    printf "  %-25s %s\n" "-h, --help" "Show this help message."
    echo ""
    echo -e "${CLI_COLOR_BOLD}Example:${CLI_COLOR_RESET}"
    echo "  $(basename "$0") mycli.sh --output mycli-bundle.sh"
    echo "  $(basename "$0") main.sh --keep-shebang"
    echo ""
}

# Init command for bash-cli.sh itself.
# Args: <main_script_name> [--commands-dir <dir>]
_cli_generator_init() {
    local main_script_name=""
    local commands_dir="commands"

    local parsed_flags_init=() # For parsing flags specific to init
    local parsed_positional_init=() # For parsing positional args specific to init

    # Parse arguments for init command
    while (( "$#" )); do
        case "$1" in
            --commands-dir)
                if [[ "$2" ]]; then
                    commands_dir="$2"
                    shift 2
                else
                    echo -e "${CLI_COLOR_RED}Error: --commands-dir requires an argument.${CLI_COLOR_RESET}" >&2
                    exit 1
                fi
                ;;
            -h|--help)
                _cli_generator_display_help
                exit 0
                ;;
            -*) # Unknown flag for init command
                echo -e "${CLI_COLOR_RED}Error: Unknown flag for 'init' command: $1${CLI_COLOR_RESET}" >&2
                exit 1
                ;;
            *) # Positional argument
                parsed_positional_init+=("$1")
                shift
                ;;
        esac
    done

    if [[ "${#parsed_positional_init[@]}" -gt 1 ]]; then
        echo -e "${CLI_COLOR_RED}Error: Too many positional arguments for 'init' command. Expected: <main_script_name>${CLI_COLOR_RESET}" >&2
        _cli_generator_display_help
        exit 1
    fi
    main_script_name="${parsed_positional_init[0]}"

    if [[ -z "$main_script_name" ]]; then
        echo -e "${CLI_COLOR_RED}Error: 'init' command requires <main_script_name>.${CLI_COLOR_RESET}" >&2
        _cli_generator_display_help
        exit 1
    fi

    mkdir -p "$commands_dir"

    # Create main CLI script
    cat << EOF > "$main_script_name"
#!/bin/bash
# Main CLI script for ${main_script_name}

# Ensure Bash 4.x+ for associative arrays
if [[ -z "\${BASH_VERSINFO}" || "\${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "Error: This CLI requires Bash 4.x or higher." >&2
    exit 1
fi

# Include the bash-cli.sh framework
source "\$(dirname "\$0")/bash-cli.sh"

# Register global flags (e.g., verbose)
cli_register_global_flag \\
    "verbose" \\
    "v" \\
    "false" \\
    "Enable verbose output." \\
    "bool" \\
    "false"

# Source command files (root command should be sourced first for default behavior)
source "\$(dirname "\$0")/${commands_dir}/root.sh"

# !!! IMPORTANT: Source your additional command files here !!!
# Example: source "\$(dirname "\$0")/${commands_dir}/user.sh"
# Example: source "\$(dirname "\$0")/${commands_dir}/user.add.sh" # New style for sub-commands


# Run the CLI
cli_run "\$@"
EOF
    chmod +x "$main_script_name"
    echo -e "${CLI_COLOR_GREEN}Created main CLI script: ${main_script_name}${CLI_COLOR_RESET}"

    # Create root command file
    cat << EOF > "${commands_dir}/root.sh"
#!/bin/bash

# Root command function, executed when no specific command is provided.
cli_root_func() {
    # If no command is provided, or help is requested without a specific target,
    # this function will be called.
    # The framework handles positional arguments being passed here if they are not
    # flags or command names.
    if [[ "\${#CLI_POSITIONAL_ARGS[@]}" -gt 0 ]]; then
        echo -e "${CLI_COLOR_YELLOW}Warning: Unexpected positional arguments for root command: \${CLI_POSITIONAL_ARGS[@]}${CLI_COLOR_RESET}" >&2
    fi
    cli_display_help "root"
}

# Register the root command.
# An empty string "" for command path indicates the root command.
cli_register_command \\
    "" \\
    "cli_root_func" \\
    "Display help information." \\
    "This is the default command, displaying overall help when no command is specified." \\
    "\${CLI_TOOL_NAME} [command] [flags]"
EOF
    echo -e "${CLI_COLOR_GREEN}Created root command: ${commands_dir}/root.sh${CLI_COLOR_RESET}"
}

# Add command for bash-cli.sh itself.
# Args: <command_path> [--commands-dir <dir>] [--main-script <script_path>]
_cli_generator_add() {
    local command_path=""
    local commands_dir="commands"
    local main_script_path=""

    local parsed_flags_add=()
    local parsed_positional_add=()

    # Parse arguments for add command
    while (( "$#" )); do
        case "$1" in
            --commands-dir)
                if [[ "$2" ]]; then
                    commands_dir="$2"
                    shift 2
                else
                    echo -e "${CLI_COLOR_RED}Error: --commands-dir requires an argument.${CLI_COLOR_RESET}" >&2
                    exit 1
                fi
                ;;
            --main-script)
                if [[ "$2" ]]; then
                    main_script_path="$2"
                    shift 2
                else
                    echo -e "${CLI_COLOR_RED}Error: --main-script requires an argument.${CLI_COLOR_RESET}" >&2
                    exit 1
                fi
                ;;
            -h|--help)
                _cli_generator_display_help
                exit 0
                ;;
            -*) # Unknown flag for add command
                echo -e "${CLI_COLOR_RED}Error: Unknown flag for 'add' command: $1${CLI_COLOR_RESET}" >&2
                exit 1
                ;;
            *) # Positional argument
                parsed_positional_add+=("$1")
                shift
                ;;
        esac
    done

    if [[ "${#parsed_positional_add[@]}" -gt 1 ]]; then
        echo -e "${CLI_COLOR_RED}Error: Too many positional arguments for 'add' command. Expected: <command_path>${CLI_COLOR_RESET}" >&2
        _cli_generator_display_help
        exit 1
    fi
    command_path="${parsed_positional_add[0]}"

    if [[ -z "$command_path" ]]; then
        echo -e "${CLI_COLOR_RED}Error: 'add' command requires <command_path>.${CLI_COLOR_RESET}" >&2
        _cli_generator_display_help
        exit 1
    fi

    # Auto-detect main_script_path if not provided
    if [[ -z "$main_script_path" ]]; then
        local candidate_scripts=()
        for script in *.sh; do
            if [[ -f "$script" ]] && grep -q "cli_run \"\$@\"" "$script" 2>/dev/null; then
                candidate_scripts+=("$script")
            fi
        done

        if [[ "${#candidate_scripts[@]}" -eq 1 ]]; then
            main_script_path="${candidate_scripts[0]}"
            echo -e "${CLI_COLOR_GREEN}Auto-detected main script: ${main_script_path}${CLI_COLOR_RESET}"
        elif [[ "${#candidate_scripts[@]}" -gt 1 ]]; then
            echo -e "${CLI_COLOR_YELLOW}Warning: Multiple potential main scripts found:${CLI_COLOR_RESET}" >&2
            for s in "${candidate_scripts[@]}"; do echo "  - $s" >&2; done
            echo -e "${CLI_COLOR_YELLOW}Please specify the correct main script using --main-script <path>. Skipping main script update.${CLI_COLOR_RESET}" >&2
            main_script_path="" # Prevent update
        else
            echo -e "${CLI_COLOR_YELLOW}Warning: No main CLI script containing 'cli_run \"\$@\"' found in current directory. Skipping main script update.${CLI_COLOR_RESET}" >&2
            main_script_path="" # Prevent update
        fi
    fi

    # For user.add, the file will be commands/user.add.sh, no subdirectories
    local command_file="${commands_dir}/${command_path}.sh"
    mkdir -p "$(dirname "$command_file")" # Ensures 'commands/' exists

    local func_name="cli_${command_path//./_}_func" # Replace dots with underscores for function name
    local example_placeholder="\${CLI_TOOL_NAME} ${command_path}"

    cat << EOF > "$command_file"
#!/bin/bash

# Function for the '${command_path}' command.
${func_name}() {
    echo "Executing command: ${command_path}"
    echo "Positional arguments: \$@"

    # Example of accessing a global flag
    # local verbose_global=\$(cli_get_global_flag "verbose")
    # if [[ "\$verbose_global" == "true" ]]; then
    #     echo "Verbose output enabled."
    # fi
}

# Register the '${command_path}' command.
cli_register_command \\
    "${command_path}" \\
    "${func_name}" \\
    "A short description for ${command_path}." \\
    "A longer description for the ${command_path} command." \\
    "${example_placeholder}"

# Example of registering a local flag for '${command_path}'
# cli_register_flag \\
#     "${command_path}" \\
#     "example-flag" \\
#     "e" \\
#     "default-value" \\
#     "An example string flag." \\
#     "string" \\
#     "false"
EOF
    echo -e "${CLI_COLOR_GREEN}Generated command file: ${command_file}${CLI_COLOR_RESET}"

    if [[ -n "$main_script_path" ]]; then
        local relative_path_from_main="$(realpath --relative-to="$(dirname "$main_script_path")" "$command_file")"
        local source_line="source \"\$(dirname \"\$0\")/${relative_path_from_main}\""
        local source_marker="# Example: source \"\$(dirname \"\$0\")/${commands_dir}/user.add.sh\" # New style for sub-commands"

        # Check if the source line exists, ignoring lines that are comments
        # Using awk to check for the line, and if it's not present or is commented out, insert it.
        # This awk specifically checks for the exact source line, not just a pattern.
        local should_insert=true
        if awk -v s_line_to_check="$source_line" '
            /^[^#]*source "/ && index($0, s_line_to_check) { found_uncommented = 1; exit }
            END { exit !found_uncommented }
        ' "$main_script_path"; then
            should_insert=false
        fi

        if $should_insert; then
            awk -v source_line="$source_line" -v source_marker_regex="^# Example: source.*New style for sub-commands$" '
                { print }
                $0 ~ source_marker_regex && !inserted {
                    print source_line;
                    inserted=1;
                }
            ' "$main_script_path" > "${main_script_path}.tmp" && \
            mv "${main_script_path}.tmp" "$main_script_path" && \
            chmod +x "$main_script_path" # Ensure execute permission is restored

            echo -e "${CLI_COLOR_GREEN}Added source line to ${main_script_path}: ${source_line}${CLI_COLOR_RESET}"
        else
            echo -e "${CLI_COLOR_YELLOW}Source line already exists in ${main_script_path}. Skipping.${CLI_COLOR_RESET}"
        fi
    fi
}

# --- Main Logic for bash-cli.sh itself ---

# If bash-cli.sh is executed directly, it acts as the code generator.
if [[ "$(basename "$0")" == "bash-cli.sh" ]]; then
    if [[ "$#" -eq 0 ]]; then
        _cli_generator_display_help
        exit 0
    fi

    command="$1"
    shift

    # Check for help flag for the generator itself
    if [[ "$command" == "-h" || "$command" == "--help" ]]; then
        _cli_generator_display_help
        exit 0
    fi

    case "$command" in
        init)
            _cli_generator_init "$@"
            ;;
        add)
            _cli_generator_add "$@"
            ;;
        bundle)
            _cli_generator_bundle "$@"
	    ;;
        *)
            echo -e "${CLI_COLOR_RED}Error: Unknown generator command: '$command'${CLI_COLOR_RESET}" >&2
            echo "Use 'bash-cli.sh init' or 'bash-cli.sh add'."
            echo "For general help: 'bash-cli.sh --help'"
            exit 1
            ;;
    esac
    exit 0
fi

# --- Framework Initialization for Sourced Context ---

# Register the global --help flag
# This must be registered early, before cli_run is called in the main script.
cli_register_global_flag \
    "help" \
    "h" \
    "false" \
    "Show help for command." \
    "bool" \
    "false"

# If this script is sourced, the framework functions are available for the main CLI script.
# No further action needed here, as cli_run will be called by the main script.

