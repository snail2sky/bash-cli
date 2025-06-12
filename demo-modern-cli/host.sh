##### load bash-cli library
source $(dirname $0)/../bash-cli.sh

# load libs
for lib_file in "libs/"*.sh; do
    source "$lib_file"
done

# load commands
for cmd_file in "commands/"*.sh; do
    source "$cmd_file"
done

# --- Run the CLI ---
cli_run "$@"
