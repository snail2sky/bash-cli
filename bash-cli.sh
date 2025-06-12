#!/bin/bash

# ==============================================================================
# Bash CLI Framework
# Version: 0.2.2 (Fix: Root flag parsing and root command execution robustness)
# Author: Gemini
# Description: A robust and modular Bash command-line framework.
# Designed for Bash 4.x+ (using associative arrays).
# Supports dot-separated command paths (e.g., "serve.start").
# Site: https://github.com/snail2sky/bash-cli
# ==============================================================================

# ==============================================================================
# Global Data Structures (Associative Arrays - Bash 4.x+ required)
# Internal command paths are SPACE-separated (e.g., "serve start")
# ==============================================================================
declare -A CLI_COMMANDS_MAP           # Maps internal full command path to function name: "serve" -> "cli_serve_func", "serve start" -> "cli_serve_start_func"
declare -A CLI_COMMAND_DESCRIPTIONS   # Stores short descriptions for commands
declare -A CLI_COMMAND_LONG_DESCRIPTIONS # Stores long descriptions for commands
declare -A CLI_COMMAND_EXAMPLES       # Stores example usage for commands

declare -A CLI_FLAGS_DEFINITIONS      # Stores flag definitions per command: "root" -> "flag1:s:def:desc:type:req|flag2:..."
                                      # Format: "flag_name:short_char:default_value:description:type:required"
                                      # Type: string, bool
                                      # Required: true, false

declare -A CLI_SHORT_FLAG_TO_LONG     # Maps short flag char to long flag name globally: "p" -> "port"
declare -A CLI_PARSED_FLAGS           # Stores parsed flag values for current execution: "port" -> "8080"
declare -A CLI_GLOBAL_FLAGS_MAP       # Explicitly stores which flags are global: "verbose" -> "true", "config" -> "true"

# ==============================================================================
# Core Framework Variables
# ==============================================================================
CLI_TOOL_NAME=$(basename "$0") # The name of the script itself

# ==============================================================================
# Internal Helper Functions
# ==============================================================================

# __cli_normalize_command_path: Converts user-facing dot-separated path to internal space-separated path.
# Adds "root" prefix if it's a top-level command for internal consistency.
# Usage: __cli_normalize_command_path "serve.start"
# Returns: "root serve start"
# Usage: __cli_normalize_command_path "root"
# Returns: "root"
# Usage: __cli_normalize_command_path "" (for top-level root command)
# Returns: "root"
__cli_normalize_command_path() {
    local user_path="$1"
    local internal_path=""

    if [[ -z "$user_path" || "$user_path" == "root" ]]; then # Handle empty string for root and explicit "root"
        echo "root"
        return 0
    fi

    # Replace dots with spaces
    internal_path="${user_path//./ }"

    # If it's not already prefixed with "root", add it
    if [[ "$internal_path" != "root "* ]]; then
        internal_path="root ${internal_path}"
    fi
    echo "$internal_path"
}

# __cli_denormalize_command_path: Converts internal space-separated path to user-facing dot-separated path.
# Removes "root" prefix for top-level commands.
# Usage: __cli_denormalize_command_path "root serve start"
# Returns: "serve.start"
# Usage: __cli_denormalize_command_path "root"
# Returns: "" (empty string for root command display name)
__cli_denormalize_command_path() {
    local internal_path="$1"
    if [[ "$internal_path" == "root" ]]; then
        echo "" # Root command has no dot-separated name for display
        return 0
    fi
    local user_path="${internal_path#"root "}" # Remove "root " prefix
    echo "${user_path// /.}" # Replace spaces with dots
}


# __cli_get_command_parts: Splits a full command path (internal, space-separated) into individual parts.
# Usage: __cli_get_command_parts "root serve start"
# Returns: "root" "serve" "start"
__cli_get_command_parts() {
    echo "$@"
}

# __cli_get_flag_def_str: Retrieves the flag definition string for a given command (internal path).
# Usage: __cli_get_flag_def_str <internal_command_path>
# Output: "flag1:s:def:desc:type:req|flag2:..."
__cli_get_flag_def_str() {
    local cmd_path_internal="$1"
    echo "${CLI_FLAGS_DEFINITIONS["$cmd_path_internal"]:-}"
}

# __cli_parse_flag_def: Parses a single flag definition string.
# Usage: __cli_parse_flag_def "port:p:8000:Port to listen on.:string:false"
# Sets: __CLI_TEMP_FLAG_NAME, __CLI_TEMP_FLAG_SHORT, __CLI_TEMP_FLAG_DEFAULT,
#       __CLI_TEMP_FLAG_DESC, __CLI_TEMP_FLAG_TYPE, __CLI_TEMP_FLAG_REQUIRED
__cli_parse_flag_def() {
    local def_str="$1"
    # Ensure def_str is not empty before parsing
    if [[ -z "$def_str" ]]; then
        __CLI_TEMP_FLAG_NAME=""
        __CLI_TEMP_FLAG_SHORT=""
        __CLI_TEMP_FLAG_DEFAULT=""
        __CLI_TEMP_FLAG_DESC=""
        __CLI_TEMP_FLAG_TYPE=""
        __CLI_TEMP_FLAG_REQUIRED=""
        return 1 # Indicate failure to parse
    fi
    IFS=':' read -r __CLI_TEMP_FLAG_NAME \
                  __CLI_TEMP_FLAG_SHORT \
                  __CLI_TEMP_FLAG_DEFAULT \
                  __CLI_TEMP_FLAG_DESC \
                  __CLI_TEMP_FLAG_TYPE \
                  __CLI_TEMP_FLAG_REQUIRED <<< "$def_str"
    return 0 # Indicate success
}

