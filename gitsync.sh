#!/usr/bin/env bash

# Author : Bobby Valenzuela
# Created : 16th Septemper 2024

# Description:
# List all of the available hosts in your SSH config file and select one to connect to from numbered list.

# Requires 'jq' => sudo apt-get install jq -y

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
      "dir":"api"
    },
    {
      "hostname":"alpha",
      "dir":"biltong-server"
    },
    {
      "hostname":"alpha",
      "dir":"c4"
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

# ======== END CONFIG ============
#############################################################################

# Checks for any arguments passed in
LOCAL_DIR_FORCED=""

if [[ ! -z "$1" ]]; then
  LOCAL_DIR_FORCED="${LOCAL_ROOT}$1"
fi

# If a single dot pased in then we are calling Gitsync from inside a repo in our list, only force this one. 
# This way we can just call `gitsync .` from inside a repo to sync (and optinally pass in a second arg as a commit msg).
if [[ "$1" == '.' ]]; then
  PWD_DIR=$(basename $(pwd))
  LOCAL_DIR_FORCED="${LOCAL_ROOT}${PWD_DIR}"
fi


COMMIT_MSG=$2


# Auto-mode interation details
COUNT=0
NAP_TIME=3  # 3 seconds per iteration
LIMIT=1000 # 100 iterations = ~83mins


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

    # Skip if processing a manual Update
    if [[ ! -z "${LOCAL_DIR_FORCED}" && "${LOCAL_DIR_FORCED}" != "${local}" ]]; then
      continue
    fi

    echo -e "\n[VALUES] Forced: ${LOCAL_DIR_FORCED} | Method: ${SYNC_METHOD} | Local: ${local} | Remote: ${remote}" 
    
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
    if [[ -z "${local_dir_sizes[${local_escaped}]}" || "${current_branch}" != "${local_branch[${local_escaped}]}" ]]; then

      local_dir_sizes[${local_escaped}]=${current_size}
      local_dir_files[${local_escaped}]=${current_num_of_files}
      local_branch[${local_escaped}]=${current_branch}

      # [Initial Steps] On remote machine:
      # - Pull down latest from master
      # - Check out branch (if not checked out)
      # - Pull down latest on that branch (if git sync) otherwise rsync
      
      # Checkout same branch
      ssh ${hostname} "cd ${remote} && git stash save && git checkout master && git checkout -b ${current_branch}" # Create branch

      # Run sync now
      if [[ "${SYNC_METHOD}" == 'Rsync' ]]; then

        rsync=$(rsync --delete-after --exclude "*.git" --info=progress2 -harvpE -e "ssh -i ${ssh_key}"  ${local}/ ${ssh_user}@${ssh_hostname}:${remote}/)
      
      else
        # Git-based sync - pull down on remote
        ssh ${hostname} "cd ${remote} && git checkout ${current_branch} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull && echo synced"
      
      fi

    else

      # We have a size saved for this dir - lets compare with current size and num of files
      if [[ ${local_dir_sizes[${local_escaped}]} -ne ${current_size} ]]; then

        # Update size in dict
        local_dir_sizes[${local_escaped}]=${current_size}
       
        # Perform sync
        if [[ "${SYNC_METHOD}" == 'Rsync' ]]; then
          rsync=$(rsync --delete-after --exclude "*.git" --info=progress2 -harvpE -e "ssh -i ${ssh_key}"  ${local}/ ${ssh_user}@${ssh_hostname}:${remote}/)
        else
          # If we're here done the initial steps - just pull
          ssh ${hostname} "cd ${remote} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull origin ${current_branch} && echo synced"
        fi

      elif [[ ${local_dir_files[${local_escaped}]} -ne ${current_num_of_files} ]]; then

        # Update file count in dict
        local_dir_files[${local_escaped}]=${current_num_of_files}
        
        # Perform sync
        if [[ "${SYNC_METHOD}" == 'Rsync' ]]; then
          rsync=$(rsync --delete-after --exclude "*.git" --info=progress2 -harvpE -e "ssh -i ${ssh_key}"  ${local}/ ${ssh_user}@${ssh_hostname}:${remote}/)
        else
          # If we're here done the initial steps - just pull
          ssh ${hostname} "cd ${remote} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull origin ${current_branch} && echo synced"
        fi


      fi

    fi

  done
  
  # If we've been passed a commit msg - this is a once-off
  [[  ! -z "${LOCAL_DIR_FORCED}" ]] && exit

  # Stop if we've reached defined LIMIT
  ((COUNT++))
  [[ $COUNT -ge $LIMIT ]] && exit

  sleep ${NAP_TIME}

done
