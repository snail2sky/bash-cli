#!/bin/bash

##### load bash-cli library
source $(dirname $0)/../bash-cli.sh


##### cli register begin
#### cli root cmd register begin
cli_register_command \
    "" \
    "cli_root_func" \
    "A simple CLI tool example." \
    "This is a longer description of the root command, providing general information about the application." \
    "${CLI_TOOL_NAME} add"
#### cli root cmd register end

#### cli root.add cmd register begin
cli_register_command \
    "add" \
    "cli_add_func" \
    "add a host map of ip and host" \
    "add a host map of ip and host" \
    "${CLI_TOOL_NAME} add --host localhost --ip 127.0.0.1"

cli_register_flag "add" "host" "H" "localhost" "localhost domain name" "string" "true"
cli_register_flag "add" "ip" "i" "127.0.0.1" "local loop ip" "string" "true"
#### cli root.add cmd register end

#### cli root.del cmd register begin
cli_register_command \
    "del" \
    "cli_del_func" \
    "delete matched host map of ip and host" \
    "delete manthed host map of ip and host" \
    "${CLI_TOOL_NAME} del --host localhost --ip 127.0.0.1"

cli_register_flag "del" "host" "H" "localhost" "localhost domain name" "string" "true"
cli_register_flag "del" "ip" "i" "127.0.0.1" "local loop ip" "string" "true"
#### cli root.ddel cmd register end
##### cli register end


##### func begin

#### cli root func begin
cli_root_func() {
    __cli_print_help "root"
}
#### cli root func end

#### cli add func begin
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
#### cli add func end


#### lib func begin
id_check(){
    local uid=`id -u`
    if [ $uid -eq 0 ]; then
        return 0
    fi
    return 1
}

ip_check(){
    local ip=$1
    echo $ip | grep -Eq '([0-9]{1,3}\.){3}[0-9]{1,3}'
    if [ $? -eq 0 ]; then
        return 0
    fi
    return 1
}

#### lib func end


# --- Run the CLI ---
cli_run "$@"
