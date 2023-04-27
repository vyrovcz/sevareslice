#!/bin/bash
# shellcheck disable=SC2034,2154

usage() {
    styleCyan "$0: $1"
    echo
    echo "Options: { -n[odes] | -i[nput] | -c[pu] |"
    echo "           -q(--cpuquota) | -f[req] | -r[am] | -l[atency] | -b(andwidth)} |"
    echo "           -d(--packetdrop)"
    echo -e "\nRun '$0 --help' for more information.\n"
    echo -e "\nAvailable NODES:"
	# xargs replaces '\n' with ' '
	pos no li | grep -E "$(whoami)|None" | awk '{print $1}' | xargs
    exit 1
}

help() {
	echo "$0 - run SMC experiments with MP-Slice in a POS testbed environment"
    echo "Example:  ./$0 -p 1,2,...,6 -n algofi,gard,goracle,zone --dtype 64 -b 20000 -i 10,20,...,100 -q 20,40,80 -f 1.9,2.6"
    echo
    echo "<Values> supported are of the form <value1>[,<value2>,...] or use \"...\" to specify the range"
    echo "       [...,<valuei>,]<start>,<next>,...,<stop>[,valuek,...], with increment steps <next>-<start>"
    echo -e "\nOptions (mandatory)"
    echo " -n, --nodes          nodes to run the experiment on of the form <node1>[,<node2>,...]"
    echo " -p, --protocols      protocols , with <Values>"
    echo " -i, --input          input sizes, with <Values>"
    echo -e "\nOptions (optional)"
    #echo "     --etype          experiment type, if applicable, specified with a code"
    #echo "     --compflags      extra flags to compile the protocols with"
    #echo "     --progflags      extra flags to compile the smc program with"
    #echo "     --runflags       extra flags to run the protocols with"
    echo "     --dtype          set the datatype in bits (1,8,64,128,256)"
    # switches
    echo "     --preproc        activate/deactivate preprocessing"
    echo "     --split          activate/deactivate split roles, set type with 1 or 2 or 3"
    echo "                      1 -> split-roles-3"
    echo "                      2 -> split-roles-3to4"
    echo "                      3 -> split-roles-4 (only with -p > 6)"
    echo "     --packbool       activate/deactivate pack booleans (--dtype 1 only)"
    echo "     --optshare       activate/deactivate optimized sharing"
    echo "     --ssl            activate/deactivate SSL encryption"
    echo "     --function       Function Identifier (0: Search, 2: AND, ...)"
    # variables
    echo "     --threads        Number of parallel processes to use"
    echo "     --txbuffer       Number of gates to buffer until sending them to the receiving party"
    echo "     --rxbuffer       Number of messages to buffer until processing"
    echo "     --config         config files run with <path> as parameter, nodes can be given separatly"
    echo "                      allowed form: $0 --config file.conf [nodeA,...]"
    echo -e "\nManipulate Host Environment (optional)"
    echo " -c, --cpu            cpu thread counts, with <Values>"
    echo " -q, --cpuquota       cpu quotas in % (10 < quota), with <Values>"
    echo " -f, --freq           cpu frequencies in GHz (e.g. 1.7), with <Values>"
    echo " -r, --ram            limit max RAM in MiB (e.g. 1024), with <Values>, /dev/nvme0n1 required"
    echo "     --swap           set secondary memory swap size in MiB, one value, SSD /dev/nvme0n1 required"
    echo "                      mandatory with -r to allow paging/swaping (default 4096)"
    echo "                      Warning: setting this too small will break the entire run at some point"
    echo -e "\nManipulate Network Environment (optional)"
    echo " -l, --latency        latency of network in ms, with <Values>"
    echo " -b, --bandwidth      bandwidth of network in MBit/s, with <Values>"
    echo " -d, --packetdrop     packet drop/loss in network in %, with <Values>"
    echo "     --manipulate     specify custom links to manipulate, instead of all links (=\"66...\"),"
    echo "                      by defining a code for each node to manipulate only a subset of the links."
    echo "                      For 4 nodes, there are 6 links, each link having 2 endings. In sum there"
    echo "                      are 12 endings that can be manipulated, giving 2^12 = 4096 total constellations"
    echo "                      Note that only Tx direction can be manipulated, to limit the entire link, both"
    echo "                      ends need to be activated for manipulation."
    echo "                      The codes 0,1,...,6 define which of the three links to manipulate, where"
    echo "                      0 -> only NIC0;    1 -> only NIC1;    2 -> only NIC2;    7 -> none"
    echo "                      3 -> NIC0 && NIC1; 4 -> NIC0 && NIC2; 5 -> NIC1 && NIC2; 6 -> all"
    echo "                      where NIC0 always connects to the next node alphabetically in sequence"
    echo "                      and NIC1 to the second and NIC3 to the third in sequence"
    echo "                      Notice: nodes constellation must be circularly sorted (should be anyway)"
    echo "                      Notice: NICs must be connected alphabetically in sequence (see readme)"
    echo "                      Examples for \"--node node2,node3,node4,node1\":"
    echo "                      1234 activats Tx manipulations on"
    echo "                          node2 -> NIC1 -> node4"
    echo "                          node3 -> NIC2 -> node2"
    echo "                          node4 -> NIC0 && NIC1 -> node1 && node2"
    echo "                          node1 -> NIC0 && NIC2 -> node2 && node4"
    echo "                      0000 activats Tx manipulations on"
    echo "                          node2 -> NIC0 -> node3"
    echo "                          node3 -> NIC0 -> node4"
    echo "                          node4 -> NIC0 -> node1"
    echo "                          node1 -> NIC0 -> node2"
    echo "                      2567 activats Tx manipulations on"
    echo "                          node2 -> NIC2 -> node1"
    echo "                          node3 -> NIC1 && NIC2 -> node2"
    echo "                          node4 -> all -> node1 && node2 && node3"
    echo "                          node1 -> none"
    echo "                      7777 (useless, no links are manipulated, equivalent to no manipulation options)"
    echo "                      6666 (default, all links are manipulated)"
    echo "                      To limit only the link between node3 and node4 in both directions to"
    echo "                      simulate a low bandwidth bottleneck: 7027"
    echo "                      7027 activats Tx manipulations on"
    echo "                          node2 -> none"
    echo "                          node3 -> NIC0 -> node4"
    echo "                          node4 -> NIC2 -> node3"
    echo "                          node1 -> none"
	echo -e "\nAvailable NODES:\n"
	# xargs replaces '\n' with ' '
	pos no li | grep -E "$(whoami)|None" | awk '{print $1}' | xargs
	exit 0
}

