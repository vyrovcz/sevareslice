#!/bin/bash
# shellcheck disable=SC2034,2154

usage() {
    styleCyan "$0: $1"
    echo
    echo "Options: { -n[odes] | -i[nput] | -c[pu] |"
    echo "           -q(--cpuquota) | -f[req] | -r[am] | -l[atency] | -b(andwidth)} |"
    echo "           -d(--packetdrop)"
    echo -e "\nRun '$0 --help' for more information.\n"
    echo "Available experiments:"
	ls experiments
    echo -e "\nAvailable NODES:"
	# xargs replaces '\n' with ' '
	pos no li | grep -E "$(whoami)|None" | awk '{print $1}' | xargs
    exit 1
}

help() {
	echo "$0 - run SMC experiments with MP-Slice protocol in a POS testbed environment"
    echo "Example:  ./$0 -e 31_scalable_search -p shamir,atlas -n valga,tapa,rapla -i 10,20,...,100 -q 20,40,80 -f 1.9,2.6"
    echo
    echo "<Values> supported are of the form <value1>[,<value2>,...] or use \"...\" to specify the range"
    echo "       [...,<valuei>,]<start>,<next>,...,<stop>[,valuek,...], with increment steps <next>-<start>"
    echo -e "\nOptions (mandatory)"
    echo " -n, --nodes          nodes to run the experiment on of the form <node1>[,<node2>,...]"
    echo " -i, --input          input sizes, with <Values>"
    echo -e "\nOptions (optional)"
    echo "     --etype          experiment type, if applicable, specified with a code"
    echo "     --compflags      extra flags to compile the protocols with"
    echo "     --progflags      extra flags to compile the smc program with"
    echo "     --runflags       extra flags to run the protocols with"
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
EXPORTPATH="results/$(date +20%y-%m)/$(date +%d_%H-%M-%S)"
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

# MP slice vars
DATATYPE=()
PROTOCOLS=()
PREPROCESS=()

INPUTS=()
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
    LONG=experiment:,etype:,compflags:,progflags:,runflags:,nodes:,input:,measureram,cpu:,cpuquota:,freq:,ram:,swap:,config:,latency:,bandwidth:,packetdrop:,help,dtype:,preproc:

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
                setArray PROTOCOLS "$2"
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
        esac
        shift || true      # skip to next option-argument pair
    done

    # node already in use check
    nodetasks=$(pgrep -facu "$(id -u)" "${NODES[0]}")
    [ "$nodetasks" -gt 4 ] && error $LINENO "${FUNCNAME[0]}(): it appears host ${NODES[0]} is currently in use"

    # generate loop-variables.yml (append random num to mitigate conflicts)
    loopvarpath="loopfiles/loop-variables-$NETWORK.yml"
    rm -f "$loopvarpath"
    # Config Vars
    for type in PROTOCOLS DATATYPE PREPROCESS; do
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

    # Experiment run summary  information output
    SUMMARYFILE="$EXPORTPATH/E${EXPERIMENT::2}-run-summary.dat"
    mkdir -p "$SUMMARYFILE" && rm -rf "$SUMMARYFILE"
    {
        echo "  Setup:"
        echo "    Experiment = $EXPERIMENT $ETYPE"
        echo "    Nodes = ${NODES[*]}"
        echo "    Internal network = 10.10.$NETWORK.0/24"
        echo "    Protocols: ${PROTOCOLS[*]}"
        echo "    Inputs = ${INPUTS[*]}"
        echo "    Testtypes:"
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
            flagsnparas=( --experiment "$experiment" )
            for flag in "${!config[@]}"; do
                # skip experiment flag
                [ "$flag" != experiments ] && flagsnparas=( "${flagsnparas[@]}" --"$flag" "${config[$flag]}" )
            done
            echo "running \"bash $0 ${flagsnparas[*]}\""

            # run a new instance of sevarebench with the parsed parameters
            # internal flag -x prevents the recursive closing of the process
            # group in the trap logic that would also close this instance
            bash "$0" -x "${flagsnparas[@]}" || 
                error ${LINENO} "${FUNCNAME[0]}(): stopping config run due to an error"
                
        done <<< "${config[experiments]}",

    done
}