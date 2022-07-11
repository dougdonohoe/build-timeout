#!/usr/bin/env bash
#
# Script to sleep a bit X minutes, 5 seconds at a time, defaulting to 61 minutes.  Arg 1 can be
# used to specify alternate minutes.
#

# setup
minutes=${1:-61}
secs=5
((rounds = minutes * 60 / secs))
total=0

# sleep loop
number=0
echo "Sleeping for $minutes minutes, $secs seconds at a time..."
while [[ $number -lt $rounds ]] ; do
  sleep $secs
  ((number = number + 1))
  ((total = total + secs))
  echo "Slept $total seconds of $minutes minutes #$number/$rounds..."
done
echo "Done sleeping $minutes minutes."
