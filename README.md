# GitSync
Sync the local git repo in a remote machine with your local git repo on your host system

### Scenario
- You have a local git repo on your local system.
- You also have a remote system which has that same repo cloned into it.
- You have an SSH connection to that machine and relevant details in your ~/.ssh/config file.
- You want the remote system to to always be on the same branch as you (in your local system) and to pull down any changes as soon as you push up any.

<br />

### How it works
There are two modes:
- __Auto__: In this mode the script will check (every seconds) if the number of files has changed or the total dir size has changes for each entry in the JSON list. If so, it will sync up the remote system.
- __Manual__: In this mode, the script only runs one time and immediately sync up the remote system for each entry in the JSON list.

<br />

__How it syncs__  
Each time a sync occurs, here's what happens for each entry in the JSON list:
- On the local side, all changes are staged and committed  (with a default commit message of 'Testing/Debugging' and pushed up
- On the remote side
  - Verify we're on the same branch as local. If not, we check out that branch
  - Run a git pull to sync all changes down
- If the branch changes on the local side the branch will also change on the remote side

_Note: In auto mode, this could result in many commits as even small changes will be detected and a commit will be pushed up for every changed (and pulled down on the remote side). One could change the `NAP_TIME` global variable to ensure the the script iterates less often (default is every 3 seconds)._

<br />

### Setup
In the script you'll find a JSON variable like so:
```bash
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
```
For each item in the JSON array, there are three key/value pairs:
- local_dir: The directory on your local machine in which a git repo is located
- remote_dir: The directoy on your remote machine in which the same git repo is located
- hostname: The hostname as it appears in youe `.ssh/config file`. This will be used to ssh into your machine and sync things up.

You could even pipe a file into `JSON` if you want to save your details in a separate file.

<br />

### Usage
Ideally you would place the script in `/usr/local/bin` this way you can having to call with script with the preceding `./`

<br />

```bash
mv gitsync.sh /usr/local/bin/gitsync && sudo chmod 755 /usr/local/bin/gitsync
```

<br />

_Auto Mode_
```bash
gitsync
```

<br />

_Mnual Mode_
```bash
gitsync "My Cool commit message"
```