# __cli_is_valid_flag_type: Checks if a flag type is valid.
__cli_is_valid_flag_type() {
    local type="$1"
    [[ "$type" == "string" || "$type" == "bool" ]]
}

# __cli_is_valid_flag_name: Checks if a given flag name (long or short) exists for a specific command (internal path) or globally.
# Usage: __cli_is_valid_flag_name <flag_arg_string> <internal_command_path> [output_flag_name_var]
# This function is crucial for distinguishing flags from subcommands during the initial parsing.
# The optional third argument is a variable name to store the actual long flag name found.
__cli_is_valid_flag_name() {
    local flag_arg="$1" # e.g., "--config" or "-c"
    local current_cmd_path_internal="$2" # This is the internal, space-separated path where the flag is expected
    local __ret_flag_name_var="${3:-}" # Variable to store the resolved long flag name

    local is_long_flag="false"
    local is_short_flag="false"
    local potential_flag_name=""
    local resolved_long_flag_name=""

    if [[ "$flag_arg" == "--" ]]; then return 1; fi # "--" is a separator, not a flag name
    if [[ "$flag_arg" =~ ^-- ]]; then
        potential_flag_name="${flag_arg#--}"
        if [[ "$potential_flag_name" =~ = ]]; then # handle --flag=value
            potential_flag_name="${potential_flag_name%%=*}"
        fi
        is_long_flag="true"
    elif [[ "$flag_arg" =~ ^- && ${#flag_arg} -eq 2 ]]; then
        potential_flag_name="${flag_arg#-}"
        is_short_flag="true"
    else
        return 1 # Not a flag format
    fi

    # 1. Check local command flags first
    local local_flag_defs="$(__cli_get_flag_def_str "$current_cmd_path_internal")"
    if [[ -n "$local_flag_defs" ]]; then
        local OLD_IFS="$IFS"
        IFS='|' read -ra LOCAL_DEFS_ARRAY <<< "$local_flag_defs"
        IFS="$OLD_IFS"
        for flag_def in "${LOCAL_DEFS_ARRAY[@]}"; do
            if [[ -z "$flag_def" ]]; then continue; fi
            if __cli_parse_flag_def "$flag_def"; then
                if [[ "$is_long_flag" == "true" && "$__CLI_TEMP_FLAG_NAME" == "$potential_flag_name" ]]; then
                    resolved_long_flag_name="$__CLI_TEMP_FLAG_NAME"
                    [[ -n "$__ret_flag_name_var" ]] && printf -v "$__ret_flag_name_var" "%s" "$resolved_long_flag_name"
                    return 0 # Found a valid long flag for current command
                elif [[ "$is_short_flag" == "true" && "$__CLI_TEMP_FLAG_SHORT" == "$potential_flag_name" ]]; then
                    resolved_long_flag_name="$__CLI_TEMP_FLAG_NAME"
                    [[ -n "$__ret_flag_name_var" ]] && printf -v "$__ret_flag_name_var" "%s" "$resolved_long_flag_name"
                    return 0 # Found a valid short flag for current command
                fi
            fi
        done
    fi

    # 2. Then check global flags (root command flags)
    local root_flag_defs="$(__cli_get_flag_def_str "root")"
    if [[ -n "$root_flag_defs" ]]; then
        local OLD_IFS="$IFS"
        IFS='|' read -ra ROOT_DEFS_ARRAY <<< "$root_flag_defs"
        IFS="$OLD_IFS"
        for flag_def in "${ROOT_DEFS_ARRAY[@]}"; do
            if [[ -z "$flag_def" ]]; then continue; fi
            if __cli_parse_flag_def "$flag_def"; then
                if [[ "$is_long_flag" == "true" && "$__CLI_TEMP_FLAG_NAME" == "$potential_flag_name" ]]; then
                    resolved_long_flag_name="$__CLI_TEMP_FLAG_NAME"
                    [[ -n "$__ret_flag_name_var" ]] && printf -v "$__ret_flag_name_var" "%s" "$resolved_long_flag_name"
                    return 0 # Found a valid global long flag
                elif [[ "$is_short_flag" == "true" && "$__CLI_TEMP_FLAG_SHORT" == "$potential_flag_name" ]]; then
                    resolved_long_flag_name="$__CLI_TEMP_FLAG_NAME"
                    [[ -n "$__ret_flag_name_var" ]] && printf -v "$__ret_flag_name_var" "%s" "$resolved_long_flag_name"
                    return 0 # Found a valid global short flag
                fi
            fi
        done
    fi

    return 1 # Not found as a valid flag for current command or globally
}


# __cli_get_direct_subcommands: Gets direct subcommands (internal paths) of a parent command (internal path).
# Usage: __cli_get_direct_subcommands "root"
# Output (each on a new line): "root serve", "root config"
__cli_get_direct_subcommands() {
    local parent_cmd_internal="$1"
    local subcommands=""
    # Calculate parts for parent_cmd_internal for length comparison
    local parent_parts_count=$(__cli_get_command_parts "$parent_cmd_internal" | wc -w)

    for cmd_full_name_internal in "${!CLI_COMMANDS_MAP[@]}"; do
        # We need to exclude the "root" command itself from being listed as a subcommand of "root"
        # unless it's the only command. But in our current structure, "root" is implicitly the base.
        if [[ "$cmd_full_name_internal" == "root" ]]; then continue; fi

        # Check if it's a direct child
        # Ensure the full command name starts with the parent's path followed by a space
        if [[ "$cmd_full_name_internal" == "$parent_cmd_internal "* ]]; then
            local suffix="${cmd_full_name_internal#"$parent_cmd_internal "}"
            local suffix_parts_count=$(__cli_get_command_parts "$suffix" | wc -w)
            if (( suffix_parts_count == 1 )); then # Exactly one word after parent_cmd, meaning it's a direct child
                subcommands+="$cmd_full_name_internal"$'\n'
            fi
        fi
    done
    echo "$subcommands" | sort
}

# __cli_print_help: Prints help message for a command (internal path).
# Usage: __cli_print_help <internal_command_path>
__cli_print_help() {
    local cmd_path_internal="$1"
    local func_name="${CLI_COMMANDS_MAP["$cmd_path_internal"]:-}"
    local short_desc="${CLI_COMMAND_DESCRIPTIONS["$cmd_path_internal"]:-}"
    local long_desc="${CLI_COMMAND_LONG_DESCRIPTIONS["$cmd_path_internal"]:-}"
    local example="${CLI_COMMAND_EXAMPLES["$cmd_path_internal"]:-}"

    local display_cmd_name=$(__cli_denormalize_command_path "$cmd_path_internal")
    local display_cmd_path="${CLI_TOOL_NAME}"
    if [[ -n "$display_cmd_name" ]]; then
        display_cmd_path+=" $display_cmd_name"
    fi

    echo "Usage:"
    echo "  ${display_cmd_path} [flags]"
    local direct_subcommands=$(__cli_get_direct_subcommands "$cmd_path_internal")
    if [[ -n "$direct_subcommands" ]]; then
        echo "  ${display_cmd_path} [command]"
    fi
    echo
    echo "Short Description:"
    echo "  ${short_desc}"
    echo

    if [[ -n "$long_desc" ]]; then
        echo "Long Description:"
        echo "  ${long_desc}"
        echo
    fi

    if [[ -n "$example" ]]; then
        echo "Examples:"
        echo "  ${example}"
        echo
    fi

    # Print Local Flags (for non-root commands, or root if it has specific flags)
    local local_flag_defs="$(__cli_get_flag_def_str "$cmd_path_internal")"
    if [[ -n "$local_flag_defs" ]]; then
        echo "Flags:"
        local OLD_IFS="$IFS" # Save IFS
        IFS='|' read -ra FLAG_DEF_ARRAY <<< "$local_flag_defs"
        IFS="$OLD_IFS" # Restore IFS

        for flag_def in "${FLAG_DEF_ARRAY[@]}"; do
            if [[ -z "$flag_def" ]]; then continue; fi # Skip empty definitions
            __cli_parse_flag_def "$flag_def" || continue # Skip if parsing failed
            local flag_str=""
            if [[ -n "$__CLI_TEMP_FLAG_SHORT" ]]; then
                flag_str="-${__CLI_TEMP_FLAG_SHORT}, --${__CLI_TEMP_FLAG_NAME}"
            else
                flag_str="    --${__CLI_TEMP_FLAG_NAME}"
            fi

            local default_str=""
            if [[ "$__CLI_TEMP_FLAG_TYPE" == "string" && -n "$__CLI_TEMP_FLAG_DEFAULT" ]]; then
                default_str=" (default: \"${__CLI_TEMP_FLAG_DEFAULT}\")"
            elif [[ "$__CLI_TEMP_FLAG_TYPE" == "bool" && "$__CLI_TEMP_FLAG_DEFAULT" == "true" ]]; then
                default_str=" (default: true)"
            fi
            local required_str=""
            if [[ "$__CLI_TEMP_FLAG_REQUIRED" == "true" ]]; then
                required_str=" (required)"
            fi
            printf "  %-20s %s%s%s\n" "$flag_str" "$__CLI_TEMP_FLAG_DESC" "$default_str" "$required_str"
        done
        echo
    fi

    # Print Global Flags (always display if they exist, and not already covered by local flags)
    local root_flag_defs="$(__cli_get_flag_def_str "root")"

    if [[ -n "$root_flag_defs" ]]; then
        echo "Global Flags:"
        local OLD_IFS="$IFS" # Save IFS
        IFS='|' read -ra GLOBAL_FLAG_DEF_ARRAY <<< "$root_flag_defs"
        IFS="$OLD_IFS" # Restore IFS

        for flag_def in "${GLOBAL_FLAG_DEF_ARRAY[@]}"; do
            if [[ -z "$flag_def" ]]; then continue; fi # Skip empty definitions
            if __cli_parse_flag_def "$flag_def"; then
                # Check if this global flag has a local counterpart with the same name.
                # If so, the local one is already printed under "Flags:", so skip this global one here.
                local is_local_flag_with_same_name="false"
                if [[ -n "$local_flag_defs" ]]; then
                    local OLD_IFS_INNER="$IFS" # Save IFS for inner loop
                    IFS='|' read -ra TEMP_LOCAL_FLAG_DEF_ARRAY <<< "$local_flag_defs"
                    IFS="$OLD_IFS_INNER" # Restore IFS for inner loop

                    for local_def in "${TEMP_LOCAL_FLAG_DEF_ARRAY[@]}"; do
                        if [[ -z "$local_def" ]]; then continue; fi
                        local local_flag_name="${local_def%%:*}"
                        if [[ "$local_flag_name" == "$__CLI_TEMP_FLAG_NAME" ]]; then
                            is_local_flag_with_same_name="true"
                            break
                        fi
                    done
                fi
                if [[ "$is_local_flag_with_same_name" == "true" ]]; then continue; fi # Skip if a local flag with same name exists

                local flag_str=""
                if [[ -n "$__CLI_TEMP_FLAG_SHORT" ]]; then
                    flag_str="-${__CLI_TEMP_FLAG_SHORT}, --${__CLI_TEMP_FLAG_NAME}"
                else
                    flag_str="    --${__CLI_TEMP_FLAG_NAME}"
                fi

                local default_str=""
                if [[ "$__CLI_TEMP_FLAG_TYPE" == "string" && -n "$__CLI_TEMP_FLAG_DEFAULT" ]]; then
                    default_str=" (default: \"${__CLI_TEMP_FLAG_DEFAULT}\")"
                elif [[ "$__CLI_TEMP_FLAG_TYPE" == "bool" && "$__CLI_TEMP_FLAG_DEFAULT" == "true" ]]; then
                    default_str=" (default: true)"
                fi
                printf "  %-20s %s%s\n" "$flag_str" "$__CLI_TEMP_FLAG_DESC" "$default_str"
            fi # End of __cli_parse_flag_def check
        done
        echo
    fi


    # Print Available Commands (subcommands)
    local direct_subcommands=$(__cli_get_direct_subcommands "$cmd_path_internal")
    if [[ -n "$direct_subcommands" ]]; then
        echo "Available Commands:"
        local max_cmd_len=0
        local sub_array=()
        local OLD_IFS="$IFS" # Save IFS
        # Read direct_subcommands into an array, handling newlines
        IFS=$'\n' read -r -d '' -a sub_array <<< "$direct_subcommands"
        IFS="$OLD_IFS" # Restore IFS

        for cmd_full_name_internal in "${sub_array[@]}"; do
            # Extract the last part (e.g., "serve" from "root serve") for display length calculation
            local cmd_base_name_internal="${cmd_full_name_internal##* }"
            if (( ${#cmd_base_name_internal} > max_cmd_len )); then
                max_cmd_len=${#cmd_base_name_internal}
            fi
        done

        for cmd_full_name_internal in "${sub_array[@]}"; do
            local cmd_base_name_internal="${cmd_full_name_internal##* }"
            printf "  %-*s %s\n" $((max_cmd_len + 4)) "$cmd_base_name_internal" "${CLI_COMMAND_DESCRIPTIONS["$cmd_full_name_internal"]}"
        done
        echo
    fi
}

# ==============================================================================
# Public API for Command Registration
# ==============================================================================

# cli_register_command: Registers a new command.
# Usage: cli_register_command <user_command_path> <function_name> <short_description> [long_description] [example]
# <user_command_path>: "", "serve", "serve.start" (empty string for root command)
cli_register_command() {
    local user_cmd_path="$1" # User provides "" for root, "serve", "serve.start"
    local func_name="$2"
    local short_desc="$3"
    local long_desc="${4:-}"
    local example="${5:-}"

    # Normalize user path to internal space-separated path
    local cmd_path_internal=$(__cli_normalize_command_path "$user_cmd_path")

    if [[ -n "${CLI_COMMANDS_MAP["$cmd_path_internal"]}" ]]; then
        echo "Warning: Command '$user_cmd_path' (internal: '$cmd_path_internal') is already registered. Overwriting." >&2
    fi

    CLI_COMMANDS_MAP["$cmd_path_internal"]="$func_name"
    CLI_COMMAND_DESCRIPTIONS["$cmd_path_internal"]="$short_desc"
    CLI_COMMAND_LONG_DESCRIPTIONS["$cmd_path_internal"]="$long_desc"
    CLI_COMMAND_EXAMPLES["$cmd_path_internal"]="$example"
    CLI_FLAGS_DEFINITIONS["$cmd_path_internal"]="" # Initialize flag definitions for this command
}

# cli_register_flag: Registers a flag for a specific command.
# Usage: cli_register_flag <user_command_path> <flag_name> <short_char> <default_value> <description> <type> [required]
# <user_command_path>: "", "serve", "serve.start" (empty string for root command, "root" for global)
cli_register_flag() {
    local user_cmd_path="$1" # User provides "" for root, "serve", "serve.start"
    local flag_name="$2"
    local short_char="$3"
    local default_value="$4"
    local description="$5"
    local type="$6"
    local required="${7:-false}"

    # Normalize user path to internal space-separated path
    local cmd_path_internal=$(__cli_normalize_command_path "$user_cmd_path")

    if ! __cli_is_valid_flag_type "$type"; then
        echo "Error: Invalid flag type '$type' for flag '$flag_name' on command '$user_cmd_path'. Must be 'string' or 'bool'." >&2
        exit 1
    fi

    local new_flag_def="${flag_name}:${short_char}:${default_value}:${description}:${type}:${required}"

    # Check if flag_name already exists for this command
    local existing_defs="${CLI_FLAGS_DEFINITIONS["$cmd_path_internal"]}"

    local temp_defs_array=()
    local found_flag="false"
    if [[ -n "$existing_defs" ]]; then
        local OLD_IFS="$IFS" # Save IFS
        IFS='|' read -ra DEF_ARRAY <<< "$existing_defs"
        IFS="$OLD_IFS" # Restore IFS
        for def_item in "${DEF_ARRAY[@]}"; do
            if [[ -z "$def_item" ]]; then continue; fi # Skip empty item
            local existing_flag_name="${def_item%%:*}"
            if [[ "$existing_flag_name" == "$flag_name" ]]; then
                # If existing, replace it (allowing re-registration to update)
                temp_defs_array+=("$new_flag_def")
                found_flag="true"
            else
                temp_defs_array+=("$def_item")
            fi
        done
    fi

    if [[ "$found_flag" == "false" ]]; then
        temp_defs_array+=("$new_flag_def")
    fi
    CLI_FLAGS_DEFINITIONS["$cmd_path_internal"]=$(IFS='|'; echo "${temp_defs_array[*]}")

    # Register short flag to long flag mapping globally
    if [[ -n "$short_char" ]]; then
        if [[ -n "${CLI_SHORT_FLAG_TO_LONG["$short_char"]}" && "${CLI_SHORT_FLAG_TO_LONG["$short_char"]}" != "$flag_name" ]]; then
            echo "Warning: Short flag '-${short_char}' is already registered for '--${CLI_SHORT_FLAG_TO_LONG["$short_char"]}'. Ignoring this new mapping for '--${flag_name}'." >&2
        else
            CLI_SHORT_FLAG_TO_LONG["$short_char"]="$flag_name"
        fi
    fi

    # Mark as global flag if registered for "root"
    if [[ "$cmd_path_internal" == "root" ]]; then
        CLI_GLOBAL_FLAGS_MAP["$flag_name"]="true"
    fi
}

# cli_register_global_flag: A convenience function to register a global flag.
# This simply calls cli_register_flag with "" (empty string) as the command_path for the root command.
# Usage: cli_register_global_flag <flag_name> <short_char> <default_value> <description> <type> [required]
cli_register_global_flag() {
    # All arguments are passed directly to cli_register_flag, with "" as the user_command_path.
    cli_register_flag "" "$@" # Use empty string for user_command_path for consistency with cli_register_command for root
}


# cli_get_flag: Retrieves the parsed value of a flag for the *current* command context.
# This can be a local command flag or an applicable global flag.
# Usage: cli_get_flag <flag_name>
# Returns: The value, or an empty string if not set.
cli_get_flag() {
    local flag_name="$1"
    echo "${CLI_PARSED_FLAGS["$flag_name"]:-}"
}

# cli_get_global_flag: Retrieves the parsed value of a specifically *global* flag.
# This function is intended for cases where you explicitly need to know if a flag is global
# and access its global value, regardless of potential local overrides.
# Usage: cli_get_global_flag <flag_name>
# Returns: The value, or an empty string if not set.
cli_get_global_flag() {
    local flag_name="$1"
    if [[ "${CLI_GLOBAL_FLAGS_MAP["$flag_name"]}" == "true" ]]; then
        echo "${CLI_PARSED_FLAGS["$flag_name"]:-}"
    else
        # Optional: warn if trying to get a non-global flag with this function
        # echo "Warning: Flag '$flag_name' is not registered as a global flag." >&2
        echo ""
    fi
}


# ==============================================================================
# Main CLI Execution Logic
# ==============================================================================

# cli_run: The main function to parse commands and dispatch execution.
# Usage: cli_run "$@" (pass all arguments from the script)
cli_run() {
    local raw_args=("$@")
    local current_args=("${raw_args[@]}") # Mutable copy for parsing

    local command_path_internal="root" # Default to root command's internal path
    local command_func="${CLI_COMMANDS_MAP["root"]}" # Default to root command function
    local args_after_command_index=0 # Index of the first non-command arg/flag

    # 1. Handle help requests and no-argument scenarios (Early Exit)
    if [[ ${#raw_args[@]} -eq 0 ]]; then # No arguments at all
        __cli_print_help "root"
        exit 0
    fi

    # Special "help" command (e.g., mycli help serve) - This takes precedence
    if [[ "${raw_args[0]}" == "help" ]]; then
        local help_target_internal_cmd="root"
        local help_cmd_parts=("${raw_args[@]:1}") # arguments after "help"

        local temp_user_cmd_path_parts=()
        if (( ${#help_cmd_parts[@]} > 0 )); then
            for part in "${help_cmd_parts[@]}"; do
                temp_user_cmd_path_parts+=("$part")
                local test_user_path="$(IFS='.'; echo "${temp_user_cmd_path_parts[*]}")"
                local test_internal_path=$(__cli_normalize_command_path "$test_user_path")
                if [[ -n "${CLI_COMMANDS_MAP["$test_internal_path"]}" ]]; then
                    help_target_internal_cmd="$test_internal_path"
                else
                    echo "Error: Unknown command for help: '${test_user_path}'" >&2
                    __cli_print_help "root"
                    exit 1
                fi
            done
        fi
        __cli_print_help "$help_target_internal_cmd"
        exit 0
    fi

    # 2. Parse command parts and identify the specific command to execute
    local i=0
    local potential_command_parts=() # Stores the *user's* command parts (e.g., "serve", "start")

    while (( i < ${#current_args[@]} )); do
        local arg="${current_args[i]}"

        # If it's a flag format or "--", stop trying to find more command parts
        if [[ "$arg" == "--" || "$arg" =~ ^- ]]; then
            break
        fi

        potential_command_parts+=("$arg")
        local test_user_cmd_path="$(IFS='.'; echo "${potential_command_parts[*]}")"
        local test_internal_path=$(__cli_normalize_command_path "$test_user_cmd_path")

        if [[ -n "${CLI_COMMANDS_MAP["$test_internal_path"]}" ]]; then
            command_path_internal="$test_internal_path" # Update the deepest found command
            command_func="${CLI_COMMANDS_MAP["$command_path_internal"]}"
            args_after_command_index=$((i + 1)) # Keep track of where positional args/flags begin
            ((i++))
        else
            # This argument is not a valid continuation of a command.
            # It must be a positional argument or an invalid command.
            # We stop command parsing and mark this as the end of command arguments.
            break
        fi
    done

    # Remaining arguments are everything after the identified command.
    local remaining_args=("${current_args[@]:$args_after_command_index}")

    # Check for --help or -h flag among remaining args (e.g., `mycli serve --help`)
    # This should be after initial help command handling, but before actual flag parsing,
    # as it's a special request.
    local help_flag_present_in_args="false"
    for arg_for_help_check in "${remaining_args[@]}"; do
        if [[ "$arg_for_help_check" == "--help" || "$arg_for_help_check" == "-h" ]]; then
            help_flag_present_in_args="true"
            break
        fi
    done

    if [[ "$help_flag_present_in_args" == "true" ]]; then
        __cli_print_help "$command_path_internal"
        exit 0
    fi

    # If `command_func` is still empty at this point, it implies that even after
    # attempting to match subcommands, no valid command was found beyond 'root'.
    # This means the user either provided invalid subcommands, or only flags.
    # In such cases, `command_path_internal` should remain "root", and `command_func`
    # should be the function for the "root" command. We've already initialized it.

    # If the `command_func` is still empty here, it means "root" itself was not registered, which is an error.
    if [[ -z "$command_func" ]]; then
        echo "Error: Root command function is not registered. Please register the root command." >&2
        exit 1
    fi

    # 3. Initialize CLI_PARSED_FLAGS with default values
    # Clear previous parsed flags
    for key in "${!CLI_PARSED_FLAGS[@]}"; do
        unset CLI_PARSED_FLAGS["$key"]
    done

    # Get all relevant flag definitions (global first, then local to command_path_internal)
    local relevant_flag_defs_str=""
    local root_defs="$(__cli_get_flag_def_str "root")"
    if [[ -n "$root_defs" ]]; then
        relevant_flag_defs_str+="$root_defs"
    fi

    # If current command is not root, add its local flags.
    # Note: cli_register_flag ensures local flags (for a specific command) are distinct from global ones,
    # but a local flag could have the same name as a global one, effectively overriding it for that command.
    # We prioritize flags based on the `command_path_internal`'s definitions, then global definitions.
    if [[ "$command_path_internal" != "root" ]]; then
        local local_cmd_defs="$(__cli_get_flag_def_str "$command_path_internal")"
        if [[ -n "$local_cmd_defs" ]]; then
            if [[ -n "$relevant_flag_defs_str" ]]; then
                relevant_flag_defs_str+="|"
            fi
            relevant_flag_defs_str+="$local_cmd_defs"
        fi
    fi

    # Robustly iterate over flag definitions, skipping empty ones
    local ALL_FLAG_DEFS_ARRAY=()
    if [[ -n "$relevant_flag_defs_str" ]]; then
        local OLD_IFS="$IFS"
        IFS='|' read -r -d '' -a ALL_FLAG_DEFS_ARRAY <<< "$relevant_flag_defs_str" # Use -d '' to read all lines
        IFS="$OLD_IFS"
    fi

    # Initialize with default values. Later parsing will overwrite.
    # To handle potential overrides (local flag same name as global), we can initialize a temporary map
    # that prioritizes local over global when initializing defaults.
    declare -A TEMP_INIT_FLAGS
    # First, global defaults
    local global_defs_only="$(__cli_get_flag_def_str "root")"
    if [[ -n "$global_defs_only" ]]; then
        local OLD_IFS="$IFS"
        IFS='|' read -r -d '' -a GLOBAL_INIT_DEFS <<< "$global_defs_only"
        IFS="$OLD_IFS"
        for flag_def in "${GLOBAL_INIT_DEFS[@]}"; do
            if [[ -z "$flag_def" ]]; then continue; fi
            if __cli_parse_flag_def "$flag_def"; then
                TEMP_INIT_FLAGS["$__CLI_TEMP_FLAG_NAME"]="$__CLI_TEMP_FLAG_DEFAULT"
            fi
        done
    fi

    # Then, local defaults (will overwrite global if names conflict)
    if [[ "$command_path_internal" != "root" ]]; then
        local local_cmd_defs_only="$(__cli_get_flag_def_str "$command_path_internal")"
        if [[ -n "$local_cmd_defs_only" ]]; then
            local OLD_IFS="$IFS"
            IFS='|' read -r -d '' -a LOCAL_INIT_DEFS <<< "$local_cmd_defs_only"
            IFS="$OLD_IFS"
            for flag_def in "${LOCAL_INIT_DEFS[@]}"; do
                if [[ -z "$flag_def" ]]; then continue; fi
                if __cli_parse_flag_def "$flag_def"; then
                    TEMP_INIT_FLAGS["$__CLI_TEMP_FLAG_NAME"]="$__CLI_TEMP_FLAG_DEFAULT"
                fi
            done
        fi
    fi

    # Copy initialized defaults to CLI_PARSED_FLAGS
    for flag_name in "${!TEMP_INIT_FLAGS[@]}"; do
        CLI_PARSED_FLAGS["$flag_name"]="${TEMP_INIT_FLAGS["$flag_name"]}"
    done


    # 4. Parse flags from remaining_args and override defaults
    local final_positional_args=() # Collects positional arguments after flags
    local arg_idx=0
    while (( arg_idx < ${#remaining_args[@]} )); do
        local arg="${remaining_args[arg_idx]}"
        local resolved_flag_name="" # To store the actual long flag name found

        if [[ "$arg" == "--" ]]; then # Stop parsing flags after "--"
            final_positional_args+=("${remaining_args[@]:$((arg_idx + 1))}")
            break
        elif [[ "$arg" =~ ^-- ]]; then # Long flag (--flag or --flag=value)
            local flag_part="${arg#--}"
            local parsed_flag_name=""
            local parsed_flag_value=""

            if [[ "$flag_part" =~ = ]]; then
                parsed_flag_name="${flag_part%%=*}"
                parsed_flag_value="${flag_part#*=}"
            else
                parsed_flag_name="$flag_part"
            fi

            if ! __cli_is_valid_flag_name "--$parsed_flag_name" "$command_path_internal" "resolved_flag_name"; then
                echo "Error: Unknown flag '--${parsed_flag_name}' for command context '${command_path_internal}'" >&2
                exit 1
            fi

            # Find the definition for this specific flag name to get its type
            local target_flag_def_str=""
            local found_def_for_parsing="false"
            local flag_type_for_parsing="string" # Default type for robustness

            # Check current command's flags first for definition
            local local_defs_check="$(__cli_get_flag_def_str "$command_path_internal")"
            if [[ -n "$local_defs_check" ]]; then
                local OLD_IFS_INNER="$IFS"
                IFS='|' read -r -d '' -a LOCAL_DEF_ARRAY_FOR_PARSE <<< "$local_defs_check"
                IFS="$OLD_IFS_INNER"
                for def_item in "${LOCAL_DEF_ARRAY_FOR_PARSE[@]}"; do
                    if [[ "${def_item%%:*}" == "$resolved_flag_name" ]]; then
                        target_flag_def_str="$def_item"
                        found_def_for_parsing="true"
                        break
                    fi
                done
            fi

            # If not found in local, check global flags
            if [[ "$found_def_for_parsing" == "false" ]]; then
                local global_defs_check="$(__cli_get_flag_def_str "root")"
                if [[ -n "$global_defs_check" ]]; then
                    local OLD_IFS_INNER="$IFS"
                    IFS='|' read -r -d '' -a GLOBAL_DEF_ARRAY_FOR_PARSE <<< "$global_defs_check"
                    IFS="$OLD_IFS_INNER"
                    for def_item in "${GLOBAL_DEF_ARRAY_FOR_PARSE[@]}"; do
                        if [[ "${def_item%%:*}" == "$resolved_flag_name" ]]; then
                            target_flag_def_str="$def_item"
                            found_def_for_parsing="true"
                            break
                        fi
                    done
                fi
            fi

            if [[ "$found_def_for_parsing" == "true" ]]; then
                __cli_parse_flag_def "$target_flag_def_str"
                flag_type_for_parsing="$__CLI_TEMP_FLAG_TYPE"
            else
                # This should ideally not be reached due to __cli_is_valid_flag_name check,
                # but good for defensive programming.
                echo "Internal Error: Flag '${resolved_flag_name}' definition not found." >&2
                exit 1
            fi


            # Set parsed value based on type
            if [[ "$flag_type_for_parsing" == "bool" ]]; then
                if [[ "$flag_part" =~ = ]]; then
                    if [[ "$parsed_flag_value" == "true" ]]; then
                        CLI_PARSED_FLAGS["$resolved_flag_name"]="true"
                    elif [[ "$parsed_flag_value" == "false" ]]; then
                        CLI_PARSED_FLAGS["$resolved_flag_name"]="false"
                    else
                        echo "Warning: Invalid boolean value for --${resolved_flag_name}: '$parsed_flag_value'. Using 'true'." >&2
                        CLI_PARSED_FLAGS["$resolved_flag_name"]="true"
                    fi
                else
                    CLI_PARSED_FLAGS["$resolved_flag_name"]="true" # Just presence means true for bool
                fi
            else # String type
                if [[ "$flag_part" =~ = ]]; then
                    CLI_PARSED_FLAGS["$resolved_flag_name"]="$parsed_flag_value"
                else
                    local next_arg="${remaining_args[arg_idx+1]:-}"
                    # If next arg is not empty and doesn't start with '-', it's the flag value
                    if [[ -n "$next_arg" && ! "$next_arg" =~ ^- ]]; then
                        CLI_PARSED_FLAGS["$resolved_flag_name"]="$next_arg"
                        ((arg_idx++)) # Consume the next argument as the flag value
                    else
                        # String flag without an explicit value: assign empty string
                        CLI_PARSED_FLAGS["$resolved_flag_name"]=""
                    fi
                fi
            fi
        elif [[ "$arg" =~ ^- && ${#arg} -eq 2 ]]; then # Short flag (-f or -f value)
            local short_char="${arg#-}"

            if ! __cli_is_valid_flag_name "-$short_char" "$command_path_internal" "resolved_flag_name"; then
                echo "Error: Unknown short flag '-${short_char}' for command context '${command_path_internal}'" >&2
                exit 1
            fi

            # Find the definition for this specific flag name to get its type
            local target_flag_def_str=""
            local found_def_for_parsing="false"
            local flag_type_for_parsing="string" # Default type for robustness

            # Check current command's flags first for definition
            local local_defs_check="$(__cli_get_flag_def_str "$command_path_internal")"
            if [[ -n "$local_defs_check" ]]; then
                local OLD_IFS_INNER="$IFS"
                IFS='|' read -r -d '' -a LOCAL_DEF_ARRAY_FOR_PARSE <<< "$local_defs_check"
                IFS="$OLD_IFS_INNER"
                for def_item in "${LOCAL_DEF_ARRAY_FOR_PARSE[@]}"; do
                    if [[ "${def_item%%:*}" == "$resolved_flag_name" ]]; then
                        target_flag_def_str="$def_item"
                        found_def_for_parsing="true"
                        break
                    fi
                done
            fi

            # If not found in local, check global flags
            if [[ "$found_def_for_parsing" == "false" ]]; then
                local global_defs_check="$(__cli_get_flag_def_str "root")"
                if [[ -n "$global_defs_check" ]]; then
                    local OLD_IFS_INNER="$IFS"
                    IFS='|' read -r -d '' -a GLOBAL_DEF_ARRAY_FOR_PARSE <<< "$global_defs_check"
                    IFS="$OLD_IFS_INNER"
                    for def_item in "${GLOBAL_DEF_ARRAY_FOR_PARSE[@]}"; do
                        if [[ "${def_item%%:*}" == "$resolved_flag_name" ]]; then
                            target_flag_def_str="$def_item"
                            found_def_for_parsing="true"
                            break
                        fi
                    done
                fi
            fi

            if [[ "$found_def_for_parsing" == "true" ]]; then
                __cli_parse_flag_def "$target_flag_def_str"
                flag_type_for_parsing="$__CLI_TEMP_FLAG_TYPE"
            else
                echo "Internal Error: Flag '${resolved_flag_name}' definition not found during short flag parse." >&2
                exit 1
            fi

            # Set parsed value based on type
            if [[ "$flag_type_for_parsing" == "bool" ]]; then
                CLI_PARSED_FLAGS["$resolved_flag_name"]="true" # Just presence means true for bool
            else # String type
                local next_arg="${remaining_args[arg_idx+1]:-}"
                if [[ -n "$next_arg" && ! "$next_arg" =~ ^- ]]; then
                    CLI_PARSED_FLAGS["$resolved_flag_name"]="$next_arg"
                    ((arg_idx++)) # Consume the next argument as the flag value
                else
                    CLI_PARSED_FLAGS["$resolved_flag_name"]="" # String flag without a value
                fi
            fi
        else # Non-flag argument (positional argument)
            final_positional_args+=("$arg")
        fi
        ((arg_idx++))
    done

    # 5. Validate required flags
    # We re-gather all relevant flags for the *current* command_path_internal to validate required flags.
    local current_cmd_all_flag_defs_str=""
    local root_defs_for_validation="$(__cli_get_flag_def_str "root")"
    if [[ -n "$root_defs_for_validation" ]]; then
        current_cmd_all_flag_defs_str+="$root_defs_for_validation"
    fi

    if [[ "$command_path_internal" != "root" ]]; then
        local local_cmd_defs_for_validation="$(__cli_get_flag_def_str "$command_path_internal")"
        if [[ -n "$local_cmd_defs_for_validation" ]]; then
            if [[ -n "$current_cmd_all_flag_defs_str" ]]; then
                current_cmd_all_flag_defs_str+="|"
            fi
            current_cmd_all_flag_defs_str+="$local_cmd_defs_for_validation"
        fi
    fi

    local FINAL_CHECK_FLAG_DEFS_ARRAY=()
    if [[ -n "$current_cmd_all_flag_defs_str" ]]; then
        local OLD_IFS="$IFS"
        IFS='|' read -r -d '' -a FINAL_CHECK_FLAG_DEFS_ARRAY <<< "$current_cmd_all_flag_defs_str"
        IFS="$OLD_IFS"
    fi

    for flag_def in "${FINAL_CHECK_FLAG_DEFS_ARRAY[@]}"; do
        if [[ -z "$flag_def" ]]; then continue; fi
        if __cli_parse_flag_def "$flag_def"; then
            if [[ "$__CLI_TEMP_FLAG_REQUIRED" == "true" ]]; then
                # A required flag can be satisfied by a specific local definition
                # or by a global definition if no local one exists and it's set.
                if [[ -z "${CLI_PARSED_FLAGS["$__CLI_TEMP_FLAG_NAME"]}" ]]; then
                    echo "Error: Required flag --${__CLI_TEMP_FLAG_NAME} not set for command context '${command_path_internal}'." >&2
                    __cli_print_help "$command_path_internal"
                    exit 1
                fi
            fi
        fi
    done

    # 6. Execute the command function with final positional arguments
    # Ensure command_func is not empty. If it's still empty, it means no command (even root) was properly mapped,
    # which points to a registration issue.
    if [[ -z "$command_func" ]]; then
        echo "Error: No command function found for command path '${command_path_internal}'. This indicates a registration issue." >&2
        __cli_print_help "root"
        exit 1
    fi

    "$command_func" "${final_positional_args[@]}"
}
