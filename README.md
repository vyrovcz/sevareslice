# Benchmark MP-Slice programs in pos testing environments

sevarebench is a framework for running [MP-SPDZ](https://github.com/data61/MP-SPDZ#protocols) SMC protocols in a [pos](https://dl.acm.org/doi/10.1145/3485983.3494841) -enabled testbed environment.

This sevareslice version is a framework for running [MP-Slice](https://github.com/chart21/MP-Slice/tree/experimental) SMC protocols

## How to

### Enable git-upload of the measurement data
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

- determine, if the switch is a compile option or a runtime option and how it is used (in this case -h)
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

Verify functionality:
- by running a test using the new flag

```
bash sevarebench.sh --protocols 1,2,...,6 --nodes n1,n2,n3 --dtype 128 --ssl 0,1 --split 0,1 --input 4096,8192,...,40960 &>> sevarelog_n1TEST &
disown %-
tail -fn 80 sevarelog_n1TEST
```

- and verify if exported data looks good

```
less -S resultsMP-Slice/20xx-xx/xx_xx-xx-xx/data/Eslice_short_results.tsv
```

Parsing of measurements table.
In `tools\sevare_parser.py`:
- add the switch to the "switches_names"-array: ("**; h -> ssl**") and ("**, "ssl"**")

```
# switches are on/off values, where a feature is either off or on
# e -> preprocess; r -> splitroles; c -> packbool; o -> optimize sharing; h -> ssl
switches_names = ["preprocess", "splitroles", "packbool", "optshare", "ssl"]
```

- add the default value for this switch, in case it has not been specified. The value should correspond to the value set in `helpers\parameters.sh` in a previous step.

```
        # default values in case the table is lacking them
        ...
        opt = line[switch_indexes[3]] if switch_indexes[3] > 0 else 1
        ssl = line[switch_indexes[4]] if switch_indexes[4] > 0 else 1
```

- add the switchname to the filename: ("**ssl1**") and ("**+ "ssl" + str(ssl)**")

```
        # path of form parsed/2D/p1/d128Bwd_pre0split0pack0opt1ssl1.txt
        ...
        txtpath = txtpathbase + "pre" + str(pre) + "split" + str(split) + "pack" + str(pack) + "opt" + str(opt) + "ssl" + str(ssl) + ".txt"
```

- confirm the parsing works by running

```
python3 tools/sevare_parser.py resultsMP-Slice/20xx-xx/xx_xx-xx-xx
```

- and verifying that under `parsed/2D/x/` the correct plot files are being created

Plotting the plot files.
In `tools\sevare_plotter_tex.py`:
- add the switch to the getConsString() function: ("**+ "ssl" + constellation["ssl"]**")

```
def getConsString(constellation):
    return "pre" + constellation["pre"] + "split" + constellation["split"] + "pack" + constellation["pack"] + "opt" + constellation["opt"] + "ssl" + constellation["ssl"]
```

- add the switch to the plot information summary ("**", SSL: " + constellation["ssl"]**"):

```
        # Plot information summary
        ...
        switchpositions += ", Pack Bool: " + constellation["pack"] + ", Optimize Sharing: " + constellation["opt"]
        switchpositions +=  ", SSL: " + constellation["ssl"]
```

- add the switch to title page information by adding ("**, "SSL"**") to the capture array:

```
    # title page information
    capture = ["Protocols", "Datatypes", "Inputs", "Preprocessing",
        "SplitRoles", "Pack", "Optimized", "SSL", "CPUS", "QUOTAS", "FREQS", "RAM",
        "LATENCIES", "BANDWIDTHS", "PACKETDROPS", "Summary file", "runtime"]
```

- add the switch information to the filename: ("**, "ssl"**")

```
    # add switch positions to the filename
    for switch in ["pre", "split", "pack", "opt", "ssl"]:
```


### Add new testbed hosts

#### Find out interface names - 4 interconnected nodes algofi,gard,goracle,zone

In a well documented testbed, interface names are simply looked up in the topology overview.
If, for some reason, the interface names are not documented, the following procedure can help to identify them:

- Make a schematic representation depicting the node situation for better orientation, for example a graph with four nodes and each node connected to each other, resulting in 6 edges that will be labled with the interface card. For each node, 3 interfaces need to be determined, 12 in total.

- The NICs are arranged circularly sorted, so that NIC0 is connected to the node alphabetically in sequence. (algofi: NIC0 -> gard, NIC1 -> goracle, NIC2 -> zone; or gard: NICO -> goracle, NIC1 -> zone, NIC2 -> algofi; or goracle: NIC0 -> zone, NIC1 -> algofi, NIC2 -> gard)

- Reserve the nodes and reset them, using all four nodes. This will fail since interfaces are missing.

```
bash sevarebench.sh --config configs/testruns/basic.conf algofi,gard,goracle,zone &> sevarelog_gardTEST &
```

- Connect to each of the nodes and view the interfaces with

```
ip a
```

- Check the interfaces, if their name and speed information reveal them to be a candidate

```
root@algofi:~# apt install ethtool
root@algofi:~# for interface in $(ip a | grep mtu | awk '{print $2}' | cut -d ':' -f 1); do echo "$interface"; ethtool $interface | grep Speed; done
lo
eno1np0
        Speed: 1000Mb/s
eno2np1
        Speed: 10000Mb/s
enp193s0f0
        Speed: 10000Mb/s
enp193s0f1
        Speed: 25000Mb/s
enp195s0f0
        Speed: 25000Mb/s
enp195s0f1
        Speed: 25000Mb/s
usb0
enp129s0f0np0
        Speed: Unknown!
enp129s0f1np1
        Speed: Unknown!
```

- Since we are looking for 25000Mb/s Link Speed interfaces, the three candidates have been revealed to be enp193s0f1, enp195s0f0, enp195s0f1 for algofi. Repeat for the other 3 nodes.

- Now that the interfaces have been determined, the next step is to find out which interfaces connects to which node. First, set the ip to the interfaces with

```
root@algofi:~# for interface in $(ip a | grep mtu | awk '{print $2}' | cut -d ':' -f 1);do [ $(ethtool $interface | grep -c 25000Mb) -gt 0 ] && echo "$interface" && ip addr add 10.10.10.2/24 dev "$interface" ; done
root@gard:~# for interface in $(ip a | grep mtu | awk '{print $2}' | cut -d ':' -f 1);do [ $(ethtool $interface | grep -c 25000Mb) -gt 0 ] && echo "$interface" && ip addr add 10.10.10.3/24 dev "$interface" ; done
root@goracle:~# for interface in $(ip a | grep mtu | awk '{print $2}' | cut -d ':' -f 1);do [ $(ethtool $interface | grep -c 25000Mb) -gt 0 ] && echo "$interface" && ip addr add 10.10.10.4/24 dev "$interface" ; done
root@zone:~# for interface in $(ip a | grep mtu | awk '{print $2}' | cut -d ':' -f 1);do [ $(ethtool $interface | grep -c 25000Mb) -gt 0 ] && echo "$interface" && ip addr add 10.10.10.5/24 dev "$interface" ; done
```

- Note the ip address ending in .2 for the first node, .3 for the second, .4 the third, and .5 the fourth. Alphabetically sorted. Verify with ip a that ips have been set. Set interface link up

```
for interface in $(ip a | grep mtu | awk '{print $2}' | cut -d ':' -f 1);do [ $(ethtool $interface | grep -c 25000Mb) -gt 0 ] && echo "$interface" && ip link set dev "$interface" up; done
```


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