#!/bin/bash

source ctt.sh

npoints=${1:-3}

begin_notebook=$SECONDS

unset first_commit

time timestamps_of_sample_commits $npoints | awk 'BEGIN {spw = 60*60*24*7} {print $3/spw","$1}' > OUT

(( elapsed_seconds = SECONDS - begin_notebook ))
(( minutes = elapsed_seconds / 60 ))
seconds=$((elapsed_seconds - minutes*60))
printf "Elapsed time running notebook %02d:%02d\n" $minutes $seconds
