#!/usr/bin/bash

TERM="1500 2000 3000 3500 4000 4500 5000 6000 6500 7000 7500 8000 9000"

for mtu in $TERM
do
	awk '{print $7}' $mtu.dat > $mtu
done
paste $TERM > normal.tsv

for mtu in $TERM
do
	awk '{print $7}' $mtu-perf.dat > $mtu
done
paste $TERM > perf.tsv

for mtu in $TERM
do
	awk '{print $7}' $mtu-perf-buf.dat > $mtu
done
paste $TERM > buf.tsv

for mtu in $TERM
do
	rm $mtu	
done

