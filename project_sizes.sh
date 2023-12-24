#!/bin/bash -eu

# Housekeeping: utility functions
## print message to stderr and fail
die() {
    echo "$@" >&2
    exit 1
}
## cleanliness is next to godliness
get-default-branch() {
    CURRENT_BRANCH=$(git branch --show-current)
    [ $CURRENT_BRANCH == $DEFAULT_BRANCH ] ||
        git checkout -qf $DEFAULT_BRANCH
}


# Setup variables
## script variables set once, used in several places
set-globals() {
    SPW=$(( 60*60*24*7 ))  # calculate and save seconds-per-week as a shell constant
    # plus some defaults
    REVS=""
    NPOINTS=1000
    RESULTS=/tmp
    FUNCS="ncommits nweeks nauthors ncommitters nfiles"
}

## per-project variables
set-locals() {
    project=$1
    # output locations
    PROJ_SIZES=$RESULTS/sizes/$project
    PROJ_TIMES=$RESULTS/times/$project
    mkdir -p $PROJ_TIMES $PROJ_SIZES
    # misc. per-project variables
    DEFAULT_BRANCH=$(basename $(git symbolic-ref --short refs/remotes/origin/HEAD))  # master, main, ... whatever
    SKIP=$(skip-size-for $NPOINTS)
    set-rev-list
    FIRST_COMMIT=$(head -1 <<< "$REV_LIST") # initial commit in current repo
}

# Revisions to work on.
## all revisions
revs() {
    git rev-list $REVS --abbrev-commit --reverse $DEFAULT_BRANCH
}
## total revisions
nrevs() {
    revs | wc -l
}
## number of revisions to skip between samples
skip-size-for() {
    echo $(( $(nrevs)/$1 ))
}
## evenly spaced sample revisions
sample-revs(){
    revs |                     # list of evenly spaced revisions,
        gsplit -n r/1/$SKIP    # separated by $SKIP, starting with first commit
}
## cache the list in REV_LIST
set-rev-list() {
    : ${REV_LIST:="$(sample-revs)"}     # calculate once per project
}

# Data-collection
## commits per revision
ncommits() {
    local sample=1;
    for rev in $*; do
        echo $rev,$sample
        ((sample += $SKIP))
    done
}
## weeks after initial commit, each revision
nweeks() {
    for rev in $*; do
        echo $rev,$(timestamp-in-weeks $rev)
    done
}
## number of authors at each revision
nauthors() {
    for rev in $*; do
        echo $rev,$(git shortlog $REVS -sa $rev | wc -l)
    done
}
## number of committers at each revision
ncommitters() {
    for rev in $*; do
        echo $rev,$(git shortlog $REVS -sc $rev | wc -l)
    done
}
## all files in a revision
files() { git ls-tree -r --full-tree --name-only ${1:-HEAD}; }
## number of files at each revision
nfiles() {
    for rev in $*; do
        echo $rev,$(files $rev | wc -l)
    done
}
## complete data for current repo
collect-nocheckout-data() {
    for func in $FUNCS; do
        timeit $func $REV_LIST &
    done
    wait
}
## combine all csv files into a single, summary csv
add-suffix() {
    suffix=$1; shift
    for name in $*; do
        echo $name.$suffix
    done
}

# join a list of files
multi-join() {
    local first="yes"
    for file in $*
    do
        if [ $first = "yes" ]; then
            command="cat $file"
            first="no"
        else
            command+=" | join -t, - $file"
        fi
    done
    eval "$command"
}

summarize() {
    local dir=$1
    (
        cd $dir        # do this in a subshell, so you don't have to track the cds
        local files=$(add-suffix csv $FUNCS)
        multi-join $files |
            sed 's/ //g'
    ) 
}


# Timing the script
## how long to collect one data set?
timeit() {
    local func=$1
    shift
    {
        echo == $func
        time $func $* > $PROJ_SIZES/$func.csv
        echo
    } &> $PROJ_TIMES/$func.times
}
## how long to run this whole script?
report-elapsed-time() {
    local elapsed_seconds minutes seconds
    (( elapsed_seconds = SECONDS - begin_script ))
    (( minutes = elapsed_seconds / 60 ))
    seconds=$((elapsed_seconds - minutes*60))
    printf "Total elapsed time %02d:%02d\n" $minutes $seconds
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

# Argument parsing
## all repos to traverse
repo-list() {
    echo "$@"             # repos on command line
    sed s'/#.*$//' .repos  # file of repo names, comments allowed
}
## extract project name from URL
project-name() {
    basename $1 .git
}
## variables set in .config file override built-in defaults
##  File is just assignments, e.g.,
##
##      # example .config file
##      REVS="--first-parent"    # just look at the first parent
##      NPOINTS=10               # do only 10 points
##      FUNCS="ncommits nweeks"  # just report these data
##
read-config() {
    [ -f .config ] && source .config
}

# Put them all together, they spell "MOTHER."
main() {
    local cmdline_args="$@"
    set-globals
    read-config
    for repo in $(repo-list $cmdline_args); do
        local project=$(project-name $repo)
        [ -d $project ] || git clone -q $repo  # if it's not already local, clone from URL
        (   # in a subshell
            cd $project > /dev/null
            echo == calculating sizes of project $project in $PWD ==
            set-locals $project
            collect-nocheckout-data
            summarize $PROJ_SIZES > $RESULTS/$project.csv
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
    report-elapsed-time | tee $RESULTS/total.times
fi
