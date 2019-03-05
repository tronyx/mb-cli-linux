#!/usr/bin/env bash
#
# Script to setup/configure MediaButler.
# Tronyx
set -eo pipefail
IFS=$'\n\t'

# Define variables
mbLoginURL='https://auth.mediabutler.io/login'
mbDiscoverURL='https://auth.mediabutler.io/login/discover'
mbClientID='MB-Client-Identifier: 4d656446-fbe7-4545-b754-1adfb8eb554e'
mbClientIDShort='4d656446-fbe7-4545-b754-1adfb8eb554e'
# Set initial Plex credentials status
plexCredsStatus='invalid'
# Set initial Tautulli credentials status
tautulliURLStatus='invalid'
tautulliAPIKeyStatus='invalid'

# Define temp dir and files
tempDir='/tmp/mb_setup/'
plexCredsFile="${tempDir}plex_creds_check.txt"
plexServersFile="${tempDir}plex_server_list.txt"
numberedPlexServersFile="${tempDir}numbered_plex_server_list.txt"
tautulliConfigFile="${tempDir}tautulli_config.txt"
sonarrConfigFile="${tempDir}sonarr_config.txt"
sonarr4KConfigFile="${tempDir}sonarr4k_config.txt"
radarrConfigFile="${tempDir}radarr_config.txt"
radarr4KConfigFile="${tempDir}radarr4k_config.txt"
radarr3DConfigFile="${tempDir}radarr3d_config.txt"

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
#usage() {
#    cat <<- EOF
#
#  Usage: $(echo -e "${lorg}./$0${endColor}")
#
#EOF
#
#}

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
    echo -e "${ylw}Doing it for you now...${endColor}"
    echo ''
    sudo bash "${scriptname:-}" "${args[@]:-}"
    exit
  fi
}

# Function to determine which Package Manager to use
package_manager() {
  declare -A osInfo;
  osInfo[/etc/redhat-release]='yum -y -q'
  osInfo[/etc/arch-release]=pacman
  osInfo[/etc/gentoo-release]=emerge
  osInfo[/etc/SuSE-release]=zypp
  osInfo[/etc/debian_version]='apt-get -y -qq'
  osInfo[/etc/alpine-release]='apk'
  osInfo[/System/Library/CoreServices/SystemVersion.plist]='mac'

  for f in "${!osInfo[@]}"
    do
      if [[ -f $f ]];then
        packageManager=${osInfo[$f]}
      fi
    done
}

# Function to check if cURL is installed and, if not, install it
check_curl() {
  whichCURL=$(which curl)
  if [ -z "${whichCURL}" ]; then
    echo -e "${red}cURL is not currently installed!${endColor}"
    echo -e "${ylw}Doing it for you now...${endColor}"
    if [ "${packageManager}" = 'apk' ]; then
      apk add --no-cache curl
    elif [ "$[packageManager]" = 'mac' ]; then
      /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" && /usr/local/bin/brew install jq
    else
      "${packageManager}" install curl
    fi
  else
    :
  fi
  whichCURL=$(which curl)
  if [ -z "${whichCURL}" ]; then
    echo -e "${red}We tried, and failed, to install cURL!${endColor}"
    exit 1
  else
    :
  fi
}

