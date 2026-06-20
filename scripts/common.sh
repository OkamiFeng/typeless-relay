#!/bin/sh

validate_port() {
    case "${1-}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

read_config_port() {
    config_file=$1
    [ -f "$config_file" ] || return 1
    config_port=$(awk -F= '$1 == "SOCKS_PORT" { print $2; exit }' "$config_file")
    validate_port "$config_port" || return 1
    printf '%s\n' "$config_port"
}

write_config() {
    config_file=$1
    config_port=$2
    validate_port "$config_port" || return 1
    config_dir=$(dirname -- "$config_file")
    mkdir -p "$config_dir"
    config_temp=$(mktemp "$config_dir/.typeless-relay.conf.XXXXXX")
    printf 'SOCKS_PORT=%s\n' "$config_port" > "$config_temp"
    chmod 644 "$config_temp"
    if ! mv -f "$config_temp" "$config_file"; then
        rm -f "$config_temp"
        return 1
    fi
}

render_plist() {
    plist_template=$1
    plist_destination=$2
    plist_port=$3
    validate_port "$plist_port" || return 1
    sed "s/__SOCKS_PORT__/$plist_port/g" "$plist_template" > "$plist_destination"
}
