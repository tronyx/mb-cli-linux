#!/usr/bin/env bash
#
# Script to setup/configure MediaButler.
# Tronyx
set -eo pipefail
IFS=$'\n\t'

# Define variables
mbLoginURL='https://auth.mediabutler.io/login'
mbClientID='MB-Client-Identifier: 4d656446-fbe7-4545-b754-1adfb8eb554e'
# Set initial Plex credentials status
plexCredsStatus='invalid'

# Define temp dir and files
tempDir='/tmp/mb_setup/'
plexCredsFile="${tempDir}plex_creds_check.txt"
plexServersFile="${tempDir}plex_server_list.txt"
numberedPlexServersFile="${tempDir}numbered_plex_server_list.txt"

# Define text colors
readonly blu='\e[34m'
readonly lblu='\e[94m'
readonly grn='\e[32m'
readonly red='\e[31m'
readonly ylw='\e[33m'
readonly org='\e[38;5;202m'
readonly lorg='\e[38;5;130m'
readonly mgt='\e[35m'
readonly endColor='\e[0m'

# Define usage
usage() {
    cat <<- EOF

  Usage: $(echo -e "${lorg}./$0${endColor}")

EOF

}

# Script Information
get_scriptname() {
    local source
    local dir
    source="${BASH_SOURCE[0]}"
    while [[ -L ${source} ]]; do
        dir="$(cd -P "$(dirname "${source}")" > /dev/null && pwd)"
        source="$(readlink "${source}")"
        [[ ${source} != /* ]] && source="${dir}/${source}"
    done
    echo "${source}"
}

readonly scriptname="$(get_scriptname)"
readonly scriptpath="$(cd -P "$(dirname "${scriptname}")" > /dev/null && pwd)"

# Check whether or not user is root or used sudo
root_check() {
    if [[ ${EUID} -ne 0 ]]; then
        echo -e "${red}You didn't run the script as root!${endColor}"
        echo -e "${red}Doing it for you now...${endColor}"
        echo ''
        sudo bash "${scriptname:-}" "${args[@]:-}"
        exit
    fi
}

# Create directory to neatly store temp files
create_dir() {
    mkdir -p "${tempDir}"
    chmod 777 "${tempDir}"
}

# Cleanup temp files
cleanup() {
    rm -rf "${tempDir}"*.txt || true
}
trap 'cleanup' 0 1 3 6 14 15

# Exit the script if the user hits CTRL+C
function control_c() {
    #cleanup
    exit
}
trap 'control_c' 2

# Grab status variable line numbers
get_line_numbers() {
  plexCredsStatusLineNum=$(head -50 "${scriptname}" | grep -En -A1 'Set initial Plex credentials status' | tail -1 | awk -F- '{print $1}')
}

# Function to prompt user for Plex credentials or token
get_plex_creds() {
  echo 'Welcome to the MediaButler setup utility!'
  echo 'First thing we need are your Plex credentials so please choose from one of the following options:'
  echo ''
  echo '1) Plex username & password'
  echo '2) Plex token'
  echo ''
  read -rp 'Enter your option: ' plex_creds_option
  if [ "${plex_creds_option}" == '1' ]; then
    echo 'Please enter your Plex username:'
    read -r plex_username
    echo 'Please enter your Plex password:'
    read -rs plex_password
  elif [ "${plex_creds_option}" == '2' ]; then
    echo 'Please enter your Plex token:'
    read -rs plex_token
  else
    echo 'You provided an invalid option, please try again.'
    exit 1
  fi
}

# Function to check that the provided Plex credentials are valid
check_plex_creds() {
  echo "Now we're going to make sure you provided valid credentials..."
  while [ "${plexCredsStatus}" = 'invalid' ]; do
    if [ "${plex_creds_option}" == '1' ]; then
      curl -s --location --request POST "${mbLoginURL}" \
      --header "${mbClientID}" \
      --data "username=${plex_username}&password=${plex_password}" |jq . > "${plexCredsFile}"
      authResponse=$(grep -Po '"name":.*?[^\\]",' "${plexCredsFile}" |cut -c9- |tr -d '",')
      if [[ "${authResponse}" =~ 'BadRequest' ]]; then
        echo -e "${red}The credentials that you provided are not valid!${endColor}"
        echo ''
        echo 'Please enter your Plex username:'
        read -r plex_username
        echo 'Please enter your Plex password:'
        read -rs plex_password
      elif [[ "${authResponse}" != *'BadRequest'* ]]; then
        sed -i "${plexCredsStatusLineNum} s/plexCredsStatus='[^']*'/plexCredsStatus='ok'/" "${scriptname}"
        plexCredsStatus='ok'
      fi
    elif [ "${plex_creds_option}" == '2' ]; then
      curl -s --location --request POST "${mbLoginURL}" \
      --header "${mbClientID}" \
      --header "Content-Type: application/x-www-form-urlencoded" \
      --data "authToken=${plex_token}" |jq . > "${plexCredsFile}"
      authResponse=$(grep -Po '"name":.*?[^\\]",' "${plexCredsFile}" |cut -c9- |tr -d '",')
      if [[ "${authResponse}" =~ 'BadRequest' ]]; then
        echo -e "${red}The credentials that you provided are not valid!${endColor}"
        echo ''
        echo 'Please enter your Plex token:'
        read -rs plex_token
      elif [[ "${authResponse}" != *'BadRequest'* ]]; then
        sed -i "${plexCredsStatusLineNum} s/plexCredsStatus='[^']*'/plexCredsStatus='ok'/" "${scriptname}"
        plexCredsStatus='ok'
      fi
    fi
  done
}

# Function to create list of Plex servers
create_plex_servers_list() {
  grep -Po '"name":.*?[^\\]",' "${plexCredsFile}" |cut -c9- |tr -d '",' > "${plexServersFile}"
  IFS=$'\r\n' GLOBIGNORE='*' command eval 'plexServers=($(cat "${plexServersFile}"))'
  for ((i = 0; i < ${#plexServers[@]}; ++i)); do
    position=$(( $i + 1 ))
    echo "$position) ${plexServers[$i]}"
  done > "${numberedPlexServersFile}"
}

# Function to prompt user to select Plex Server from list
prompt_for_plex_server() {
  numberOfOptions=$(echo "${#plexServers[@]}")
  echo 'Please choose which Plex Server you would like to setup MediaButler for:'
  cat "${numberedPlexServersFile}"
  read -p "Server (1 - ${numberOfOptions}):" plexServerSelection
  selectedPlexServerName=$(sed "${plexServerSelection}q;d" |awk '{$1=""; print $0}' |cut -c2-)
}

# Main function to run all functions
main() {
  root_check
  create_dir
  get_line_numbers
  get_plex_creds
  check_plex_creds
  create_plex_servers_list
  prompt_for_plex_server
}

main
