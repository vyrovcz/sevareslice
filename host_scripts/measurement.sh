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
manipulate=$(pos_get_variable manipulate --from-global)
source "$REPO2_DIR"/protocols.sh
size=$(pos_get_variable input_size --from-loop)
protocol=$(pos_get_variable protocol --from-loop)
datatype=$(pos_get_variable datatype --from-loop)
preprocess=$(pos_get_variable preprocess --from-loop)
splitroles=$(pos_get_variable splitroles --from-loop)
packbool=$(pos_get_variable packbool --from-loop)
optshare=$(pos_get_variable optshare --from-loop)

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
touch testresults

cd "$REPO_DIR"

{
    echo "./Scripts/config.sh -p $player -n $size -d $datatype -s $protocol -e $preprocess"

    #if [ "$splitroles" == 0 ]; then
        # compile experiment
        /bin/time -f "$timerf" ./Scripts/config.sh -p "$player" -n "$size" -d "$datatype" \
            -s "$protocol" -e "$preprocess" -c "$packbool" -o "$optshare"
    #fi
    
    echo "$(du -BM search-P* | cut -d 'M' -f 1 | head -n 1) (Binary file size in MiB)"

} |& tee testresults

echo -e "\n========\n" >> testresults

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
if [ "$splitroles" == 0 ]; then
    /bin/time -f "$timerf" ./search-P"$player".o "$ipA" "$ipB" &>> testresults || success=false
else
    #doesn't work with /bin/time
    #/bin/time -f "$timerf" ./Scripts/split-roles.sh -p "$player" -a "$ipA" -b "$ipB" &>> testresults || success=false
    ./Scripts/split-roles.sh -p "$player" -a "$ipA" -b "$ipB" &>> testresults || success=false

    # wait until finished, the runs quits earlier
    sleep 2s

    ###echo "./Scripts/split-roles.sh -p \"$1\" -a \"$2\" -b \"$3\"" > run.sh
    ###/bin/time -f "$timerf" bash run.sh -p "$player" -a "$ipA" -b "$ipB" &>> testresults || success=false
    
    # calculate mean of 36 results
    sum=$(grep "measured to initialize program" testresults | cut -d 's' -f 2 | awk '{print $5}' | paste -s -d+ | bc)
    average=$(echo "scale=6;$sum / 36" | bc -l)
    echo "Time measured to initialize program: ${average}s" &>> testresults

    sum=$(grep "computation clock" testresults | cut -d 's' -f 2 | awk '{print $6}' | paste -s -d+ | bc)
    average=$(echo "scale=6;$sum / 36" | bc -l)
    echo "Time measured to perform computation clock: ${average}s" &>> testresults

    sum=$(grep "computation getTime" testresults | cut -d 's' -f 2 | awk '{print $6}' | paste -s -d+ | bc)
    average=$(echo "scale=6;$sum / 36" | bc -l)
    echo "Time measured to perform computation getTime: ${average}s" &>> testresults

    sum=$(grep "computation chrono" testresults | cut -d 's' -f 2 | awk '{print $6}' | paste -s -d+ | bc)
    average=$(echo "scale=6;$sum / 36" | bc -l)
    echo "Time measured to perform computation chrono: ${average}s" &>> testresults

fi

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

echo "experiment finished"  >> testresults
pos_upload --loop testresults
# abort if no success
$success
pos_sync --loop