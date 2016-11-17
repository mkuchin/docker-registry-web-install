#!/bin/bash
#
# # Coding conventions
#
# * globals are `like_this`.
# * locals are `_like_this`.
# * exported values are `LIKE_THIS`.
# * out-of-band return values are put into `RETVAL`.

set -u # Undefined variables are errors

main() {
    [[ $# -eq 0 ]] && usage
#    assert_cmnds
    set_globals "$1"
    original
}

usage() {
    printf "Usage: %s <domain name>\n" $0 
    exit 1
}

set_globals() {
    local _pwd=$(pwd)
    domain=$1
    
    dehydrated_dir=config/dehydrated
    www_dir=config/temp/var/www
    nginx_stage1_dir=config/temp/nginx/conf.d

    script=$( cd $(dirname $0) ; pwd -P )
    install_dir=${DRW_INSTALL_ROOT:-$_pwd}
    
    assert_nz $script
    assert_nz $install_dir
}

generate_config() {
  local _template_name=$1
  local _config_name=$2
  cat templates/$_template_name | sed -e "s/{{domain}}/$domain/"  > $_config_name
}


original () {
    # check if docker installed
    docker -v >/dev/null 2>&1 || { echo >&2 "Docker required but it's not installed.  Aborting."; exit 1; }
    #docker-compose -v >/dev/null 2>&1 || { echo >&2 "docker-compose required but it's not installed.  Aborting."; exit 1; }
    #todo: check docker and compose versions

    if [[  -z  $1  ]]; then
        read -p "Enter domain name of the host: " domain
    fi
    echo Domain=$domain

    mkdir -p $nginx_stage1_dir
    mkdir -p $www_dir/dehydrated

    generate_config nginx-stage1.cfg $nginx_stage1_dir/default.conf

    docker run -p 80:80 -v $(pwd)/$www_dir:/var/www -v $(pwd)/$nginx_stage1_dir:/etc/nginx/conf.d -d --name nginx nginx

    echo $domain > $www_dir/domain.txt
    echo Checking domain...
    sleep 1
    response=$(curl -s $domain/domain.txt)
    if [ "$domain" != "$response" ]; then
        echo "Domain check failed, check if DNS record exist!"
        exit 1
    else
        echo "...OK"
    fi

    echo Generating ssl certificate
    mkdir -p $dehydrated_dir
    touch $dehydrated_dir/config
    #staging url
    echo CA="https://acme-staging.api.letsencrypt.org/directory" > $dehydrated_dir/config
    echo $domain > $dehydrated_dir/domains.txt
    sleep 1
    docker run --rm -v $(pwd)/$dehydrated_dir:/etc/dehydrated -v $(pwd)/$www_dir:/var/www  hyper/dehydrated -c
    docker rm -f nginx

    mkdir -p config/nginx
    mkdir config/registry
    mkdir config/registry-web

    generate_config stage2/conf/nginx/default.conf.tmpl config/nginx/default.conf
    generate_config stage2/conf/registry/config.yml.tmpl config/registry/config.yml
    generate_config stage2/conf/registry-web/config.yml.tmpl config/registry-web/config.yml

    mkdir config/etc
    cp templates/stage2/docker-compose.yml config/
    cd config

    openssl req \
    -new \
    -newkey rsa:4096 \
    -days 365 \
    -subj "/CN=localhost" \
    -nodes \
    -x509 \
    -keyout registry-web/auth.key \
    -out registry/auth.cert

    echo Installing docker-compose
    curl -L "https://github.com/docker/compose/releases/download/1.8.1/docker-compose-$(uname -s)-$(uname -m)" > /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    sleep 1
    docker-compose up
}

# Standard utilities
# # Reference: rustup.sh (https://www.rust-lang.org)

say() {
    echo "rustup: $1"
}

say_err() {
    say "$1" >&2
}

verbose_say() {
    if [ "$flag_verbose" = true ]; then
	say "$1"
    fi
}

err() {
    say "$1" >&2
    exit 1
}

need_cmd() {
    if ! command -v "$1" > /dev/null 2>&1
    then err "need '$1' (command not found)"
    fi
}

need_ok() {
    if [ $? != 0 ]; then err "$1"; fi
}

assert_nz() {
    if [ -z "$1" ]; then err "assert_nz $2"; fi
}

# Run a command that should never fail. If the command fails execution
# will immediately terminate with an error showing the failing
# command.
ensure() {
    "$@"
    need_ok "command failed: $*"
}

# This is just for indicating that commands' results are being
# intentionally ignored. Usually, because it's being executed
# as part of error handling.
ignore() {
    run "$@"
}

# Runs a command and prints it to stderr if it fails.
run() {
    "$@"
    local _retval=$?
    if [ $_retval != 0 ]; then
	say_err "command failed: $*"
    fi
    return $_retval
}

# Prints the absolute path of a directory to stdout
abs_path() {
    local _path="$1"
    # Unset CDPATH because it causes havok: it makes the destination unpredictable
    # and triggers 'cd' to print the path to stdout. Route `cd`'s output to /dev/null
    # for good measure.
    (unset CDPATH && cd "$_path" > /dev/null && pwd)
}
#
#assert_cmds() {
#    need_cmd dirname
# }

main "$@"
