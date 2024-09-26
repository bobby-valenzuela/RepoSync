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

# 3 seconds per iteration
NAP_TIME=3  

# ======== END CONFIG ============
#############################################################################

# Checks for any arguments passed in
COMMIT_MSG=$2
LOCAL_DIR_FORCED=""

# If a single dot pased in then we are calling Gitsync from inside a repo in our list, only force this one. 
# This way we can just call `gitsync .` from inside a repo to sync (and optinally pass in a second arg as a commit msg).
if [[ "$1" == '.' ]]; then

  PWD_DIR=$(basename $(pwd))
  LOCAL_DIR_FORCED="${LOCAL_ROOT}${PWD_DIR}"

elif [[  ! -z "$1" ]]; then

  # Anything other than a dot must be the dir itself thats being forced
  LOCAL_DIR_FORCED="${LOCAL_ROOT}$1"

fi


# Define Associative arrays to hold file count/dir size info
unset local_dir_sizes
declare -A local_dir_sizes

unset local_dir_files
declare -A local_dir_files

unset local_branch
declare -A local_branch

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
    if [[ ! -z "${LOCAL_DIR_FORCED}" && "${LOCAL_DIR_FORCED}" != "${local}" ]]; then
      continue
    fi

    # If we're forcing an update and on Rsync, then second arg could be the hostname we want to force as well, if thats passed in, make sure we only process that host as well
    if [[ ! -z "${LOCAL_DIR_FORCED}" && ! -z "$2" && $2 != ${hostname} ]]; then
      continue
    fi

    echo -e "\n[VALUES] Forced: ${LOCAL_DIR_FORCED} | Method: ${SYNC_METHOD} | Local: ${local} | Remote: ${remote} | Host: ${hostname}" 
    
    # Skip if local dir doesn't exist
    [[ ! -d ${local} ]] && continue
    
    # Set any SSH vars if we're doing rsync
    ssh_user=""
    ssh_hostname=""
    ssh_key=""

    if [[ "${SYNC_METHOD}" == 'Rsync' ]]; then
      ssh_user=$(grep -E -A10 "${hostname}(\b|\r|n)" ~/.ssh/config | sed -E '/^$/ q' | awk '/User/ { print $2 }')
      ssh_hostname=$(grep -E -A10 "${hostname}(\b|\r|n)" ~/.ssh/config | sed -E '/^$/ q' | awk '/HostName/ { print $2 }')
      ssh_key=$(grep -E -A10 "${hostname}(\b|\r|n)" ~/.ssh/config | sed -E '/^$/ q' | awk '/IdentityFile/ { print $2 }')
    fi
    
    # Get current git branch
    current_branch=$(cd ${local} && git branch 2>/dev/null | grep '*' | awk '{print $2}' | xargs)
    current_branch_remote=$(ssh ${hostname} "cd ${remote} && git branch 2>/dev/null | grep '*' | awk '{print \$2}' | xargs")

    # Skip if no branch found  or if master (only feature branches sync)
    [[ -z "${current_branch}" || "${current_branch}" == 'master' || "${current_branch}" == 'main' ]] && continue

    # Before continuing let's push what we have up
    if [[ -z "${COMMIT_MSG}" ]]; then
      COMMIT_MSG="Testing/Debugging"
    fi
   
    # If If git sync then commit any unsaved changes
    if [[ "${SYNC_METHOD}" != 'Rsync' ]]; then
      cd ${local} && git add -A && git commit -m "${COMMIT_MSG}" && git push --set-upstream origin ${current_branch}
    fi

    # Replace any fwd-slashes with underscores
    local_escaped=$(printf ${local////_})

    # Now that we have all keys for this entry, lets check size changes to see if sync is needed
    current_size=$(du -bs ${local} | awk '{print $1}')
    current_num_of_files=$(ls -lR ${local} | wc -l)

    # If no size set for this local dir or we switched branches
    echo "[BRANCH] Current: ${current_branch} | LocalLastSaved: ${local_branch[${local_escaped}]}"
    if [[ -z "${local_dir_sizes[${local_escaped}]}" || "${current_branch}" != "${local_branch[${local_escaped}]}" ]]; then
    
      echo "Updating Branches. Notifying remote..."
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
          echo "Remote already on same branch - running rsync."
          rsync=$(rsync --delete-after --exclude "*.git" --info=progress2 -harvpE -e "ssh -i ${ssh_key}"  ${local}/ ${ssh_user}@${ssh_hostname}:${remote}/)
        else
          echo "Remote on different branch (${current_branch_remote}). Updating remote..."

          # Clean any untracked files and discard any unsaved changes - then create branch if needed
          echo "About to run: (ssh ${hostname}'cd ${remote} && git checkout -- . && git clean -fd && git checkout -b ${current_branch}')"
          ssh ${hostname} "cd ${remote} && git checkout -- . && git clean -fd && git checkout -- .  && git checkout -b ${current_branch}"

          # Checkout branch and clean up any untracked files
          ssh ${hostname} "cd ${remote} && git checkout ${current_branch} && git clean -fd" 

          rsync=$(rsync --delete-after --exclude "*.git" --info=progress2 -harvpE -e "ssh -i ${ssh_key}"  ${local}/ ${ssh_user}@${ssh_hostname}:${remote}/)

        fi
      
      else
        # Checkout same branch
        ssh ${hostname} "cd ${remote} && git stash save && git checkout master && git checkout -b ${current_branch}" # Create branch
        
        # Git-based sync - pull down on remote
        ssh ${hostname} "cd ${remote} && git checkout ${current_branch} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull && echo synced"
      
      fi

      # Discard any files that are deleted
      ssh ${hostname} "cd ${remote} && for file in \$(git status | grep 'deleted:' | awk '{print \$2}' ); do git checkout -- \$file; done"  

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
          ssh ${hostname} "cd ${remote} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull origin ${current_branch} && echo synced"
        fi

      elif [[ ${local_dir_files[${local_escaped}]} -ne ${current_num_of_files} ]]; then

        # Update file count in dict
        local_dir_files[${local_escaped}]=${current_num_of_files}
        
        # Perform sync
        if [[ "${SYNC_METHOD}" == 'Rsync' ]]; then
          rsync=$(rsync --delete-after --exclude "*.git" --info=progress2 -harvpE -e "ssh -i ${ssh_key}"  ${local}/ ${ssh_user}@${ssh_hostname}:${remote}/ 2>/dev/null)
        else
          # If we're here done the initial steps - just pull
          ssh ${hostname} "cd ${remote} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull origin ${current_branch} && echo synced"
        fi


      fi

    fi

  done
  
  # If we've been passed some args - this is a once-off unless theres a third argument saying otherwise
  [[  ! -z "${LOCAL_DIR_FORCED}" && "$3" != "ongoing" ]] && exit

  # Stop if we've reached defined LIMIT
  # ((COUNT++))
  # [[ $COUNT -ge $LIMIT ]] && exit

  sleep ${NAP_TIME}

done
