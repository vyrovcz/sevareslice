#!/bin/bash

# Experiment setup-script to be run locally on experiment server

# exit on error
set -e
# log every command
set -x

REPO_DIR=$(pos_get_variable repo_dir --from-global)
REPO2_DIR=$(pos_get_variable repo2_dir --from-global)
EXPERIMENT=$(pos_get_variable experiment --from-global)
# SMC protocols to compile
ipaddr="$1"
SWAP="$2"
network="$3"
read -r -a nodes <<< "$4"
groupsize=${#nodes[*]}


#######
#### set networking environment
#######


# If the testnodes are directly connected from NIC to NIC and
# not via a switch, we need to create individual networks for each
# NIC pair and route the network through the correct NIC
# this is not an ideal situation for big party numbers

nic0=$(pos_get_variable "$(hostname)"NIC0 --from-global)
nic1=$(pos_get_variable "$(hostname)"NIC1 --from-global) || nic1=0

ips=()

######
### three nodes indirect connection topology setup
### node 2 --- node 1 --- node 3
### for 25G+ speeds set MTU
if [ "$(hostname | grep -cE "gard|goracle|zone")" -eq 1 ]; then

	ip addr add 10.10."$network"."$ipaddr"/24 dev "$nic0"
	ip link set dev "$nic0" mtu 9000
	ip link set dev "$nic0" up

	if [ "$ipaddr" -eq 2 ]; then
		# activate forwarding for the center node
		sysctl -w net.ipv4.ip_forward=1
		ip addr add 10.10."$network"."$ipaddr"/24 dev "$nic1"
		ip link set dev "$nic1" mtu 9000
		ip link set dev "$nic1" up
		# route via correct NICs
		ip route add 10.10."$network".3 dev "$nic0"
		ip route add 10.10."$network".4 dev "$nic1"
	elif [ "$ipaddr" -eq 3 ]; then
		ip route add 10.10."$network".4 via 10.10."$network".2
	else
		ip route add 10.10."$network".3 via 10.10."$network".2
	fi
# three nodes direct connection topology if true
elif [ "$nic1" != 0 ]; then

	# verify that nodes array is circularly sorted
	# this is required for the definition of this topology
	
	# specify the ip pair to create the network routes to
	# it's not the ip that is being set to this host
	[ "$ipaddr" -eq 2 ] && ips+=( 3 4 )
	[ "$ipaddr" -eq 3 ] && ips+=( 4 2 )
	[ "$ipaddr" -eq 4 ] && ips+=( 2 3 )

	ip addr add 10.10."$network"."$ipaddr"/24 dev "$nic0"
	ip addr add 10.10."$network"."$ipaddr"/24 dev "$nic1"

	ip link set dev "$nic0" up
	ip link set dev "$nic1" up

	ip route add 10.10."$network"."${ips[0]}" dev "$nic0"
	ip route add 10.10."$network"."${ips[1]}" dev "$nic1"

# here the testhosts are connected via switch
else
	# support any groupsizes
	# store other participants ips
	for i in $(seq 2 "$groupsize"); do
		[ "$ipaddr" -ne "$i" ] && ips+=( "$i" )
	done

	ip addr add 10.10."$network"."$ipaddr"/24 dev "$nic0"
	ip link set dev "$nic0" up

	# for every other participant
	for ip in "${ips[@]}"; do
		# add route
		ip route add 10.10."$network"."$ip" dev "$nic0"
	done
fi

# wait for others to finish setup
pos_sync

# log link test
for ip in "${ips[@]}"; do
	ping -c 2 10.10."$network"."$ip" &>> pinglog || true
done

# set up swap disk
if [ -n "$SWAP" ] && [ -b /dev/nvme0n1 ]; then
	echo "creating swapfile with swap size $SWAP"
	parted -s /dev/nvme0n1 mklabel gpt
	parted -s /dev/nvme0n1 mkpart primary ext4 0% 100%
	mkfs.ext4 -FL swap /dev/nvme0n1
	mkdir /swp
	mkdir /whale
	mount -L swap /swp
	dd if=/dev/zero of=/swp/swp_file bs=1024 count="$SWAP"K
	chmod 600 /swp/swp_file
	mkswap /swp/swp_file
	swapon /swp/swp_file
	 # create ramdisk
    totalram=$(free -m | grep "Mem:" | awk '{print $2}')
	mount -t tmpfs -o size="$totalram"M swp /whale
	# preoccupy ram and only leave 16 GiB for faster experiment runs
	# it was observed, that more than that was never required and 
	# falloc is slow in loops on nodes with large ram
	ram=$((16*1024))
	availram=$(free -m | grep "Mem:" | awk '{print $7}')
	fallocate -l $((availram-ram))M /whale/filler
fi

echo "experiment setup successful"

