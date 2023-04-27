#!/bin/bash
# shellcheck disable=SC1091,2154

#
# Script is run locally on experiment server.
#

# exit on error
set -e
# log every command
set -x

# load global variables
REPO_DIR=$(pos_get_variable repo_dir --from-global)
REPO2_DIR=$(pos_get_variable repo2_dir --from-global)
manipulate=$(pos_get_variable manipulate --from-global)
# load loop variables/switches
size=$(pos_get_variable input_size --from-loop)
protocol=$(pos_get_variable protocol --from-loop)
datatype=$(pos_get_variable datatype --from-loop)
preprocess=$(pos_get_variable preprocess --from-loop)
splitroles=$(pos_get_variable splitroles --from-loop)
packbool=$(pos_get_variable packbool --from-loop)
optshare=$(pos_get_variable optshare --from-loop)
ssl=$(pos_get_variable ssl --from-loop)
threads=$(pos_get_variable threads --from-loop)
fun=$(pos_get_variable function --from-loop)
txbuffer=$(pos_get_variable txbuffer --from-loop)
rxbuffer=$(pos_get_variable rxbuffer --from-loop)

timerf="%M (Maximum resident set size in kbytes)\n\
%e (Elapsed wall clock time in seconds)\n\
%P (Percent of CPU this job got)"
player=$1
environ=""
# test types to simulate changing environments like cpu frequency or network latency
read -r -a types <<< "$2"
network=10.10."$3"
partysize=$4
# experiment type to allow small differences in experiments
etype=$5
touch testresults

cd "$REPO_DIR"

# different split role script, different ip definition...
if [ "$splitroles" -lt 2 ]; then
    # define ip addresses of the other party members
    [ "$player" -eq 0 ] && ipA="$network".3 && ipB="$network".4
    [ "$player" -eq 1 ] && ipA="$network".2 && ipB="$network".4
    [ "$player" -eq 2 ] && ipA="$network".2 && ipB="$network".3
else
    # define all ips
    ipA="$network".2
    ipB="$network".3
    ipC="$network".4
    ipD="$network".5
fi

{
    echo "./Scripts/config.sh -p $player -n $size -d $datatype -s $protocol -e $preprocess -h $ssl"

    # set config and compile experiment
    if [ "$splitroles" -eq 0 ]; then
        /bin/time -f "$timerf" ./Scripts/config.sh -p "$player" -n "$size" -d "$datatype" \
            -s "$protocol" -e "$preprocess" -c "$packbool" -o "$optshare" -h "$ssl" -b 25000 \
            -j "$threads" -f "$fun" -y "$txbuffer" -z "$rxbuffer"
    else
        # with splitroles active, "-p 3" would through error. Omit -p as unneeded
        /bin/time -f "$timerf" ./Scripts/config.sh -n "$size" -d "$datatype" \
            -s "$protocol" -e "$preprocess" -c "$packbool" -o "$optshare" -h "$ssl" -b 25000 \
            -j "$threads" -f "$fun" -y "$txbuffer" -z "$rxbuffer"
    fi
    
    [ "$splitroles" -eq 1 ] && ./Scripts/split-roles-3-compile.sh -p "$player" -a "$ipA" -b "$ipB"
    [ "$splitroles" -eq 2 ] && ./Scripts/split-roles-3to4-compile.sh -p "$player" -a "$ipA" -b "$ipB" -c "$ipC" -d "$ipD"
    [ "$splitroles" -eq 3 ] && ./Scripts/split-roles-4-compile.sh -p "$player" -a "$ipA" -b "$ipB" -c "$ipC" -d "$ipD"
    
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

# run the SMC protocol
                              # skip 4th node here
if [ "$splitroles" -eq 0 ] && [ "$player" -lt 3 ]; then
    /bin/time -f "$timerf" timeout 420s ./search-P"$player".o "$ipA" "$ipB" &>> testresults || success=false
                                # skip 4th node here
elif [ "$splitroles" -eq 1 ] && [ "$player" -lt 3 ]; then
    /bin/time -f "$timerf" timeout 420s ./Scripts/split-roles-3-execute.sh -p "$player" -a "$ipA" -b "$ipB" &>> testresults || success=false
elif [ "$splitroles" -eq 2 ]; then
    /bin/time -f "$timerf" timeout 420s ./Scripts/split-roles-3to4-execute.sh -p "$player" -a "$ipA" -b "$ipB" -c "$ipC" -d "$ipD" &>> testresults || success=false
elif [ "$splitroles" -eq 3 ]; then
    /bin/time -f "$timerf" timeout 420s ./Scripts/split-roles-4-execute.sh -p "$player" -a "$ipA" -b "$ipB" -c "$ipC" -d "$ipD" &>> testresults || success=false
fi

# divide external runtime x*j
# Todo: divide normal binary run by j*j

# do calculations if splitroles is active or more threads are used
if [ "$splitroles" -gt 0 ] || [ "$threads" -gt 1 ]; then

    # binary:   calculate mean of j results running concurrent ( /j *j )
    # 3nodes:   calculate mean of 6*j results running concurrent ( /6*j *6*j )
    # 3-4nodes: calculate mean of 18*j results running concurrent ( /18*j *18*j )
    # 4nodes:   calculate mean of 24*j results running concurrent ( /24*j *24*j )
    [ "$splitroles" -eq 0 ] && divisor=$((threads*threads)) && divisorExt=$((threads))
    [ "$splitroles" -eq 1 ] && divisor=$((6*6*threads*threads)) && divisorExt=$((6*threads))
    [ "$splitroles" -eq 2 ] && divisor=$((18*18*threads*threads)) && divisorExt=$((18*threads))
    [ "$splitroles" -eq 3 ] && divisor=$((24*24*threads*threads)) && divisorExt=$((24*threads))

    sum=$(grep "measured to initialize program" testresults | cut -d 's' -f 2 | awk '{print $5}' | paste -s -d+ | bc)
    average=$(echo "scale=6;$sum / $divisor" | bc -l)
    echo "Time measured to initialize program: ${average}s" &>> testresults

    sum=$(grep "computation clock" testresults | cut -d 's' -f 2 | awk '{print $6}' | paste -s -d+ | bc)
    average=$(echo "scale=6;$sum / $divisor" | bc -l)
    echo "Time measured to perform computation clock: ${average}s" &>> testresults

    sum=$(grep "computation getTime" testresults | cut -d 's' -f 2 | awk '{print $6}' | paste -s -d+ | bc)
    average=$(echo "scale=6;$sum / $divisor" | bc -l)
    echo "Time measured to perform computation getTime: ${average}s" &>> testresults

    sum=$(grep "computation chrono" testresults | cut -d 's' -f 2 | awk '{print $6}' | paste -s -d+ | bc)
    average=$(echo "scale=6;$sum / $divisor" | bc -l)
    echo "Time measured to perform computation chrono: ${average}s" &>> testresults

    runtimeext=$(grep "Elapsed wall clock" testresults | tail -n 1 | cut -d ' ' -f 1)
    average=$(echo "scale=6;$runtimeext / $divisorExt" | bc -l)
    echo "$average (Elapsed wall clock time in seconds)" &>> testresults

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
pos_upload --loop terminal_output.txt
# abort if no success
$success