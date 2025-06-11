#!/bin/bash

# 引入核心命令行框架
source "$(dirname "$0")/bash-cli.sh"

# --- Command Functions ---

# Root Command Function
cli_root_func() {
    local verbose=$(cli_get_flag "verbose") # 从 cli_get_flag 获取
    local config_path=$(cli_get_flag "config") # 从 cli_get_flag 获取
    local global_debug=$(cli_get_global_flag "debug") # 使用新函数 cli_get_global_flag 获取

    if [[ "$verbose" == "true" ]]; then echo "Verbose mode enabled for root."; fi
    if [[ -n "$config_path" ]]; then echo "Using config file: $config_path"; fi
    if [[ "$global_debug" == "true" ]]; then echo "Global debug mode is ON (retrieved via cli_get_global_flag)."; fi

    if [[ ${#@} -eq 0 ]]; then # No positional arguments after flags
        echo "Welcome to my CLI tool!"
        echo "Use '${CLI_TOOL_NAME} help' for more information."
    else
        echo "Error: Unexpected arguments for root command: '$@'" >&2
        __cli_print_help "root" # 仍使用内部路径
        exit 1
    fi
}
# Register Root Command - Use empty string "" for the top-level (root) command
cli_register_command \
    "" \
    "cli_root_func" \
    "A simple CLI tool example." \
    "This is a longer description of the root command, providing general information about the application." \
    "${CLI_TOOL_NAME} --verbose"

# Register Global Flags - Still use "root" as path for global flags
cli_register_global_flag "verbose" "v" "false" "Enable verbose output." "bool" "false"
cli_register_global_flag "config" "c" "" "Path to configuration file." "string" "false"
cli_register_global_flag "debug" "D" "false" "Enable global debug logging." "bool" "false"


# Serve Command Function
cli_serve_func() {
    local port=$(cli_get_flag "port") # 命令的本地 flag
    local host=$(cli_get_flag "host") # 命令的本地 flag
    local global_debug=$(cli_get_global_flag "debug") # 使用新函数 cli_get_global_flag 获取

    if [[ "$global_debug" == "true" ]]; then echo "[Serve] Global debug mode is ON (retrieved via cli_get_global_flag)."; fi
    echo "Serving on ${host}:${port}..."
    echo "Remaining arguments for serve: $@" # Positional arguments
    # Add actual server startup logic here
}
# Register Serve Command - Use "serve" for top-level command
cli_register_command \
    "serve" \
    "cli_serve_func" \
    "Start the server." \
    "This command initiates the application server process, binding to a specified host and port." \
    "${CLI_TOOL_NAME} serve --port 8080 --host 0.0.0.0"

# Register Flags for Serve Command (local flags) - Use "serve" as command path
cli_register_flag "serve" "port" "p" "8000" "Port to listen on." "string" "false"
cli_register_flag "serve" "host" "" "127.0.0.1" "Host to bind to." "string" "false"


# Serve Start Command Function
cli_serve_start_func() {
    local background=$(cli_get_flag "background")
    local log_file=$(cli_get_flag "log-file")
    local env=$(cli_get_flag "env")
    local global_debug=$(cli_get_global_flag "debug") # 使用新函数 cli_get_global_flag 获取

    if [[ "$global_debug" == "true" ]]; then echo "[Serve Start] Global debug mode is ON (retrieved via cli_get_global_flag)."; fi
    echo "Starting server in background: ${background}"
    echo "Logging to file: ${log_file}"
    echo "Environment: ${env}"
    echo "Remaining arguments for 'serve start': $@"
    # Add actual server daemonization logic here
}
# Register Serve Start Command - Use "serve.start" for nested command
cli_register_command \
    "serve.start" \
    "cli_serve_start_func" \
    "Start the server process in the background." \
    "Starts the server in daemon mode, optionally logging output to a file and setting the environment." \
    "${CLI_TOOL_NAME} serve start -e production --background --log-file /var/log/app.log"

# Register Flags for Serve Start Command - Use "serve.start" as command path
cli_register_flag "serve.start" "background" "b" "false" "Run in background (daemonize)." "bool" "false"
cli_register_flag "serve.start" "log-file" "l" "" "Path to log output." "string" "false"
cli_register_flag "serve.start" "env" "e" "" "Deployment environment (e.g., prod, dev)." "string" "true" # Required flag


# Config Command Function
cli_config_func() {
    local global_debug=$(cli_get_global_flag "debug") # 使用新函数 cli_get_global_flag 获取
    if [[ "$global_debug" == "true" ]]; then echo "[Config] Global debug mode is ON (retrieved via cli_get_global_flag)."; fi
    echo "Config command called."
    echo "Positional arguments: $@" # This command expects positional arguments
    # Add config management logic here based on positional arguments
}
# Register Config Command - Use "config" for top-level command
cli_register_command \
    "config" \
    "cli_config_func" \
    "Manage application configuration." \
    "This command allows viewing and modifying configuration settings, typically taking sub-commands or arguments for 'set', 'get', 'view'." \
    "${CLI_TOOL_NAME} config set database.url postgresql://user:pass@host:port/db"

# --- Run the CLI ---
cli_run "$@"
