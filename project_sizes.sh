#!/bin/bash

begin_notebook=$SECONDS

# number of commits
ncommits() { git rev-list --first-parent ${1:-HEAD} | wc -l; }
ncommitters() { git shortlog --first-parent -sc ${1:-HEAD} | wc -l; }
nauthors() { git shortlog --first-parent -sa ${1:-HEAD} | wc -l; }

# interval between sampled commits
mod() { # how many commits do I skip to get $1 points?
    local npoints=${1:-1}  # default to every commit
    local ncmts=$(ncommits)
    echo $(( ncmts/npoints ))
}
# SHA1s of the sample commits
only-every() { awk "(NR-1)%$1 == 0"; }
sample-revs() {
    git rev-list --first-parent --abbrev-commit --reverse $DEFAULT_BRANCH |  # listed from first to last
        only-every $(mod $1)
}

# constants used elsewhere
set-globals() {
    DEFAULT_BRANCH=$(basename $(git symbolic-ref --short refs/remotes/origin/HEAD))
    FIRST_COMMIT=$(git rev-list --first-parent --reverse $DEFAULT_BRANCH | head -1)  # initialize per repo
    NPOINTS=10
    NPOINTS=1000
    SPW=$(( 60*60*24*7 ))  # calculate and save seconds-per-week as a shell constant
}

# an absolute timestamp, in seconds-from-the-epoch
commit-time() { git log -1 --format=%ct $1; }
# seconds between the first commit and the second
seconds-between() { echo $(($(commit-time $2) - $(commit-time $1))); }

# and finally, the function we need: seconds from the first commit.
timestamp() {
    seconds-between $FIRST_COMMIT $1
}

spw() { echo "scale=2; $1/$SPW" | bc; }
timestamp-in-weeks() {
    spw $(timestamp $1)
}

# loop through sample revisions, calling a function for each,
# separate timestamp and week with a comma
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

# count the files in the named commit without checking them out
files() { git ls-tree -r --full-tree --name-only ${1:-HEAD}; }
nfiles() { files $1 | wc -l; }
lines-and-characters() { git ls-files | grep -v ' ' | xargs -L 1 wc | awk 'BEGIN{ORS=","} {lines+=$1; chars+=$3} END{print lines "," chars}'; } 2>/dev/null
compressed-size() { tar --exclude-vcs -Jcf - . | wc -c; }
volumes() {
    git checkout -fq ${1:-HEAD}
    lines-and-characters
    compressed-size
}

set-project() {
    #DIR=git
    #REPO=https://github.com/git/git.git
    DIR=linux
    REPO=https://github.com/torvalds/linux.git
    OUTPUT=$PWD/sizes/$DIR
    mkdir -p $OUTPUT
    [ -d $DIR ] || git clone -q $REPO # clone source-code repo if it's not already there
    cd $DIR >/dev/null # and dive in
}

set-project
set-globals
time run-on-timestamped-samples $NPOINTS echo > $OUTPUT/sha1s.csv
time run-on-timestamped-samples $NPOINTS ncommits > $OUTPUT/ncommits.csv
time run-on-timestamped-samples $NPOINTS nauthors > $OUTPUT/nauthors.csv
time run-on-timestamped-samples $NPOINTS ncommitters > $OUTPUT/ncommitters.csv
time run-on-timestamped-samples $NPOINTS nfiles > $OUTPUT/nfiles.csv
time run-on-timestamped-samples $NPOINTS volumes > $OUTPUT/volumes.csv

git checkout -qf $DEFAULT_BRANCH # clean up after yourself

(( elapsed_seconds = SECONDS - begin_notebook ))
(( minutes = elapsed_seconds / 60 ))
seconds=$((elapsed_seconds - minutes*60))
printf "Total elapsed time %02d:%02d\n" $minutes $seconds
