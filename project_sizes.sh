#!/bin/bash

begin_notebook=$SECONDS

# number of commits
ncommits() { git rev-list --first-parent ${1:-HEAD} | wc -l; }

# interval between sampled commits
mod() { # how many commits do I skip to get $1 points?
    local npoints=${1:-1}  # default to every commit
    local ncmts=$(ncommits)
    echo $(( ncmts/npoints ))
}
# SHA1s of the sample commits
only_every() { awk "(NR-1)%$1 == 0"; }
sample_revs() {
    git rev-list --first-parent --abbrev-commit --reverse $DEFAULT_BRANCH |  # listed from first to last
        only_every $(mod $1)
}
# loop through sample revisions, calling a function for each
run_on_samples() {
    local npoints=1 # by default, do every commit
    if [ $# -eq 2 ]; then
        local npoints=$1
        shift # discard first argument
    fi
    local func=${1:-true}  # do nothing, i.e., only report the commit
    for commit in $(sample_revs $npoints); do
        echo $commit $($func $commit)
    done
}

# constants used elsewhere
set_globals() {
    DEFAULT_BRANCH=$(basename $(git symbolic-ref --short refs/remotes/origin/HEAD))
    FIRST_COMMIT=$(git rev-list --first-parent --reverse $DEFAULT_BRANCH | head -1)  # initialize per repo
    NPOINTS=10
    SPW=$(( 60*60*24*7 ))  # calculate and save seconds-per-week as a shell constant
}

# an absolute timestamp, in seconds-from-the-epoch
commit_time() { git log -1 --format=%ct $1; }
# seconds between the first commit and the second
seconds_between() { echo $(($(commit_time $2) - $(commit_time $1))); }

# and finally, the function we need: seconds from the first commit.
timestamp() {
    seconds_between $FIRST_COMMIT $1
}

spw() { echo "scale=2; $1/$SPW" | bc; }
timestamp_in_weeks() {
    spw $(timestamp $1)
}

# loop through sample revisions, calling a function for each,
# separate timestamp and week with a comma
run_on_timestamped_samples() {
    local npoints=1 # by default, do every commit
    if [ $# -eq 2 ]; then
        local npoints=$1
        shift # discard first argument
    fi
    local func=${1:-true}  # do nothing, i.e., only report the commit
    for commit in $(sample_revs $npoints); do
        echo $(timestamp_in_weeks $commit) ,$($func $commit)
    done
}

# count the files in the named commit without checking them out
files() { git ls-tree -r --full-tree --name-only ${1:-HEAD}; }
nfiles() { files $1 | wc -l; }
lines-and-characters() { git checkout -q ${1:-HEAD}; git ls-files | grep -v ' ' | xargs -L 1 wc | awk '{lines+=$1; chars+=$3}END{print lines "," chars}'; }
compressed-size() { git checkout -q ${1:-HEAD}; tar --exclude-vcs -Jcf - . | wc -c; }

DIR=linux
REPO=https://github.com/torvalds/linux.git
OUTPUT=$PWD/sizes/$DIR
mkdir -p $OUTPUT

[ -d $DIR ] || git clone -q $REPO # clone Git's source-code repo if it's not already there
cd $DIR >/dev/null # and dive in

set_globals
time run_on_timestamped_samples $NPOINTS ncommits > $OUTPUT/ncommits.csv
time run_on_timestamped_samples $NPOINTS nfiles > $OUTPUT/nfiles.csv
time run_on_timestamped_samples $NPOINTS lines-and-characters 2>/dev/null > $OUTPUT/lines-and-characters.csv
time run_on_timestamped_samples $NPOINTS compressed-size > $OUTPUT/compressed-size.csv

(( elapsed_seconds = SECONDS - begin_notebook ))
(( minutes = elapsed_seconds / 60 ))
seconds=$((elapsed_seconds - minutes*60))
printf "Total elapsed time %02d:%02d\n" $minutes $seconds
