#!/usr/bin/env bash

# Author : Bobby Valenzuela
# Created : 16th Septemper 2024

# Description:
# List all of the available hosts in your SSH config file and select one to connect to from numbered list.

# Requires 'jq' 
# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq is not installed. Installing..."
    sudo apt update
    sudo apt install -y jq
fi


#############################################################################
# =========== CONFIG ===========
# Enter your path details here:

# Root directory where all of your local git repos reside
LOCAL_ROOT='/home/bobby/pbx/'

# Root directory where all of your local git repos reside
REMOTE_ROOT='/home/control-io/'

# Method: Git|Rsync
SYNC_METHOD='Rsync'

# Define dirs to sync (dir must be the same on both local/remote)
JSON='[
    {
      "hostname":"alpha",
      "dir":"_custom_scripts"
    },
    {
      "hostname":"alpha",
      "dir":"api"
    },
    {
      "hostname":"alpha",
      "dir":"biltong-server"
    },
    {
      "hostname":"alpha",
      "dir":"www"
    },
    {
      "hostname":"alpha",
      "dir":"cloudprograms"
    },
    {
      "hostname":"alpha",
      "dir":"cloudside-commonfiles-v1"
    },
    {
      "hostname":"alpha",
      "dir":"control"
    },
    {
      "hostname":"alpha",
      "dir":"internal-api"
    },
    {
      "hostname":"alpha",
      "dir":"metabase-tools"
    },
    {
      "hostname":"alpha",
      "dir":"scout"
    },
    {
      "hostname":"alpha",
      "dir":"thincontroller"
    },
    {
      "hostname":"alpha",
      "dir":"vccprograms"
    },
    {
      "hostname":"alpha",
      "dir":"dropboxv2"
    },
    {
      "hostname":"alpha",
      "dir":"vccuserupdate"
    },
    {
      "hostname":"alpha",
      "dir":"voutlook365"
    }
]'


# ==== Additional customization ====
# 3 seconds per iteration
NAP_TIME=3

# SSH Confile file location (full location)
SSH_CONF=~/.ssh/config

# ======== END CONFIG ============
#############################################################################

# Checks for any arguments passed in
ARG1=$1
ARG2=$2

# If a single dot pased in then we are calling Gitsync from inside a repo in our list, only force this one. 
# This way we can just call `gitsync .` from inside a repo to sync (and optinally pass in a second arg as a commit msg).
if [[ "$ARG1" == '.' ]]; then

  PWD_DIR=$(basename $(pwd))
  ARG1="${LOCAL_ROOT}${PWD_DIR}"

elif [[  ! -z "$ARG1" ]]; then

  # Anything other than a dot must be the dir itself thats being forced
  ARG1="${LOCAL_ROOT}$ARG1"

fi

# Exit if no ssh config file
if [[ ! -e $SSH_CONF && "$1" != '--install-service' ]]; then
  echo "No file found at $SSH_CONF. Exiting!"
  exit
fi

# Define Associative arrays to hold file count/dir size info
unset local_dir_sizes
declare -A local_dir_sizes

unset local_dir_files
declare -A local_dir_files

unset local_branch
declare -A local_branch

unset ssh_info
declare -A ssh_info

