#!/usr/bin/bash

IP='/usr/sbin/ip'
HEAD='/usr/bin/head'
TAIL='/usr/bin/tail'
LSCPU='/usr/bin/lscpu'
GREP='/usr/bin/grep'
AWK='/usr/bin/awk'
TR='/usr/bin/tr'
SED='/usr/bin/sed'
XARGS='/usr/bin/xargs'
BASH='/usr/bin/bash'
SUDO='/usr/bin/sudo'
CPUFREQ_SET='/usr/bin/cpufreq-set'
CPUPOWER='/usr/bin/cpupower'
SYSCTL='/usr/sbin/sysctl'
SSH='/usr/bin/ssh'
KILLALL='/usr/bin/killall'
NUTTCP='/home/reo/nuttcp-8.1.4/nuttcp-8.1.4'

ORG_MTU=`$IP link show $1|$HEAD -n1|$AWK '{print $5}'`
NUMA_NODE=`cat /sys/class/net/$1/device/numa_node`
NUMA_CPUS=`$LSCPU|$GREP "NUMA node$NUMA_NODE"|$AWK '{print $4}'`
LIST=`echo $NUMA_CPUS|$TR "," "\n"|$SED s/-/\.\./`
ORG_RMEM_MAX=`$SYSCTL -n net.core.rmem_max`
ORG_WMEM_MAX=`$SYSCTL -n net.core.wmem_max`
ORG_TCP_RMEM=`$SYSCTL -n net.ipv4.tcp_rmem`
ORG_TCP_WMEM=`$SYSCTL -n net.ipv4.tcp_wmem`

set_link_mtu () {
	$SUDO $IP link set $1 mtu $2
	echo "set link "$1" mtu to "$2
}

set_link_mtu_remotehost () {
	$SSH $1 $SUDO $IP link set $2 mtu $3
	echo "set "$1"'s link "$2" mtu to "$3
}

killall_nuttcp_remotehost () {
	$SSH $1 $KILLALL $NUTTCP
	echo "killall "$1"'s nuttcp process"
}

start_nuttcpd_remotehost () {
	$SSH $1 $NUTTCP -S
	echo "start "$1"'s nuttcpd"
}

show_link_mtu () {
	$IP link show $1|$HEAD -n 1|$AWK '{print $5}'
}

show_link_mtu_remotehost () {
	$SSH $1 $IP link show $2|$HEAD -n 1|$AWK '{print $5}'
}

show_link_rxpackets () {
	$IP -s link show $1|$HEAD -n4|$TAIL -n1|$AWK '{print $2}'
}

show_link_txpackets () {
	$IP -s link show $1|$HEAD -n6|$TAIL -n1|$AWK '{print $2}'
}

show_link_rx_tx () {
	show_link_rxpackets $1
	show_link_txpackets $1
}

benchmark () {
	for i in {1..100}; do $NUTTCP -xc 7/7 -T10 $2 >> data/$1.dat; done
}

set_cpufreq () {
	if [-e /etc/redhat-release ]; then
		echo $LIST|$TR " " "\n"|$XARGS -I{} $BASH -c "for i in {{}}; do $SUDO $CPUPOWER -c \$i frequency-set -g $1; done"
	fi
	if [-e /etc/lsb-release ]; then
		echo $LIST|$TR " " "\n"|$XARGS -I{} $BASH -c "for i in {{}}; do $SUDO $CPUFREQ_SET -c \$i -g $1; done"
	fi
}

set_cpufreq_remotehost () {
	if [ $($SSH $1 "[ -e /etc/redhat-release ];echo \$?") -eq 0  ]; then
		echo $LIST|$TR " " "\n"|$XARGS -I{} $BASH -c "for i in {{}}; do $SSH $1 $SUDO $CPUPOWER -c \$i frequency-set -g $2; done"
	fi
	if [ $($SSH $1 "[ -e /etc/lsb-release ];echo \$?") -eq 0  ]; then
		echo $LIST|$TR " " "\n"|$XARGS -I{} $BASH -c "for i in {{}}; do $SSH $1 $SUDO $CPUFREQ_SET -c \$i -g $2; done"
	fi
}

set_tcp_buffers () {
	$SUDO $SYSCTL -w net.core.rmem_max=$1
	$SUDO $SYSCTL -w net.core.wmem_max=$2
	$SUDO $SYSCTL -w net.ipv4.tcp_rmem="$3 $4 $5"
	$SUDO $SYSCTL -w net.ipv4.tcp_wmem="$6 $7 $8"
}

set_tcp_buffers_remotehost () {
	$SSH $9 $SUDO $SYSCTL -w net.core.rmem_max=$1
	$SSH $9 $SUDO $SYSCTL -w net.core.wmem_max=$2
	$SSH $9 $SUDO $SYSCTL -w net.ipv4.tcp_rmem="$3 $4 $5"
	$SSH $9 $SUDO $SYSCTL -w net.ipv4.tcp_wmem="$6 $7 $8"
}


for mtu in {1500,2000,3000,3500,3750,4000,4500,5000,6000,6500,7000,7500,7750,8000,9000}
do
	set_link_mtu $1 $mtu
	killall_nuttcp_remotehost $2
	set_link_mtu_remotehost $2 $1 $mtu
	start_nuttcpd_remotehost $2

	# NORMAL
	echo "MTU: "$mtu" normal"
	show_link_mtu $1
	show_link_mtu_remotehost $2 $1
	show_link_rx_tx $1
	benchmark $mtu $2
	show_link_rx_tx $1

	# CPUFREQ	
	echo "MTU: "$mtu" CPUFREQ -> performance"
	set_cpufreq performance

	killall_nuttcp_remotehost $2
	set_cpufreq_remotehost $2 performance
	start_nuttcpd_remotehost $2

	benchmark $mtu-perf $2

	# TCP BUFFERS
	echo "MTU: "$mtu" CPUFREQ -> performance, TCP_BUFFERS"
	set_tcp_buffers 2147483647 2147483647 4096 87380 2147483647 4096 65536 2147483647
	killall_nuttcp_remotehost $2
	set_tcp_buffers_remotehost 2147483647 2147483647 4096 87380 2147483647 4096 65536 2147483647 $2
	start_nuttcpd_remotehost $2

	for i in {1..100}; do $NUTTCP -xc 7/7 -w1m -T10 $2 >> data/$mtu-perf-buf.dat; done

	# reset
	set_cpufreq powersave
	set_cpufreq_remotehost $2 powersave
	set_tcp_buffers $ORG_RMEM_MAX $ORG_WMEM_MAX $ORG_TCP_RMEM $ORG_TCP_WMEM
	set_tcp_buffers_remotehost $ORG_RMEM_MAX $ORG_WMEM_MAX $ORG_TCP_RMEM $ORG_TCP_WMEM $2
done

# reset
set_link_mtu $1 $ORG_MTU
set_link_mtu_remotehost $2 $1 $ORG_MTU
killall_nuttcp_remotehost $2
