#!/bin/bash -eu
#
# 
# to test out individual functions without running the whole thing.
# just source this script, then invoke functions.


# Housekeeping
## track how long the whole thing takes
report-elapsed-time() {
    local elapsed_seconds minutes seconds
    (( elapsed_seconds = SECONDS - begin_script ))
    (( minutes = elapsed_seconds / 60 ))
    seconds=$((elapsed_seconds - minutes*60))
    printf "Total elapsed time %02d:%02d\n" $minutes $seconds
}

## cleanliness is next to godliness
get-default-branch() {
    CURRENT_BRANCH=$(git branch --show-current)
    [ $CURRENT_BRANCH == $DEFAULT_BRANCH ] ||
        git checkout -qf $DEFAULT_BRANCH
}


# Basic calculations
## interval between sampled commits
mod() { # how many commits do I skip to get $1 points?
    local npoints=${1:-1}  # default to every commit
    echo $(( $(ncommits)/npoints ))
}

## simple math
only-every() {
    awk "(NR-1)%$1 == 0";
}
## SHA1s of the sample commits
sample-revs() {
    git rev-list --first-parent --abbrev-commit --reverse $DEFAULT_BRANCH |  # listed from first to last
        only-every $(mod $1)
}


# Constants
## constants used elsewhere, can be project-dependent
set-globals() {
    NPOINTS=1000
    SPW=$(( 60*60*24*7 ))  # calculate and save seconds-per-week as a shell constant
}


# Timing commits
## an absolute timestamp, in seconds-from-the-epoch
commit-time() { git log -1 --format=%ct $1; }
## seconds between the first commit and the second
seconds-between() { echo $(($(commit-time $2) - $(commit-time $1))); }
## the function we need: seconds from the first commit.
timestamp() {
    seconds-between $FIRST_COMMIT $1
}
## seconds-per-week
spw() { echo "scale=2; $1/$SPW" | bc; }
timestamp-in-weeks() {
    spw $(timestamp $1)
}

# Data collection
## loop through sample revisions, calling a function for each,
## separate timestamp and week with a comma
run-on-timestamped-samples() {
    local npoints=1 # by default, do every commit
    if [ $# -eq 2 ]; then
        npoints=$1
        shift # discard first argument
    fi
    local func=${1:-true}  # do nothing, i.e., only report the commit
    # git checkout -qf $DEFAULT_BRANCH
    for commit in $(sample-revs $npoints); do
        echo $(timestamp-in-weeks $commit) ,$($func $commit)
    done
}

## collect timing data
timeit() {
    local data=$1
    {
        echo == $data
        time run-on-timestamped-samples $NPOINTS $data > $SIZES/$data.csv
        echo
    } &> $TIMES/$data.csv
}


# Core data summarizers
## simple data collecters
ncommits() { git rev-list --first-parent ${1:-HEAD} | wc -l; }
ncommitters() { git shortlog --first-parent -sc ${1:-HEAD} | wc -l; }
nauthors() { git shortlog --first-parent -sa ${1:-HEAD} | wc -l; }
sha1s() { echo ${1:-HEAD}; }

## count the files in the named commit without checking them out
files() { git ls-tree -r --full-tree --name-only ${1:-HEAD}; }
nfiles() { files $1 | wc -l; }

## functions that survey the worktree of a checkout
lines-and-characters() { git ls-files | grep -v ' ' | xargs -P 32 wc | awk 'BEGIN{ORS=","} /total$/{lines+=$1; chars+=$3} END{print lines "," chars}'; } 2>/dev/null
compressed-size() { tar --exclude-vcs -cf - . | zstd -T0 --fast | wc -c; }

## find work-tree volumes
volumes() {
    git checkout -fq ${1:-HEAD}  # nearly all the time's spent here
    lines-and-characters
    compressed-size
}

## report data for current repo
collect-nocheckout-data() {
    # for data in sha1s ncommits nauthors ncommitters nfiles volumes; do
    for data in sha1s ncommits nauthors ncommitters nfiles; do
        timeit $data &
    done
    wait
}

# Argument parsing
## all repos to traverse
repo-list() {
    echo "$@"
    cat .repos
}

## extract project name from URL
project-name() {
    basename $1 .git
}


# Put them all together, they spell "MOTHER."
main() {
    local cmdline_args="$@"
    set-globals
    for repo in $(repo-list $cmdline_args); do
        local project=$(project-name $repo)
        SIZES=$PWD/sizes/$project
        TIMES=$PWD/times/$project
        mkdir -p $SIZES $TIMES
        [ -d $project ] || git clone -q $repo  # if it's not already local, clone from URL
        (   # in a subshell
            cd $project > /dev/null
            echo == calculating sizes of project $project in $PWD ==
            DEFAULT_BRANCH=$(basename $(git symbolic-ref --short refs/remotes/origin/HEAD))  # master, main, ... whatever
            FIRST_COMMIT=$(git rev-list --first-parent --reverse $DEFAULT_BRANCH | head -1)  # initial commit in current repo
            get-default-branch
            collect-nocheckout-data
        ) &
    done
    wait
}


# Run as a script if the file is invoked, not sourced.
if [ "$BASH_SOURCE" == "$0" ]; then
    begin_script=$SECONDS
    # INITIAL_BRANCH=$(git branch --show-current)
    # trap get-default-branch EXIT
    main "$@"
    report-elapsed-time
fi
