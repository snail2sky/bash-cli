cli_register_command \
    "add" \
    "cli_add_func" \
    "add a host map of ip and host" \
    "add a host map of ip and host" \
    "${CLI_TOOL_NAME} add --host localhost --ip 127.0.0.1"

cli_register_flag "add" "host" "H" "localhost" "localhost domain name" "string" "true"
cli_register_flag "add" "ip" "i" "127.0.0.1" "local loop ip" "string" "true"


cli_add_func(){
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
    cat >> /etc/hosts << EOF
$ip $host
EOF
    echo "$ip $host added."
}
#### cli add func end

#### cli del func begin
