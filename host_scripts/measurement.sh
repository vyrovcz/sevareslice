#!/bin/bash
# shellcheck disable=SC1091,2154

#
# Script is run locally on experiment server.
#

# exit on error
set -e
# log every command
set -x

REPO_DIR=$(pos_get_variable repo_dir --from-global)
REPO2_DIR=$(pos_get_variable repo2_dir --from-global)
source "$REPO2_DIR"/protocols.sh
size=$(pos_get_variable input_size --from-loop)
protocol=$(pos_get_variable protocols --from-loop)
datatype=$(pos_get_variable datatype --from-loop)
preprocess=$(pos_get_variable preprocess --from-loop)

timerf="%M (Maximum resident set size in kbytes)\n\
        %e (Elapsed wall clock time in seconds)\n\
        %P (Percent of CPU this job got)"
player=$1
environ=""
# test types to simulate changing environments like cpu frequency or network latency
read -r -a types <<< "$2"
network="$3"
partysize=$4
# experiment type to allow small differences in experiments
etype=$5
log=testresults"$protocol"
touch "$log"

cd "$REPO_DIR"

{
    echo "./Scripts/config.sh -p $player -n $size -d $datatype -s $protocol -e $preprocess"

    # compile experiment
    /bin/time -f "$timerf" ./Scripts/config.sh -p "$player" -n "$size" -d "$datatype" \
        -s "$protocol" -e "$preprocess"

} |& tee "$log"

echo -e "\n========\n" >> "$log"

####
#  environment manipulation section start
####
# shellcheck source=../host_scripts/manipulate.sh
source "$REPO2_DIR"/host_scripts/manipulate.sh

case " ${types[*]} " in
    *" CPUS "*)
        limitCPUs;;&
    *" RAM "*)
        limitRAM;;&
    *" QUOTAS "*)
        setQuota;;&
    *" FREQS "*)
        setFrequency;;&
    *" BANDWIDTHS "*)
        # check whether to manipulate a combination
        case " ${types[*]} " in
            *" LATENCIES "*)
                setLatencyBandwidth;;
            *" PACKETDROPS "*) # a.k.a. packet loss
                setBandwidthPacketdrop;;
            *)
                limitBandwidth;;
        esac;;
    *" LATENCIES "*)
        if [[ " ${types[*]} " == *" PACKETDROPS "* ]]; then
            setPacketdropLatency
        else
            setLatency
        fi;;
    *" PACKETDROPS "*)
        setPacketdrop;;
esac

####
#  environment manipulation section stop
####

success=true

pos_sync --timeout 300

# define ip addresses of the other party members
[ "$player" -eq 0 ] && ipA=10.10."$network".3 && ipB=10.10."$network".4
[ "$player" -eq 1 ] && ipA=10.10."$network".2 && ipB=10.10."$network".4
[ "$player" -eq 2 ] && ipA=10.10."$network".2 && ipB=10.10."$network".3

# run the SMC protocol
/bin/time -f "$timerf" ./search-P"$player".o "$ipA" "$ipB" &> "$log" || success=false

pos_upload --loop "$log"

#abort if no success
$success

pos_sync

####
#  environment manipulation reset section start
####

case " ${types[*]} " in

    *" FREQS "*)
        resetFrequency;;&
    *" RAM "*)
        unlimitRAM;;&
    *" BANDWIDTHS "*|*" LATENCIES "*|*" PACKETDROPS "*)
    	resetTrafficControl;;&
    *" CPUS "*)
        unlimitCPUs
esac

####
#  environment manipulation reset section stop
####

# if there are no test types
if [ "${#types[*]}" -lt 1 ]; then
    # older binaries won't be needed anymore and can be removed
    # this is important for a big number of various input sizes
    # as with many binaries a limited disk space gets consumed fast
    rm -rf Programs/Bytecode/*
fi

pos_sync --loop

echo "experiment successful"  >> measurementlog"$cdomain"

pos_upload --loop measurementlog"$cdomain"