setArray() { # load array $1 reference with ,-seperated values in $2
    local -n array="$1"     # get array reference
    set -f                  # avoid * expansion
    IFS="," read -r -a array <<< "$2"
}

TEMPFILES=()
ALLOC_ID=""
EXPORTPATH="resultsMP-Slice/$(date +20%y-%m)/$(date +%d_%H-%M-%S)"
# pos_upload resultspath
RPATH=""
SUMMARYFILE=""
POS=pos
IMAGE=debian-bullseye
SECONDS=0
RUNSTATUS="${Red}fail${Stop}"
# this is required for the config support logic
CONFIGRUN=false

EXPERIMENT=""
ETYPE=""
compflags=""
progflags=""
runflags=""
NODES=()

# MP slice vars with default values
DATATYPE=( 64 )
PROTOCOL=( 2 )
PREPROCESS=( 0 )
SPLITROLES=( 0 )
PACKBOOL=( 0 )
OPTSHARE=( 1 )
SSL=( 1 )
THREADS=( 1 )
FUNCTION=( 0 )
TXBUFFER=( 0 )
RXBUFFER=( 0 )
manipulate="6666"

INPUTS=( 4096 )
CPUS=()
QUOTAS=()
FREQS=()
LATENCIES=()
BANDWIDTHS=()
PACKETDROPS=()
RAM=()
SWAP=""
TTYPES=()
PIDS=()
# create a random network number to support multiple experiment runs 
# on the same switch.   Generate random number  1 < number < 255
NETWORK=$((RANDOM%253+2))

# Parsing inspired from https://stackoverflow.com/a/29754866
# https://gist.github.com/74e9875d5ab0a2bc1010447f1bee5d0a

