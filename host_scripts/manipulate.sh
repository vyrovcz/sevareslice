#!/bin/bash

# exit on error
set -e

limitCPUs() {

    cpus=$(pos_get_variable cpus --from-loop)
    # activate cpu_count many cpu cores (omit cpu0)
    cpupath=/sys/devices/system/cpu/cpu1/online
    i=2
    # while we have cpus left to manipulate do
    while [ -f $cpupath ] ; do
        # deactivate if cpu_count is smaller than i
        echo $(( cpus < i ? 0 : 1 )) > "$cpupath"
        cpupath=/sys/devices/system/cpu/cpu$i/online
        ((++i))
    done
    return 0
}

limitRAM() {

    # only manipulate ram if there was a swapfile created
    if [ -f /swp/swp_file ];then
        ram=$(pos_get_variable ram --from-loop)
        # occupy unwanted ram
        availram=$(free -m | grep "Mem:" | awk '{print $7}')
        fallocate -l $((availram-ram))M /whale/size
    fi
    return 0
}

setQuota() {

    # set up dynamic cgroup via systemd
    quota=$(pos_get_variable quotas --from-loop)
    environ+=" systemd-run --scope -p CPUQuota=${quota}%"    
    return 0
}

limitBandwidth() {

    #echo "${FUNCNAME[0]} - manipulate=$manipulate"
    bandwidth=$(pos_get_variable bandwidths --from-loop)
    NIC0=$(pos_get_variable "$(hostname)"NIC0 --from-global)
    NIC1=$(pos_get_variable "$(hostname)"NIC1 --from-global) || NIC1=0
    NIC2=$(pos_get_variable "$(hostname)"NIC2 --from-global) || NIC2=0

    # Manipulate every link between each node
    if [ "$manipulate" == "1" ]; then
        tc qdisc add dev "$NIC0" root tbf rate "$bandwidth"mbit burst "$bandwidth"kb limit "$bandwidth"kb
        # check network topology - for directly connected hosts:
        [ "$NIC1" != 0 ] && tc qdisc add dev "$NIC1" root tbf rate "$bandwidth"mbit burst "$bandwidth"kb limit "$bandwidth"kb
        [ "$NIC2" != 0 ] && tc qdisc add dev "$NIC2" root tbf rate "$bandwidth"mbit burst "$bandwidth"kb limit "$bandwidth"kb
    else
    # Manipulate custom links
        nodenumber=$player
        # if 4 nodes and this node is active (player equals to nodenumber)
        if [ ${#manipulate} -eq 4 ] && [ "${manipulate:nodenumber:1}" -eq 1 ]; then
            # NIC0 is always connected to next node in the circularly sort defintion
            # and equals to the next digit in the manipulate string/number
            # (player+1)mod4 -> NIC0; (player+2)mod4 -> NIC1; (player+3) -> NIC2
            # test if next nodes are active for manipulation
            for nic in $NIC0 $NIC1 $NIC2; do
                [ "${manipulate:(((++nodenumber) % 4)):1}" -eq 1 ] &&
                    tc qdisc add dev "$nic" root tbf rate "$bandwidth"mbit burst "$bandwidth"kb limit "$bandwidth"kb
            done
        fi
    fi
    return 0
}

setLatency() {

    latency=$(pos_get_variable latencies --from-loop)
    NIC0=$(pos_get_variable "$(hostname)"NIC0 --from-global)
    NIC1=$(pos_get_variable "$(hostname)"NIC1 --from-global) || NIC1=0
    NIC2=$(pos_get_variable "$(hostname)"NIC2 --from-global) || NIC2=0
    tc qdisc add dev "$NIC0" root netem delay "$latency"ms
    [ "$NIC1" != 0 ] && tc qdisc add dev "$NIC1" root netem delay "$latency"ms
    [ "$NIC2" != 0 ] && tc qdisc add dev "$NIC2" root netem delay "$latency"ms
    return 0
}

setPacketdrop() {

    packetdrop=$(pos_get_variable packetdrops --from-loop)
    # check if switch topology (bc in this case only 1 interface pro host)
    # for 3 interconnected hosts topologies
    NIC0=$(pos_get_variable "$(hostname)"NIC0 --from-global)
    NIC1=$(pos_get_variable "$(hostname)"NIC1 --from-global) || NIC1=0
    NIC2=$(pos_get_variable "$(hostname)"NIC2 --from-global) || NIC2=0
    tc qdisc add dev "$NIC0" root netem loss "$packetdrop"%
    [ "$NIC1" != 0 ] && tc qdisc add dev "$NIC1" root netem loss "$packetdrop"%
    [ "$NIC2" != 0 ] && tc qdisc add dev "$NIC2" root netem loss "$packetdrop"%
    return 0
}

setFrequency() {

    # manipulate frequency last
    # verify on host with watch cat /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq
    cpu_freq=$(pos_get_variable freqs --from-loop)
    cpupower frequency-set -f "$cpu_freq"GHz
    return 0
}

setLatencyBandwidth() {

    latency=$(pos_get_variable latencies --from-loop)
    bandwidth=$(pos_get_variable bandwidths --from-loop)

    NIC0=$(pos_get_variable "$(hostname)"NIC0 --from-global)
    NIC1=$(pos_get_variable "$(hostname)"NIC1 --from-global) || NIC1=0
    NIC2=$(pos_get_variable "$(hostname)"NIC2 --from-global) || NIC2=0

    tc qdisc add dev "$NIC0" root tbf rate "$bandwidth"mbit latency "$latency"ms burst 50kb
    # check if switch topology (bc in this case only 1 interface pro host)
    # for interconnected hosts topologies
    [ "$NIC1" != 0 ] && tc qdisc add dev "$NIC1" root tbf rate "$bandwidth"mbit latency "$latency"ms burst 50kb
    [ "$NIC2" != 0 ] && tc qdisc add dev "$NIC2" root tbf rate "$bandwidth"mbit latency "$latency"ms burst 50kb
    return 0
}

setBandwidthPacketdrop() {
    bandwidth=$(pos_get_variable bandwidths --from-loop)
    packetdrop=$(pos_get_variable packetdrops --from-loop)

    NIC0=$(pos_get_variable "$(hostname)"NIC0 --from-global)
    NIC1=$(pos_get_variable "$(hostname)"NIC1 --from-global) || NIC1=0
    NIC2=$(pos_get_variable "$(hostname)"NIC2 --from-global) || NIC2=0

    tc qdisc add dev "$NIC0" root handle 1:0 netem loss "$packetdrop"%
    tc qdisc add dev "$NIC0" parent 1:1 handle 10: tbf rate "$bandwidth"mbit burst 50kb limit 50kb
    # check if switch topology (bc in this case only 1 interface pro host)
    # for interconnected hosts topologies
    [ "$NIC1" != 0 ] && tc qdisc add dev "$NIC1" root handle 1:0 netem loss "$packetdrop"%
    [ "$NIC1" != 0 ] && tc qdisc add dev "$NIC1" parent 1:1 handle 10: tbf rate "$bandwidth"mbit burst 50kb limit 50kb
    [ "$NIC2" != 0 ] && tc qdisc add dev "$NIC2" root handle 1:0 netem loss "$packetdrop"%
    [ "$NIC2" != 0 ] && tc qdisc add dev "$NIC2" parent 1:1 handle 10: tbf rate "$bandwidth"mbit burst 50kb limit 50kb
    return 0
}

setPacketdropLatency() {
    packetdrop=$(pos_get_variable packetdrops --from-loop)
    latency=$(pos_get_variable latencies --from-loop)

    NIC0=$(pos_get_variable "$(hostname)"NIC0 --from-global)
    NIC1=$(pos_get_variable "$(hostname)"NIC1 --from-global) || NIC1=0
    NIC2=$(pos_get_variable "$(hostname)"NIC2 --from-global) || NIC2=0

    tc qdisc add dev "$NIC0" root netem delay "$latency"ms loss "$packetdrop"%
    # check if switch topology (bc in this case only 1 interface pro host)
    # for interconnected hosts topologies
    [ "$NIC1" != 0 ] && tc qdisc add dev "$NIC1" root netem delay "$latency"ms loss "$packetdrop"%
    [ "$NIC2" != 0 ] && tc qdisc add dev "$NIC2" root netem delay "$latency"ms loss "$packetdrop"%
    return 0
}

############
##  RESET
############

resetFrequency() {

    # reset frequency first
    cpupower frequency-set -f 5GHz
    return 0
}

unlimitRAM() {

    # only reset ram if there was a swapfile created
    if [ -f /swp/swp_file ];then
        # reset ram occupation
        rm -f /whale/size
        # reset swapfile
        swapoff /swp/swp_file
        swapon /swp/swp_file
    fi
    return 0
}

resetTrafficControl() {

    NIC0=$(pos_get_variable "$(hostname)"NIC0 --from-global)
    NIC1=$(pos_get_variable "$(hostname)"NIC1 --from-global) || NIC1=0
    NIC2=$(pos_get_variable "$(hostname)"NIC2 --from-global) || NIC2=0
    tc qdisc delete dev "$NIC0" root
    [ "$NIC1" != 0 ] && tc qdisc delete dev "$NIC1" root
    [ "$NIC2" != 0 ] && tc qdisc delete dev "$NIC2" root
    return 0
}

unlimitCPUs() {

    # activate all cpu cores (omit cpu0)
    cpupath=/sys/devices/system/cpu/cpu1/online
    i=2
    while [ -f $cpupath ] ; do
        # reactivate all
        echo 1 > "$cpupath"
        cpupath=/sys/devices/system/cpu/cpu$i/online
        ((++i))
    done
}