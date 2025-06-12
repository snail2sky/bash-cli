cli_register_command \
    "" \
    "cli_root_func" \
    "A simple CLI tool example." \
    "This is a longer description of the root command, providing general information about the application." \
    "${CLI_TOOL_NAME} add"


cli_root_func() {
    __cli_print_help "root"
}

