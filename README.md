# RepoSync
Sync the local git repo in a remote machine with your local git repo on your host system.

### Scenario
- You have a local git repo on your local system.
- You also have a remote system which has that same repo cloned into it.
- You have an SSH connection to that machine and relevant details in your ~/.ssh/config file.
- You want the remote system to to always be on the same branch as you (in your local system) and to pull down any changes as soon as you push up any.

<br />

### How it works
There are two modes:
- __Auto__: In this mode the script will check (every 3 seconds) if the number of files (in the local dir) has changed or the total dir size has changes for each entry in the JSON list. If so, it will sync up the remote system.
- __Manual__: In this mode, the script only runs one time and will immediately sync up the remote system for the local directory specified (which one can pass in as a script argument).

<br />

__How it syncs__  
Each time a sync occurs, here's what happens for each entry in the JSON list:
- On the local side, all changes are staged and committed  (with a default commit message of 'Testing/Debugging' and pushed up
- On the remote side
  - Verify we're on the same branch as local. If not, we check out that branch
  - Run a git pull to sync all changes down
- If the branch changes on the local side the branch will also change on the remote side
- Sync does not occur if on the master/main branch.

_Note: In auto mode, this could result in many commits as even small changes will be detected and a commit will be pushed up for every change (and pulled down on the remote side). One could change the `NAP_TIME` global variable to ensure the the script iterates less often (default is every 3 seconds)._

<br />

_Note on Sync Method_  
By setting the sync method to 'Rsync' an rsync will run instead of staging, comitting, and pushing code up.


<br />

### Setup
In the script you'll find a JSON variable like so:
```bash
JSON='[
    {
      "hostname":"ubuntu-vm",
      "dir":"project1"
    },
    {
      "hostname":"ubuntu-vm",
      "dir":"project2"
    },
    {
      "hostname":"ubuntu-vm2",
      "dir":"project3"
    }
]'
```
For each item in the JSON array, there are two key/value pairs:
- dir: The name of the directory on your local/remote machine in which a git repo is located (dir name must be the same on local and remote).
- hostname: The hostname as it appears in your `.ssh/config file`. This will be used to ssh into your machine and sync things up.

You could even pipe a file into `JSON` if you want to save your details in a separate file.

<br />

In the script you'll also see some variables to define:
```bash
# Root directory where all of your local git repos reside
LOCAL_ROOT='/home/bobby/my_repos/'

# Root directory where all of your remote git repos reside
REMOTE_ROOT='/home/ubuntu/projects/'

# Sync Method: Git (default) or Rsync. In Rsync mode, instead of committing and pushing/pulling every time a sync runs, we will instead run a rsync
SYNC_METHOD='/home/ubuntu/projects/'
```


<br />

## Usage
Ideally you would place the script in `/usr/local/bin` this way you can avoid having to call with script with the preceding `./`

<br />

```bash
mv reposync.sh /usr/local/bin/reposync && sudo chmod 755 /usr/local/bin/reposync
```

<br />

_Auto Mode_
```bash
reposync
```

<br />

_Manual Mode_ (forcing a specific repo to sync)  
```bash
reposync <local_dir> "<commit_msg>"
```

Example: `reposync project1 "My awesome feature"`

<br />

Alternatively, you are calling reposync from inside a repo in your sync list (JSON variable) then you can just pass in a single dot `.` as the first argument and only the pwd will be forced to sync.
```bash
reposync .
```
_Note: Of course you can still optionally pass in a second arg as a commit msg._
```bash
reposync . "<commit_msg>"
```

<br />


__Note on Rsync Method__  
If using the Rsync method, the second script argument doesn't need to be a commit message and instead, the second (optional) script argument will be the host you want to force.  
```bash
reposync . "<hostname>"
```
```bash
reposync "<my_repo>" "<hostname>"
```  

<br />

_Manual Method Ongoing_  
By default, the manual method (where repos/hosts be specifically forced) runs as a one-time sync. If you want to sync these forced values as an ongoing process, pass in `ongoing` as the third script parameter.  

```bash
reposync "<repo/.>" "<commit_msg/hostname>" ongoing
```

<br />

## Service  
If you want to install this as a systemd service you can run:  
```bash
sudo bash reposync --install-service
```

<br /> 

Monitor the service  
```bash
sudo systemctl status reposync
```

<br /> 

Tail the service log  
```bash
sudo journalctl-fu reposync
```

--- 

<br />
