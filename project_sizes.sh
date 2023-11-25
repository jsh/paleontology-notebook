#!/bin/bash -eu
#
# 
# to test out individual functions without running the whole thing.
# just source this script, then invoke functions.


# Housekeeping
## track how long the whole thing takes
begin_script=$SECONDS
report-elapsed-time() {
    (( elapsed_seconds = SECONDS - begin_script ))
    (( minutes = elapsed_seconds / 60 ))
    seconds=$((elapsed_seconds - minutes*60))
    printf "Total elapsed time %02d:%02d\n" $minutes $seconds
}

## cleanliness is next to godliness
cleanup() {
    git checkout -qf $DEFAULT_BRANCH # clean up after yourself
}
trap cleanup EXIT


# Basic calculations
## interval between sampled commits
mod() { # how many commits do I skip to get $1 points?
    local npoints=${1:-1}  # default to every commit
    local ncmts=$(ncommits)
    echo $(( ncmts/npoints ))
}

## simple math
only-every() { awk "(NR-1)%$1 == 0"; }
## SHA1s of the sample commits
sample-revs() {
    git rev-list --first-parent --abbrev-commit --reverse $DEFAULT_BRANCH |  # listed from first to last
        only-every $(mod $1)
}


# Constants
## constants used elsewhere, can be project-dependent
set-globals() {
    NPOINTS=10
    NPOINTS=1000
    SPW=$(( 60*60*24*7 ))  # calculate and save seconds-per-week as a shell constant
    DEFAULT_BRANCH=$(basename $(git symbolic-ref --short refs/remotes/origin/HEAD))
    FIRST_COMMIT=$(git rev-list --first-parent --reverse $DEFAULT_BRANCH | head -1)  # initialize per repo
}

## project-specific globals, directories, and setup
set-project() {
    local project=${1:-git} # analyze the git source by default
    SIZES=$PWD/sizes/$project
    TIMES=$PWD/times/$project

    # GitHub repo for project-specific sources
    case $project in
        git)
            OWNER=git
        ;;
        linux)
            OWNER=torvalds
            ;;
        *) die "Unknown project $project" ;;
    esac
    REPO=https://github.com/$OWNER/$project.git

    mkdir -p $SIZES $TIMES
    [ -d $project ] || git clone -q $REPO $project # clone source-code repo if it's not already there
    cd $project >/dev/null # and dive in
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
        local npoints=$1
        shift # discard first argument
    fi
    local func=${1:-true}  # do nothing, i.e., only report the commit
    git checkout -qf $DEFAULT_BRANCH
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


# Core data-collection functions
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
    git checkout -fq ${1:-HEAD}
    lines-and-characters &
    compressed-size &
    wait
}


# Put them all together, they spell "MOTHER."
main() {
    set-project ${1:-}
    set-globals   # depends on project
    for data in sha1s ncommits nauthors ncommitters nfiles volumes; do
        timeit $data
    done
    report-elapsed-time
}


# Run as a script if the file is invoked, not sourced.
if [ "$BASH_SOURCE" == "$0" ]; then
    main ${1:-}
fi
