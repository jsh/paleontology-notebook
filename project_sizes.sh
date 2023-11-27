#!/bin/bash -eua
#
# 
# to test out individual functions without running the whole thing.
# just source this script, then invoke functions.


# Housekeeping
## track how long the whole thing takes
report-elapsed-time() {
    (( elapsed_seconds = SECONDS - begin_script ))
    (( minutes = elapsed_seconds / 60 ))
    seconds=$((elapsed_seconds - minutes*60))
    printf "Total elapsed time %02d:%02d\n" $minutes $seconds
}

## cleanliness is next to godliness
cleanup() {
    seq 2 $NREPOS | parallel "[ -d $BASE/$project.{} ] || git clone -q $BASE/$project.1 $BASE/$project.{}"

}


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
## true globals, set at startup
set-globals() {
    BASE=$PWD
    NPOINTS=1000
	NREPOS=10
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
## Placeholder for Scott's comment.
iterate-commits() {
    cd $BASE/$project.$3
    local sampled_commits=$(sample-revs $1 | wc -l)
    local repo_window=$(($sampled_commits/($NREPOS-1)))
    local window_start=$(echo 1+'(('$3-1'))*'$repo_window | bc)
    local window_end=$(echo $repo_window+'(('$3-1'))'*$repo_window | bc)
    local commit_list=$(echo $(sample-revs $1) | sed -n "${window_start},${window_end}p")
    for commit in $commit_list; do
        echo $(timestamp-in-weeks $commit) ,$($2 $commit)
    done
}
## loop through sample revisions, calling a function for each,
## separate timestamp and week with a comma
## placeholder for more Scott comments
run-on-timestamped-samples() {
    local npoints=1 # by default, do every commit
    if [ $# -eq 2 ]; then
        local npoints=$1
        shift # discard first argument
    fi
    local func=${1:-true}  # do nothing, i.e., only report the commit
	seq $NREPOS | parallel cd $BASE/$project.{} ';' git checkout -qf $DEFAULT_BRANCH
    # local sampled_commits=$(sample-revs $npoints | wc -l)
    # local repo_window=$(($sampled_commits/($NREPOS-1)))
    # local window_starts=$(for repo in $(seq $NREPOS); do echo 1+'(('$repo-1'))*'$repo_window | bc; done)
    # local window_ends=$(for repo in $(seq $NREPOS); do echo $repo_window+'(('$repo-1'))'*$repo_window | bc; done)
    seq $NREPOS | parallel iterate-commits $npoints $func {}
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
    git checkout -fq ${1:-HEAD}
	parallel ::: lines-and-characters compressed-size
}

## report data for current repo
collect-data() {
    for data in sha1s ncommits nauthors ncommitters nfiles volumes; do
        timeit $data
    done
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
    cmdline="$@"
    set-globals
    for repo in $(repo-list $cmdline); do
        project=$(project-name $repo)
        SIZES=$PWD/sizes/$project
        TIMES=$PWD/times/$project
        mkdir -p $SIZES $TIMES
        [ -d $BASE/$project.1 ] || git clone -q $repo $project.1 # if it's not already local, clone from URL
		seq 2 $NREPOS | parallel "[ -d $BASE/$project.{} ] || git clone -q $BASE/$project.1 $BASE/$project.{}"
        (   # in a subshell
            cd $BASE/$project.1 > /dev/null
            echo == calculating sizes of project $project in $PWD ==
            DEFAULT_BRANCH=$(basename $(git symbolic-ref --short refs/remotes/origin/HEAD))  # master, main, ... whatever
            FIRST_COMMIT=$(git rev-list --first-parent --reverse $DEFAULT_BRANCH | head -1)  # initial commit in current repo
            collect-data
        )
    done
}


# Run as a script if the file is invoked, not sourced.
if [ "$BASH_SOURCE" == "$0" ]; then
    begin_script=$SECONDS
    DEFAULT_BRANCH=$(git branch --show-current)
    trap cleanup EXIT
    main "$@"
    report-elapsed-time
fi