### Start main loop
while :; do

  # Loop through the array using jq |
  # # Get JSON data outside of the loop to avoid subshell issues | This doesn't work => (echo "${JSON}" | jq -c '.[]' | while read obj; do)
  json_array=$(echo "${JSON}" | jq -c '.[]')

  for obj in ${json_array[@]}; do

    hostname=$(echo "$obj" | jq -r '.hostname')
    current_dir=$(echo "$obj" | jq -r '.dir')
    
    # Set proper local/remote paths``
    local="${LOCAL_ROOT}${current_dir}"
    remote="${REMOTE_ROOT}${current_dir}"

    # Skip if processing a manual Update and we're not on that repo
    if [[ ! -z "${ARG1}" && "${ARG1}" != "${local}" && "$1" != '--install-service' ]]; then
      echo "Exiting here 1 ($ARG1)"
      continue
    fi

    # If we're forcing an update and on Rsync, then second arg could be the hostname we want to force as well, if thats passed in, make sure we only process that host as well
    if [[ ! -z "${ARG1}" && ! -z "${ARG2}" && "${ARG2}" != ${hostname} && "$1" != '--install-service' ]]; then
      continue
    fi

    if [[ "$1" != '--install-service' ]]; then
      echo -e "\n[VALUES] Forced Dir: ${ARG1} | Method: ${SYNC_METHOD} | Local: ${local} | Remote: ${remote} | Host: ${hostname}" 
    fi
    
    # Skip if local dir doesn't exist
    [[ ! -d ${local} ]] && continue
    
    # Set any SSH vars if we're doing rsync
    # See if we already have details we can use for thi hosts
    if [[ ! -z "${ssh_info[${hostname}-user]}" ]]; then
      
        ssh_user="${ssh_info[${hostname}-user]}"
        ssh_hostname="${ssh_info[${hostname}-hostname]}"
        ssh_key="${ssh_info[${hostname}-key]}"
    else
        # Geth SSH file home
        # file_owner=$(stat -c '%U' "$SSH_CONF")
        
        # Find the home directory of the owner from /etc/passwd
        #user_home=$(getent passwd "$file_owner" | cut -d: -f6)

        # SSH key must have proper home (in case we're running this file as another user)
        #if [[ "${ssh_key}" == ~* ]]; then
        #  ssh_home=${SSH_CONF//\/\.ssh\/config/}
        #  ssh_key=${ssh_key//\~/$ssh_home}
        #fi

        # Check if ust installing service
        if [[ "$1" == '--install-service' ]]; then
        
            # Enforce sudo/root
            if [ "$(id -u)" -ne 0 ]; then
                echo "User is not running as root or with sudo. Exiting..."
                exit;
            fi

            read -p "Enter the user the ~/.ssh/config belongs to: " SERVICE_USER
            
            ssh_user=$(grep -E -A10 "${hostname}(\b|\r|n)" /home/${SERVICE_USER}/.ssh/config | sed -E '/^$/ q' | awk '/User/ { print $2 }')
            ssh_hostname=$(grep -E -A10 "${hostname}(\b|\r|n)" /home/${SERVICE_USER}/.ssh/config | sed -E '/^$/ q' | awk '/HostName/ { print $2 }')
            ssh_key=$(grep -E -A10 "${hostname}(\b|\r|n)" /home/${SERVICE_USER}/.ssh/config | sed -E '/^$/ q' | awk '/IdentityFile/ { print $2 }')
            
            PRGRM='reposync'
            SERVICE_UNITFILE=/etc/systemd/system/
            PROGRAM_LOCATION=$(which reposync)
            printf "[unit]\nDescription=Repo Sync Service\n[Service]\nUser\n${SERVICE_USER}\nExecStart=$PROGRAM_LOCATION" > $SERVICE_UNITFILE$PRGRM.service
            sudo chmod +x $PROGRAM_LOCATION
            sudo systemctl daemon-reload
            sudo systemctl start $PRGRM
            sudo systemctl status $PRGRM

            echo "Service installed!"
            exit

        else

            ssh_user=$(grep -E -A10 "${hostname}(\b|\r|n)" $SSH_CONF | sed -E '/^$/ q' | awk '/User/ { print $2 }')
            ssh_hostname=$(grep -E -A10 "${hostname}(\b|\r|n)" $SSH_CONF | sed -E '/^$/ q' | awk '/HostName/ { print $2 }')
            ssh_key=$(grep -E -A10 "${hostname}(\b|\r|n)" $SSH_CONF | sed -E '/^$/ q' | awk '/IdentityFile/ { print $2 }')
        
        fi




        # Save any SSH details in a var so we don't have to parse the confi file every time if we already have details for this host
        ssh_info["${hostname}-user"]=$ssh_user
        ssh_info["${hostname}-hostname"]=$ssh_hostname
        ssh_info["${hostname}-key"]=$ssh_key

    fi

    # Get current git branch
    current_branch=$(cd ${local} && git branch  | grep '*' | awk '{print $2}' | xargs)
    current_branch_remote=$(ssh ${hostname} -F ${SSH_CONF} -i ${ssh_key} "cd ${remote} && git branch 2>/dev/null | grep '*' | awk '{print \$2}' | xargs")

    # Skip if no branch found  or if master (only feature branches sync). Adding an exception for Rsync Method because we're not pushing any actual code to master in repo in this case.
    if [[ "${SYNC_METHOD}" != 'Rsync' ]]; then
        [[ -z "${current_branch}" || "${current_branch}" == 'master' || "${current_branch}" == 'main' ]]  && continue
    fi

    # Before continuing let's push what we have up
    if [[ -z "${ARG2}" ]]; then
      ARG2="Testing/Debugging"
    fi
   
    # If If git sync then commit any unsaved changes
    if [[ "${SYNC_METHOD}" != 'Rsync' ]]; then
      cd ${local} && git add -A && git commit -m "${ARG2}" && git push --set-upstream origin ${current_branch}
    fi

    # Replace any fwd-slashes with underscores
    local_escaped=$(printf ${local////_})

    # Now that we have all keys for this entry, lets check size changes to see if sync is needed
    current_size=$(du -bs ${local} | awk '{print $1}')
    current_num_of_files=$(ls -lR ${local} | wc -l)

    echo -e "\t[BRANCH] Current: ${current_branch} | LocalLastSaved: ${local_branch[${local_escaped}]}"

    # If no size set for this local dir or we switched branches
    if [[ -z "${local_dir_sizes[${local_escaped}]}" || "${current_branch}" != "${local_branch[${local_escaped}]}" ]]; then
    
      echo -e "\tUpdating Branches. Syncing remote..."
      local_dir_sizes[${local_escaped}]=${current_size}
      local_dir_files[${local_escaped}]=${current_num_of_files}
      local_branch[${local_escaped}]=${current_branch}

      # [Initial Steps] On remote machine:
      # - Pull down latest from master
      # - Check out branch (if not checked out)
      # - Pull down latest on that branch (if git sync) otherwise rsync
      
      # Run sync now
      if [[ "${SYNC_METHOD}" == 'Rsync' ]]; then

        if [[ "${current_branch}" == "${current_branch_remote}" ]]; then
          echo -e "\tRemote already on same branch - running rsync."
          rsync=$(rsync --delete-after --exclude "*.git" --info=progress2 -harvpE -e "ssh -i ${ssh_key}"  ${local}/ ${ssh_user}@${ssh_hostname}:${remote}/)
        else
          echo -e "\tRemote on different branch (${current_branch_remote}) While local is on (${current_branch}). Updating remote..."

          # Clean any untracked files and discard any unsaved changes - then create branch if needed
          ssh ${hostname} -F ${SSH_CONF} -i ${ssh_key} "cd ${remote} && git checkout -- . && git clean -fd && git checkout -- .  && git checkout -b ${current_branch}"

          # Checkout branch and clean up any untracked files
          ssh ${hostname} -F ${SSH_CONF} -i ${ssh_key} "cd ${remote} && git checkout ${current_branch} && git clean -fd" 

          rsync=$(rsync --delete-after --exclude "*.git" --info=progress2 -harvpE -e "ssh -i ${ssh_key}"  ${local}/ ${ssh_user}@${ssh_hostname}:${remote}/)

        fi
      
      else
        # Checkout same branch
        ssh ${hostname} -F ${SSH_CONF} -i ${ssh_key} "cd ${remote} && git stash save && git checkout master && git checkout -b ${current_branch}" # Create branch
        
        # Git-based sync - pull down on remote
        ssh ${hostname} -F ${SSH_CONF} -i ${ssh_key} "cd ${remote} && git checkout ${current_branch} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull && echo synced"
      
      fi

      # Discard any files that are deleted
      ssh ${hostname} -F ${SSH_CONF} -i ${ssh_key} "cd ${remote} && for file in \$(git status | grep 'deleted:' | awk '{print \$2}' ); do git checkout -- \$file; done"  

    else

      # We have a size saved for this dir - lets compare with current size and num of files
      if [[ ${local_dir_sizes[${local_escaped}]} -ne ${current_size} ]]; then

        # Update size in dict
        local_dir_sizes[${local_escaped}]=${current_size}
       
        # Perform sync
        if [[ "${SYNC_METHOD}" == 'Rsync' ]]; then
          rsync=$(rsync --delete-after --exclude "*.git" --info=progress2 -harvpE -e "ssh -i ${ssh_key}"  ${local}/ ${ssh_user}@${ssh_hostname}:${remote}/ 2>/dev/null)
        else
          # If we're here done the initial steps - just pull
          ssh ${hostname} -F ${SSH_CONF} -i ${ssh_key} "cd ${remote} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull origin ${current_branch} && echo synced"
        fi

      elif [[ ${local_dir_files[${local_escaped}]} -ne ${current_num_of_files} ]]; then

        # Update file count in dict
        local_dir_files[${local_escaped}]=${current_num_of_files}
        
        # Perform sync
        if [[ "${SYNC_METHOD}" == 'Rsync' ]]; then
          rsync=$(rsync --delete-after --exclude "*.git" --info=progress2 -harvpE -e "ssh -i ${ssh_key}"  ${local}/ ${ssh_user}@${ssh_hostname}:${remote}/ 2>/dev/null)
        else
          # If we're here done the initial steps - just pull
          ssh ${hostname} -F ${SSH_CONF} -i ${ssh_key} "cd ${remote} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull origin ${current_branch} && echo synced"
        fi


      fi

    fi

    echo -e "\tSync Complete!"

  done
  
  # If we've been passed some args - this is a once-off unless theres a third argument saying otherwise
  [[  ! -z "${ARG1}" && "$3" != "ongoing" ]] && exit

  # Stop if we've reached defined LIMIT
  # ((COUNT++))
  # [[ $COUNT -ge $LIMIT ]] && exit

  sleep ${NAP_TIME}

done
