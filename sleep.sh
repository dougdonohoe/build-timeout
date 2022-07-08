#!/usr/bin/env bash
#
# Script to sleep a bit over an hour, 5 seconds at a time
#

# 732*5 = 3660 seconds (61 minutes)
rounds=732
secs=5

# sleep loop
number=1
while [[ $number -le $rounds ]] ; do
    echo "Sleep $secs #$number/$rounds..."
  sleep $secs
  ((number = number + 1))
done