setParameters() {

    # verify if getopt is available
    getopt --test > /dev/null
    [ $? -ne 4 ] && { error $LINENO "${FUNCNAME[0]}(): getopt not available 
        for parsing arguments."; }

    # define the flags for the parameters
    # ':' means that the flag expects an argument.
    SHORT=e:,n:,p:,i:,m,c:,q:,f:,r:,l:,b:,d:,x,h
    LONG=experiment:,etype:,protocols:,compflags:,progflags:,runflags:
    LONG+=,nodes:,input:,measureram,cpu:,cpuquota:,freq:,ram:,swap:
    LONG+=,config:,latency:,bandwidth:,packetdrop:,help,dtype:,preproc:
    LONG+=,split:,packbool:,optshare:,ssl:,threads:,manipulate:,function:
    LONG+=,txbuffer:,rxbuffer:

    PARSED=$(getopt --options ${SHORT} \
                    --longoptions ${LONG} \
                    --name "$0" \
                    -- "$@") || { error $LINENO "${FUNCNAME[0]}(): getopt failed parsing options"; }

    eval set -- "${PARSED}"

    while [ $# -gt 1 ]; do
        #echo "parsing arg: $1 $2"
        case "$1" in
            -h|--help)
                help;;
            -e|--experiment)
                EXPERIMENT="$2"
                shift;;
            --etype)
                ETYPE="$2"
                shift;;
            --compflags)
                compflags="$2"
                shift;;
            --progflags)
                progflags="$2"
                shift;;
            --runflags)
                runflags="$2"
                shift;;
            -n|--nodes) 
                setArray NODES "$2"
                shift;;
            -p|--protocols) 
                setArray PROTOCOL "$2"
                shift;;
            -i|--input)
                setArray INPUTS "$2"
                shift;;
            # MP-Slice args
            --dtype)
                setArray DATATYPE "$2"
                shift;;
            --preproc)
                setArray PREPROCESS "$2"
                shift;;
            --split)
                setArray SPLITROLES "$2"
                shift;;
            --packbool)
                setArray PACKBOOL "$2"
                shift;;
            --optshare)
                setArray OPTSHARE "$2"
                shift;;
            --ssl)
                setArray SSL "$2"
                shift;; 
            --threads)
                setArray THREADS "$2"
                shift;;
            --function)
                setArray FUNCTION "$2"
                shift;;
            --txbuffer)
                setArray TXBUFFER "$2"
                shift;;
            --rxbuffer)
                setArray RXBUFFER "$2"
                shift;;
            --manipulate)
                manipulate="$2"
                shift;;
            # Host environment manipulation
            -c|--cpu)
                TTYPES+=( CPUS )
                setArray CPUS "$2"
                shift;;
            -q|--cpuquota)
                TTYPES+=( QUOTAS )
                setArray QUOTAS "$2"
                shift;;
            -f|--freq)
                TTYPES+=( FREQS )
                setArray FREQS "$2"
                shift;;
            -r|--ram)
                TTYPES+=( RAM )
                setArray RAM "$2"
                shift;;
            # Network environment manipulation
            -l|--latency)
                TTYPES+=( LATENCIES )
                setArray LATENCIES "$2"
                shift;;
            -b|--bandwidth)
                TTYPES+=( BANDWIDTHS )
                setArray BANDWIDTHS "$2"
                shift;;
            -d|--packetdrop)
                TTYPES+=( PACKETDROPS )
                setArray PACKETDROPS "$2"
                shift;;
            --swap)
                SWAP="$2"
                shift;;
            --config)
                parseConfig "$2" "$4"
                exit 0;;
            -x)
                CONFIGRUN=true;;
            *) error $LINENO "${FUNCNAME[0]}(): unrecognized flag $1 $2";;
            # "
        esac
        shift || true      # skip to next option-argument pair
    done

    # node already in use check
    nodetasks=$(pgrep -facu "$(id -u)" "${NODES[0]}")
    [ "$nodetasks" -gt 4 ] && error $LINENO "${FUNCNAME[0]}(): it appears host ${NODES[0]} is currently in use"

    # set experiment wide variables (append random num to mitigate conflicts)
    # if value may contain a leading 0 (zero), add any char before (like manipulate)
    experimentvarpath="variables/experiment-variables-$NETWORK.yml"
    echo "experiment: $EXPERIMENT" > "$experimentvarpath"
    echo "manipulate: m$manipulate" >> "$experimentvarpath"

    # generate loop-variables.yml (append random num to mitigate conflicts)
    loopvarpath="variables/loop-variables-$NETWORK.yml"
    rm -f "$loopvarpath"
    # Config Vars
    configvars=( OPTSHARE PACKBOOL SPLITROLES PROTOCOL PREPROCESS DATATYPE )
    configvars+=( SSL THREADS FUNCTION TXBUFFER RXBUFFER )
    for type in "${configvars[@]}"; do
        declare -n ttypes="${type}"
        parameters="${ttypes[*]}"
        echo "${type,,}: [${parameters// /, }]" >> "$loopvarpath"
    done
    # Environment Manipulation Vars
    for type in "${TTYPES[@]}"; do
        declare -n ttypes="${type}"
        parameters="${ttypes[*]}"
        echo "${type,,}: [${parameters// /, }]" >> "$loopvarpath"
    done
    parameters="${INPUTS[*]}"
    echo "input_size: [${parameters// /, }]" >> "$loopvarpath"

    # delete line measureram from loop_var, if active
    sed -i '/measureram/d' "$loopvarpath"

    # set default swap size, in case --ram is defined
    [ "${#RAM[*]}" -gt 0 ] && SWAP=${SWAP:-4096}

    # Experiment run summary information output
    SUMMARYFILE="$EXPORTPATH/Eslice-run-summary.dat"
    mkdir -p "$SUMMARYFILE" && rm -rf "$SUMMARYFILE"
    {
        echo "  Setup:"
        echo "    Experiment = $EXPERIMENT $ETYPE"
        echo "    Nodes = ${NODES[*]}"
        echo "    Internal network = 10.10.$NETWORK.0/24"
        echo "    Function: ${FUNCTION[*]}"
        echo "    Protocols: ${PROTOCOL[*]}"
        echo "    Datatypes = ${DATATYPE[*]}"
        echo "    Inputs = ${INPUTS[*]}"
        echo "    Preprocessing: ${PREPROCESS[*]}"
        echo "    SplitRoles: ${SPLITROLES[*]}"
        echo "    Pack Bool: ${PACKBOOL[*]}"
        echo "    Optimized Sharing: ${OPTSHARE[*]}"
        echo "    SSL: ${SSL[*]}"
        echo "    Threads: ${THREADS[*]}"
        echo "    txBuffer: ${TXBUFFER[*]}"
        echo "    rxBuffer: ${RXBUFFER[*]}"
        [ "$manipulate" != "6666" ] && echo "    manipulate: $manipulate"
        echo "    Testtypes:"
        for type in "${TTYPES[@]}"; do
            declare -n ttypes="${type}"
            echo -e "      $type\t= ${ttypes[*]}"
        done
        echo "  Summary file = $SUMMARYFILE"
    } | tee "$SUMMARYFILE"
}

