#
# # Coding conventions
#
# * globals are `like_this`.
# * locals are `_like_this`.
# * exported values are `LIKE_THIS`.
# * out-of-band return values are put into `RETVAL`.

set -u # Undefined variables are errors

main() {
    assert_cmds
    set_globals
    original "$@"
}

set_globals() {

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

    domain=$1
    if [[  -z  $1  ]]; then
        read -p "Enter domain name of the host: " domain
    fi
    echo Domain=$domain

    mkdir -p etc/nginx/conf.d
    mkdir  -p var/www

    generate_config nginx-stage1.cfg etc/nginx/conf.d/default.conf

    docker run -p 80:80 -v $(pwd)/var/www:/var/www -v $(pwd)/etc/nginx/conf.d:/etc/nginx/conf.d -d --name nginx nginx

    echo $domain > var/www/domain.txt
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
    mkdir etc/dehydrated
    mkdir var/www/dehydrated
    touch etc/dehydrated/config
    #echo  WELLKNOWN="$(pwd)/nginx/www/dehydrated" > /etc/dehydrated/config
    #staging url
    #echo CA="https://acme-staging.api.letsencrypt.org/directory" > /etc/dehydrated/config
    echo $domain > etc/dehydrated/domains.txt
    sleep 1
    docker run --rm -v $(pwd)/etc/dehydrated:/etc/dehydrated -v $(pwd)/var/www:/var/www  hyper/dehydrated -c
    docker rm -f nginx

    mkdir config

#    cat config/stage2/conf/nginx/default.conf.tmpl | sed -e "s/{{domain}}/$domain/"  > config/stage2/conf/nginx/default.conf
    generate_config stage2/conf/nginx/default.conf.tmpl config/nginx/default.conf
#    cat config/stage2/conf/registry/config.yml.tmpl | sed -e "s/{{domain}}/$domain/" > config/stage2/conf/registry/config.yml
    generate_config stage2/conf/registry/config.yml.tmpl config/stage2/conf/registry/config.yml

#    cat config/stage2/conf/registry-web/config.yml.tmpl | sed -e "s/{{domain}}/$domain/" > config/stage2/conf/registry-web/config.yml
    generate_config stage2/conf/registry-web/config.yml.tmpl config/registry-web/config.yml

    exit 1
    mkdir config/stage2/etc
    ln -s $(pwd)/etc/dehydrated config/stage2/etc/dehydrated
    cd config/stage2/
    ./generate-keys.sh
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

assert_cmds() {
#    need_cmd dirname
}

main "$@"
