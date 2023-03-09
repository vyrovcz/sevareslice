# Testing Branch for TTP extension implementation

# Benchmark MP-SPDZ programs in pos testing environments

sevarebench is a framework for running [MP-SPDZ](https://github.com/data61/MP-SPDZ#protocols) SMC protocols in a [pos](https://dl.acm.org/doi/10.1145/3485983.3494841) -enabled testbed environment.

## How to

### To enable git-upload of the measurement data
To use this functionality, a repository to store the measurement results is required. How it would work with [github.com](https://github.com/new):

Change global-variables.yml in line "repoupload: git@github.com:reponame/sevaremeasurements.git" to your repository name.

Then you need a ssh key on your pos management server. Typically you can check for existing keys by running the command

```
less -e ~/.ssh/id_rsa.pub
```

If this displays your ssh public key (ssh-... ... user@host), you could use it in your git repo settings or create a new key-lock pair with 
```
ssh-keygen
```

Use the public key to create a new deploy key for your repository. Add a new Deploy key under "Deploy keys" in the repository settings. Activate "Allow write access". Or hand your public key to your repository admin.
[docs.github.com Deploy Keys](https://docs.github.com/en/developers/overview/managing-deploy-keys#deploy-keys)


### Start experiment measurement

1. Clone this repo on the pos management node into directory `sevarebench` and enter it

```
ssh -p 10022 <username>@<pos-management-server-hostname>
git clone https://github.com/vyrovcz/sevareslice.git sevarebench
cd sevarebench
```

2. Reserve two or more nodes with pos to use with sevarebench

```
pos calendar create -s "now" -d 40 node1 node2 node3
```

3. Make `servarebench.sh` executable and test usage printing

```
chmod 740 sevarebench.sh
./sevarebench.sh
```

This should print some usage information if successful

4. Execute the testrun config to test functionality

```
./sevarebench.sh --config configs/testruns/basic.conf node1,node2,node3 &> sevarelog01 &
disown %-  # your shell might disown by default
```

This syntax backgrounds the experiment run and detaches the process from the shell so that it continues even after disconnect. Track the output of sevarebench in the logfile `sevarelog01` at any time with:

```
tail -F sevarelog01
```

Stuck runs should be closed with sigterm code 15 to the process owning all the testnodes processes. For example with 
```
htop -u $(whoami)
```
and F9. This activates the trap that launches the verification and exporting of the results that have been collected so far, which could take some time. Track the process in the logfile

### Add new parameters

#### On-off switch

An on-off switch is a variable that activates or deactivates something, represented as value 0 for "off" and 1 for "on".
To implement a new switch, code has to be added in various places. The following guides through the steps to add the switch "ssl", that activates or deactives SSL-encryption.

In `helpers\parameters.sh`:
- function `help()`, add a meaningful help entry:

```
    # switches
    ...
    echo "     --ssl            activate/deactivate SSL encryption"
```

- add an array variable in the variable definition and load it with a default value:

```
# MP slice vars with default values
...
OPTSHARE=( 1 )
SSL=( 1 )
```

- function `setParameters()`, add an option flag ("**,ssl:**") for the switch:

```
    # define the flags for the parameters
    ...
    LONG+=,split:,packbool:,optshare:,ssl:,manipulate:
```

- and add a case statement to handle the new option:

```
    while [ $# -gt 1 ]; do
        case "$1" in
            ...
            # MP-Slice args
            ...
            --ssl)
                setArray SSL "$2"
                shift;;
```

- load the new switch to the loop variable file:

```
    # generate loop-variables.yml (append random num to mitigate conflicts)
    ...
    # Config Vars
    ...
    configvars+=( SSL )
```

- add a line to the experiment summary information file:

```
    # Experiment run summary information output
    ...
    echo "    Optimized Sharing: ${OPTSHARE[*]}"
    echo "    SSL: ${SSL[*]}"
```

In `host_scripts\measurement.sh`:
- load the values for the experiment loops, referring to the parameters.sh variable name ("**SSL**") in lowercase:

```
    # load loop variables
    ...
    optshare=$(pos_get_variable optshare --from-loop)
    ssl=$(pos_get_variable ssl --from-loop)
```

- determine, if switch is a compile option or a runtime option and how it is used (in this case -h)
- Here, SSL is a compile option, add ("**-h "$ssl"**") to the compile parameters:

```
        # compile experiment
        /bin/time -f "$timerf" ./Scripts/config.sh -p "$player" -n "$size" -d "$datatype" \
            -s "$protocol" -e "$preprocess" -c "$packbool" -o "$optshare" -h "$ssl"
```

- Assuming it is a runtime option and **not a compile option** (don't do both), add here:

```
# run the SMC protocol
if [ "$splitroles" == 0 ]; then
    /bin/time -f "$timerf" ./search-P"$player".o "$ipA" "$ipB" -h "$ssl" &>> testresults || success=false
else
    ...
    ./Scripts/split-roles.sh -p "$player" -a "$ipA" -b "$ipB" -h "$ssl" &>> testresults || success=false
```


### Add new testbed hosts

#### Switch topology

In `global-variables.yml` simply add the following lines with the respective names for `testbed`, `node`, and `interfacename`

```
# testbedAlpha NIC configuration
node1NIC0: &NICtestbedA <interfacename>
node2NIC0: *NICtestbedA
...
node3NIC0: *NICtestbedA
```

#### Direct connection topology

Design and define node connection model. Recommended and intuitive is the circularly sorted approach like in the following example. Already implemented directly connected nodes are also defined in a circularly sorted fashion.


## Known limitations

### Only exporting measurements from first node

The measurement result data set is exported only from the first node of the node argument value when starting sevarebench.