# Function to check if JQ is installed and, if not, install it
check_jq() {
  whichJQ=$(which jq)
  if [ -z "${whichJQ}" ]; then
    echo -e "${red}JQ is not currently installed!${endColor}"
    echo -e "${ylw}Doing it for you now...${endColor}"
    if [ "${packageManager}" = 'apk' ]; then
      apk add --no-cache jq
    elif [ "$[packageManager]" = 'mac' ]; then
      /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" && /usr/local/bin/brew install jq
    else
      "${packageManager}" install jq
    fi
  else
    :
  fi
  whichJQ=$(which jq)
  if [ -z "${whichJQ}" ]; then
    echo -e "${red}We tried, and failed, to install JQ!${endColor}"
    exit 1
  else
    :
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
#trap 'cleanup' 0 1 3 6 14 15

# Exit the script if the user hits CTRL+C
function control_c() {
    #cleanup
    exit
}
trap 'control_c' 2

# Grab status variable line numbers
get_line_numbers() {
  plexCredsStatusLineNum=$(head -50 "${scriptname}" |grep -En -A1 'Set initial Plex credentials status' |tail -1 | awk -F- '{print $1}')
  tautulliURLStatusLineNum=$(head -50 "${scriptname}" |grep -En -A2 'Set initial Tautulli credentials status' |grep URL |awk -F- '{print $1}')
  tautulliAPIKeyStatusLineNum=$(head -50 "${scriptname}" |grep -En -A2 'Set initial Tautulli credentials status' |grep API |awk -F- '{print $1}')
}

# Function to prompt user for Plex credentials or token
get_plex_creds() {
  echo 'Welcome to the MediaButler setup utility!'
  echo 'First thing we need are your Plex credentials so please choose from one of the following options:'
  echo ''
  echo '1) Plex Username & Password'
  echo '2) Plex Auth Token'
  echo ''
  read -rp 'Enter your option: ' plexCredsOption
  if [ "${plexCredsOption}" == '1' ]; then
    echo 'Please enter your Plex username:'
    read -r plexUsername
    echo 'Please enter your Plex password:'
    read -rs plexPassword
    echo ''
  elif [ "${plexCredsOption}" == '2' ]; then
    echo 'Please enter your Plex token:'
    read -rs plexToken
    echo ''
  else
    echo 'You provided an invalid option, please try again.'
    exit 1
  fi
}

# Function to check that the provided Plex credentials are valid
check_plex_creds() {
  echo "Now we're going to make sure you provided valid credentials..."
  while [ "${plexCredsStatus}" = 'invalid' ]; do
    if [ "${plexCredsOption}" == '1' ]; then
      curl -s --location --request POST "${mbLoginURL}" \
      -H "${mbClientID}" \
      --data "username=${plexUsername}&password=${plexPassword}" |jq . > "${plexCredsFile}"
      authResponse=$(jq .name "${plexCredsFile}" |tr -d '"')
      if [[ "${authResponse}" =~ 'BadRequest' ]]; then
        echo -e "${red}The credentials that you provided are not valid!${endColor}"
        echo ''
        echo 'Please enter your Plex username:'
        read -r plexUsername
        echo 'Please enter your Plex password:'
        read -rs plexPassword
      elif [[ "${authResponse}" != *'BadRequest'* ]]; then
        sed -i'' "${plexCredsStatusLineNum} s/plexCredsStatus='[^']*'/plexCredsStatus='ok'/" "${scriptname}"
        plexCredsStatus='ok'
        echo -e "${grn}Success!${endColor}"
      fi
    elif [ "${plexCredsOption}" == '2' ]; then
      curl -s --location --request POST "${mbLoginURL}" \
      -H "${mbClientID}" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data "authToken=${plexToken}" |jq . > "${plexCredsFile}"
      authResponse=$(jq .name "${plexCredsFile}" |tr -d '"')
      if [[ "${authResponse}" =~ 'BadRequest' ]]; then
        echo -e "${red}The credentials that you provided are not valid!${endColor}"
        echo ''
        echo 'Please enter your Plex token:'
        read -rs plexToken
      elif [[ "${authResponse}" != *'BadRequest'* ]]; then
        sed -i'' "${plexCredsStatusLineNum} s/plexCredsStatus='[^']*'/plexCredsStatus='ok'/" "${scriptname}"
        plexCredsStatus='ok'
      fi
    fi
  done
}

# Function to get user's Plex token
get_plex_token() {
  if [ "${plexCredsOption}" == '1' ]; then
    plexToken=$(curl -s -X "POST" "https://plex.tv/users/sign_in.json" \
      -H "X-Plex-Version: 1.0.0" \
      -H "X-Plex-Product: MediaButler" \
      -H "X-Plex-Client-Identifier: ${mbClientIDShort}" \
      -H "Content-Type: application/x-www-form-urlencoded; charset=utf-8" \
      --data-urlencode "user[password]=${plexPassword}" \
      --data-urlencode "user[login]=${plexUsername}" |jq .user.authToken |tr -d '"')
  elif [ "${plexCredsOption}" == '2' ]; then
    :
  fi
}

# Function to create list of Plex servers
create_plex_servers_list() {
  jq .servers[].name "${plexCredsFile}" |tr -d '"' > "${plexServersFile}"
  IFS=$'\r\n' GLOBIGNORE='*' command eval 'plexServers=($(cat "${plexServersFile}"))'
  for ((i = 0; i < ${#plexServers[@]}; ++i)); do
    position=$(( $i + 1 ))
    echo "$position) ${plexServers[$i]}"
  done > "${numberedPlexServersFile}"
}

# Function to prompt user to select Plex Server from list and retrieve user's MediaButler URL
prompt_for_plex_server() {
  numberOfOptions=$(echo "${#plexServers[@]}")
  echo 'Please choose which Plex Server you would like to setup MediaButler for:'
  echo ''
  cat "${numberedPlexServersFile}"
  read -p "Server (1 - ${numberOfOptions}):" plexServerSelection
  echo ''
  echo 'Gathering required information...'
  echo ''
  plexServerArrayElement=$((${plexServerSelection}-1))
  selectedPlexServerName=$(jq .servers["${plexServerArrayElement}"].name "${plexCredsFile}" |tr -d '"')
  plexServerMachineID=$(jq .servers["${plexServerArrayElement}"].machineId "${plexCredsFile}" |tr -d '"')
  userMBURL=$(curl -s --location --request POST "${mbDiscoverURL}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "${mbClientID}" \
    --data "authToken=${plexToken}&machineId=${plexServerMachineID}")
  plexServerMBToken=$(jq .servers["${plexServerArrayElement}"].token "${plexCredsFile}" |tr -d '"')
  echo -e "${grn}Done!${endColor}"
  echo ''
  echo 'Is this the correct MediaButler URL?'
  echo -e "${ylw}${userMBURL}${endColor}"
  echo ''
  echo -e "${grn}[Y]${endColor}es or ${red}[N]${endColor}o):"
  read -r mbURLConfirmation
  echo ''
  if ! [[ "${mbURLConfirmation}" =~ ^(yes|y|no|n)$ ]]; then
    echo -e "${red}Please specify yes, y, no, or n.${endColor}"
  elif [[ "${mbURLConfirmation}" =~ ^(yes|y)$ ]]; then
    :
  elif [[ "${mbURLConfirmation}" =~ ^(no|n)$ ]]; then
    echo 'Please enter the correct MediaButler URL:'
    read -r userMBURL
  fi
}

# Function to exit the menu
exit_menu() {
  echo 'This will exit the program and any unfinished config setup will be lost.'
  echo 'Are you sure you wish to exit?'
  read -rp "${grn}[Y]${endColor}es or ${red}[N]${endColor}o):" exitPrompt
  if ! [[ "${exitPrompt}" =~ ^(yes|y|no|n)$ ]]; then
    echo -e "${red}Please specify yes, y, no, or n.${endColor}"
  elif [[ "${exitPrompt}" =~ ^(yes|y)$ ]]; then
    exit 0
  elif [[ "${exitPrompt}" =~ ^(no|n)$ ]]; then
    main_menu
  fi
}

# Function to display the main menu
main_menu(){
  echo '*****************************************'
  echo '*               Main Menu               *'
  echo '*****************************************'
  echo 'Please choose which application you would'
  echo '   like to configure for MediaButler:    '
  echo ''
  echo '1) Sonarr'
  echo '2) Radarr'
  echo '3) Tautulli'
  echo '4) Exit'
  echo ''
  read -rp 'Selection: ' mainMenuSelection
}

# Function to display the Sonarr sub-menu
sonarr_menu() {
  echo '*****************************************'
  echo '*           Sonarr Setup Menu           *'
  echo '*****************************************'
  echo 'Please choose which version of Radarr you'
  echo 'would like to configure for MediaButler: '
  echo ''
  echo '1) Sonarr'
  echo '2) Sonarr 4K'
  echo '3) Back to Main Menu'
  echo ''
  read -rp sonarrMenuSelection
  if ! [[ "${sonarrMenuSelection}" =~ ^(1|2|3)$ ]]; then
    echo -e "${red}You did not specify a valid option!${endColor}"
    sonarr_menu
  elif [[ "${sonarrMenuSelection}" =~ ^(1|2)$ ]]; then
    sonarr_setup
  elif [ "${sonarrMenuSelection}" = '3' ]; then
    main_menu
  fi
}

# Function to display the Radarr sub-menu
radarr_menu() {
  echo '*****************************************'
  echo '*           Radarr Setup Menu           *'
  echo '*****************************************'
  echo 'Please choose which version of Radarr you'
  echo 'would like to configure for MediaButler: '
  echo ''
  echo '1) Radarr'
  echo '2) Radarr 4K'
  echo '3) Radarr 3D'
  echo '4) Back to Main Menu'
  echo ''
  read -rp radarrMenuSelection
  if ! [[ "${radarrMenuSelection}" =~ ^(1|2|3|4)$ ]]; then
    echo -e "${red}You did not specify a valid option!${endColor}"
    radarr_menu
  elif [[ "${radarrMenuSelection}" =~ ^(1|2|3)$ ]]; then
    radarr_setup
  elif [ "${radarrMenuSelection}" = '4' ]; then
    main_menu
  fi
}

# Function to process Sonarr configuration
setup_sonarr() {
  curl -s -X GET 'http://192.168.1.103:9898/sonarr/api/profile' -H 'X-Api-Key: ccf949b82b0a4b6f99a0949f35e37b88' |jq .[].name
  curl -s -X GET 'http://192.168.1.103:9898/sonarr/api/rootfolder' -H 'X-Api-Key: ccf949b82b0a4b6f99a0949f35e37b88' |jq .[].path
}

# Function to process Radarr configuration
setup_radarr() {
  curl -s -X GET 'http://192.168.1.103:7878/radarr/api/profile' -H 'X-Api-Key: 15bba08182544413a4d55c5b19868d9c' |jq .[].name
  curl -s -X GET 'http://192.168.1.103:7878/radarr/api/rootfolder' -H 'X-Api-Key: 15bba08182544413a4d55c5b19868d9c' |jq .[].path
}

# Function to process Tautulli configuration
setup_tautulli() {
  echo 'Please enter your Tautulli URL (IE: http://127.0.0.1:8181/tautulli/):'
  read -r tautulliURL
  echo ''
  echo 'Checking that the provided Tautulli URL is valid...'
  if [[ "${tautulliURL: -1}" = '/' ]]; then
    convertedTautulliURL=$(echo "${tautulliURL}")
  elif [[ "${tautulliURL: -1}" != '/' ]]; then
    convertedTautulliURL=$(tautulliURL+=\/; echo "${tautulliURL}")
  fi
  tautulliURLCheckResponse=$(curl -sI "${convertedTautulliURL}"auth/login |grep HTTP |awk '{print $2}')
  while [ "${tautulliURLStatus}" = 'invalid' ]; do
    if [ "${tautulliURLCheckResponse}" = '200' ]; then
      sed -i'' "${tautulliURLStatusLineNum} s/tautulliURLStatus='[^']*'/tautulliURLStatus='ok'/" "${scriptname}"
      tautulliURLStatus='ok'
      echo -e "${grn}Success!${endColor}"
    elif [ "${tautulliURLCheckResponse}" = '200' ]; then
      echo -e "${red}Received something other than a 200 OK response!${endColor}"
      echo 'Please enter your Tautulli URL (IE: http://127.0.0.1:8181/tautulli/):'
      read -r tautulliURL
      echo ''
    fi
  done
  echo 'Please enter your Tautulli API key:'
  read -r tautulliAPIKey
  echo ''
  echo 'Testing that the provided Tautulli API Key is valid...'
  tautulliAPITestResponse=$(curl -s "${convertedTautulliURL}api/v2?apikey=${tautulliAPIKey}&cmd=arnold" |jq .response.message |tr -d '"')
  while [ "${tautulliAPIKeyStatus}" = 'invalid' ]; do
    if [ "${tautulliAPITestResponse}" = 'null' ]; then
      sed -i'' "${tautulliAPIKeyStatusLineNum} s/tautulliAPIKeyStatus='[^']*'/tautulliAPIKeyStatus='ok'/" "${scriptname}"
      tautulliAPIKeyStatus='ok'
      echo -e "${grn}Success!${endColor}"
    elif [ "${tautulliAPITestResponse}" = 'Invalid apikey' ]; then
      echo -e "${red}Received something other than an OK response!${endColor}"
      echo 'Please enter your Tautulli API Key:'
      read -r tautulliAPIKey
      echo ''
    fi
  done
  echo 'Testing the full Tautulli config for MediaButler...'
  JSONConvertedTautulliURL=$(echo "${tautulliURL}" |sed 's/:/%3A/g')
  curl -s --location --request PUT "${userMBURL}configure/tautulli?" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "${mbClientID}" \
  -H "Authorization: Bearer ${plexServerMBToken}" \
  --data "url=${JSONConvertedTautulliURL}&apikey=${tautulliAPIKey}" |jq . > "${tautulliConfigFile}"
  tautulliMBConfigTestResponse=$(cat "${tautulliConfigFile}" |jq .message |tr -d '"')
  if [ "${tautulliMBConfigTestResponse}" = 'success' ]; then
    echo -e "${grn}Success!${endColor}"
    echo ''
    echo 'Saving the Tautulli config to MediaButler...'
    curl -s --location --request POST "${userMBURL}configure/tautulli?" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "${mbClientID}" \
    -H "Authorization: Bearer ${plexServerMBToken}" \
    --data "url=${JSONConvertedTautulliURL}&apikey=${tautulliAPIKey}" |jq . > "${tautulliConfigFile}"
    tautulliMBConfigPostResponse=$(cat "${tautulliConfigFile}" |jq .message |tr -d '"')
    if [ "${tautulliMBConfigPostResponse}" = 'success' ]; then
      echo -e "${grn}Done! Tautulli has been successfully configured for${endColor}"
      echo -e "${grn}MediaButler with the ${selectedPlexServerName} Plex server.${endColor}"
      sleep 3
      echo 'Returning you to the Main Menu...'
      main_menu
    elif [ "${tautulliMBConfigPostResponse}" != 'success' ]; then
      echo -e "${red}Config push failed! Please try again later.${endColor}"
      sleep 3
      main_menu
    fi
  elif [ "${tautulliMBConfigTestResponse}" != 'success' ]; then
    echo -e "${red}Hmm, something weird happened. Please try again."
    sleep 3
    main_menu
  fi
}

# Main function to run all functions
main() {
  root_check
  package_manager
  check_curl
  check_jq
  create_dir
  get_line_numbers
  get_plex_creds
  check_plex_creds
  get_plex_token
  create_plex_servers_list
  prompt_for_plex_server
  main_menu
  if ! [[ "${mainMenuSelection}" =~ ^(1|2|3|4)$ ]]; then
    echo -e "${red}You did not specify a valid option!${endColor}"
    main_menu
  elif [ "${mainMenuSelection}" = '1' ]; then
    sonarr_menu
  elif [ "${mainMenuSelection}" = '2' ]; then
    radarr_menu
  elif [ "${mainMenuSelection}" = '3' ]; then
    setup_tautulli
  elif [ "${mainMenuSelection}" = '4' ]; then
    exit_menu
  fi
}

main