# inspired by https://unix.stackexchange.com/a/206216
parseConfig() {

    # overwrite the main trap
    trap configruntrap 0

    configs=()
    # file or folder?
    if [ -f "$1" ]; then
        configs=( "$1" )
    elif [ -d "$1" ]; then
        # add all config files in the folder to the queue 
        while IFS= read -r conf; do
            configs+=( "$conf" )
        done < <(find "$1" -maxdepth 1 -name "*.conf" | sort)
    else
        error ${LINENO} "${FUNCNAME[0]}(): no such file or directory: $1"
    fi

    for conf in "${configs[@]}"; do

        echo -e "\n_____________________________________"
        echo "###   Starting new config file \"$conf\" ###"
        echo -e "_____________________________________\n"

        declare -A config=()
        while read -r line; do
            # skip # lines
            [[ "${line::4}" == *"#"* ]] && continue
            # sanitize a little by removing everything after any space char
            sanline="${line%% *}"

            flag=$(echo "$sanline" | cut -d '=' -f 1)
            parameter=$(echo "$sanline" | cut -d '=' -f 2-)
            [ -n "$parameter" ] && config[$flag]="$parameter"
            # for flags without parameter, cut returns the flag
            [ "$flag" == "$parameter" ] && config[$flag]=""
        done < "$conf"

        # also allow specifying the nodes via commandline in the form
        # ./sevarebench.sh --config xy.conf nodeA,nodeB,...
        [ -z "${config[nodes]}" ] && config[nodes]="$2"
        # override mode for externally defined nodes
        #[ -n "$2" ] && config[nodes]="$2"

        while read -rd , experiment; do

            echo -e "\n_____________________________________"
            echo "###   Starting new experiment run ###"
            echo -e "_____________________________________\n"
            # generate the specifications
            #flagsnparas=( --experiment "$experiment" )
            flagsnparas=( )
            for flag in "${!config[@]}"; do
                # skip experiment flag
                [ "$flag" != experiments ] && flagsnparas=( "${flagsnparas[@]}" --"$flag" "${config[$flag]}" )
            done

            retry=1
            while [ "$retry" -eq 1 ]; do
                retry=0

                # run a new instance of sevarebench with the parsed parameters
                # internal flag -x prevents the recursive closing of the process
                # group in the trap logic that would also close this instance
                echo "running \"bash $0 ${flagsnparas[*]}\""
                bash "$0" -x "${flagsnparas[@]}"

                # catch retry error codes, set them with the error function in the
                # getlastoutput() function in the trap_helper.sh or around the framework
                exitcode=$?
                if [ "$exitcode" -eq 4 ]; then
                    warning "Random error assumed, trying again. Waiting 5s for nodes to detach..."
                    sleep 5
                    echo
                    retry=1
                elif [ "$exitcode" -eq 5 ]; then
                    warning "POS timeout, trying again. Waiting 5s for nodes to detach..."
                    sleep 5
                    echo
                    retry=1                    
                elif [ "$exitcode" -ne 0 ]; then
                    error ${LINENO} "${FUNCNAME[0]}(): stopping config run due to an error"
                fi
            done
                
        done <<< "${config[experiments]}",

    done
}