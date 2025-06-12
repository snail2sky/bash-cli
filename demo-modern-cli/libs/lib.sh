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
