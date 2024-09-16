#!/usr/bin/env bash

# Author : Bobby Valenzuela
# Created : 20th June 2023
# Last Modified : 20th June 2023

# Description:
# List all of the available hosts in your SSH config file and select one to connect to from numbered list.

# Requires 'jq' => sudo apt-get install jq -y

#############################################################################

# Define globals
COUNT=0
LIMIT=10000 # [optional] 1000 iterations = ~ 7.5hrs
COMMIT_MSG=$1

JSON='[
    {
      "hostname":"alpha",
      "local_dir":"/home/bobby/pbx/c4",
      "remote_dir":"/home/control-io/www"
    },
    {
      "hostname":"alpha",
      "local_dir":"/home/bobby/pbx/voutlook365",
      "remote_dir":"/home/control-io/voutlook365"
    }
]'

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
    local=$(echo "$obj" | jq -r '.local_dir')
    remote=$(echo "$obj" | jq -r '.remote_dir')

    # Skip if local dir doesn't exist
    [[ ! -d ${local} ]] && continue

    # Get current git branch
    current_branch=$(cd ${local} && git branch 2>/dev/null | grep '*' | awk '{print $2}' | xargs)

    # Skip if no branch found  or if master (only feature branches sync)
    [[ -z "${current_branch}" || "${current_branch}" == 'master' ]] && continue

    # Before continuing let's push what we have up
    if [[ -z "${COMMIT_MSG}" ]]; then
      COMMIT_MSG="Testing/Debugging"
    fi
    cd ${local} && git add -A && git commit -m "${COMMIT_MSG}" && git push --set-upstream origin ${current_branch}

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
      # - Check out branch
      # - Pull down latest on that branch

      ssh ${hostname} "cd ${remote} && git stash save && git checkout master && git checkout -b ${current_branch}" # Create branch
      ssh ${hostname} "cd ${remote} && git checkout ${current_branch} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull && echo synced"

    else

      # We have a size saved for this dir - lets compare with current size and num of files
      if [[ ${local_dir_sizes[${local_escaped}]} -ne ${current_size} ]]; then

        # Update size in dict
        local_dir_sizes[${local_escaped}]=${current_size}

        # If we're here done the initial steps - just pull
        ssh ${hostname} "cd ${remote} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull && echo synced"

      elif [[ ${local_dir_files[${local_escaped}]} -ne ${current_num_of_files} ]]; then

        # Update file count in dict
        local_dir_files[${local_escaped}]=${current_num_of_files}

        # If we're here done the initial steps - just pull
        ssh ${hostname} "cd ${remote} && git branch --set-upstream-to=origin/${current_branch} ${current_branch} && git pull && echo synced"
      fi

    fi

  done

  # If we've been passed a commit msg - this is a once-off
  [[ -z "${COMMIT_MSG}" ]] && exit

  ((COUNT++))

  # Stop if we've reached defined LIMIT
  [[ $COUNT -ge $LIMIT ]] && exit

  sleep 3

done
