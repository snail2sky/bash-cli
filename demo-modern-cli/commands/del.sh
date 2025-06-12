cli_register_command \
    "del" \
    "cli_del_func" \
    "delete matched host map of ip and host" \
    "delete manthed host map of ip and host" \
    "${CLI_TOOL_NAME} del --host localhost --ip 127.0.0.1"

cli_register_flag "del" "host" "H" "localhost" "localhost domain name" "string" "true"
cli_register_flag "del" "ip" "i" "127.0.0.1" "local loop ip" "string" "true"


cli_del_func(){
    local host=$(cli_get_flag "host")
    local ip=$(cli_get_flag "ip")

    if ! id_check; then
        echo current user: $USER has not permissions to modify /etc/hosts
	exit 2
    fi

    if ! ip_check $ip; then
        echo $ip invalid
	exit 1
    fi
    sed -i "/$ip $host/d" /etc/hosts

    echo "$ip $host has been deleted."
}

