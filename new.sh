#!/bin/bash -eu

die() {
    echo "$@" >&2
    exit 1
}

set-globals() {
    NPOINTS=1000
    RESULTS=/tmp
    SIZES=$RESULTS/sizes
    TIMES=$RESULTS/times
    REVS=""
    SPW=$(( 60*60*24*7 ))  # calculate and save seconds-per-week as a shell constant
}

set-locals() {
    project=$1
    PROJ_SIZES=$SIZES/$project
    PROJ_TIMES=$TIMES/$project
    mkdir -p $PROJ_TIMES $PROJ_SIZES
    DEFAULT_BRANCH=$(basename $(git symbolic-ref --short refs/remotes/origin/HEAD))  # master, main, ... whatever
    FIRST_COMMIT=$(git rev-list $REVS --reverse $DEFAULT_BRANCH | head -1)  # initial commit in current repo
    SKIP=$(skip-size-for $NPOINTS)
    set-rev-list
}

# Housekeeping
## track how long the whole thing takes
report-elapsed-time() {
    local elapsed_seconds minutes seconds
    (( elapsed_seconds = SECONDS - begin_script ))
    (( minutes = elapsed_seconds / 60 ))
    seconds=$((elapsed_seconds - minutes*60))
    printf "Total elapsed time %02d:%02d\n" $minutes $seconds | tee $TIMES/total.times
}

## cleanliness is next to godliness
get-default-branch() {
    CURRENT_BRANCH=$(git branch --show-current)
    [ $CURRENT_BRANCH == $DEFAULT_BRANCH ] ||
        git checkout -qf $DEFAULT_BRANCH
}
revs() {
    git rev-list --abbrev-commit --reverse $DEFAULT_BRANCH
}
nrevs() {
    revs | wc -l
}
skip-size-for() {
    echo $(($(nrevs)/$1))
}
sample-revs(){
    revs | gsplit -n r/1/$SKIP
}
set-rev-list() {
    : ${REV_LIST:="$(sample-revs)"}
}
ncommits() {
    local sample=1;
    for rev in $*; do
        echo $rev,$sample
        ((sample += $SKIP))
    done
}
timestamps() {
    for rev in $*; do
        echo $rev,$(timestamp-in-weeks $rev)
    done
}

## collect timing data
timeit() {
    local func=$1
    shift
    {
        echo == $func
        time $func $* > $PROJ_SIZES/$func.csv
        echo
    } &> $PROJ_TIMES/$func.times
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
# Argument parsing ## all repos to traverse
repo-list() {
    echo "$@"
    cat .repos
}

## extract project name from URL
project-name() {
    basename $1 .git
}

## report data for current repo
collect-nocheckout-data() {
    for func in ncommits timestamps; do
        timeit $func $REV_LIST &
    done
    wait
}

main() {
    local cmdline_args="$@"
    set-globals
    for repo in $(repo-list $cmdline_args); do
        local project=$(project-name $repo)
        [ -d $project ] || git clone -q $repo  # if it's not already local, clone from URL
        (   # in a subshell
            cd $project > /dev/null
            echo == calculating sizes of project $project in $PWD ==
            set-locals $project
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
    # main "$@"
    main
    report-elapsed-time
fi
