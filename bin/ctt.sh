source bstats.sh

every_commit() { 
    local func=$1 
    for commit in $(commits); do      # for every commit, first to last
        echo $commit $($func $commit) # run the function, and report the result with the commit's SHA1
    done
}


only_every() { awk "(NR-1)%$1 == 0"; }

mod() { # how many commits do I skip to get $1 points?
    local npoints=${1:-1}  # default to every commit
    local ncmts=$(ncommits)
    echo $(( ncmts/npoints ))
}

sample_revs() {
    git rev-list --reverse --abbrev-commit HEAD |  # listed from first to last
        only_every $(mod $1)
}

sample_commits() {
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

commit_time() { git log -1 --format=%ct $1; }

seconds_between (){ echo $(($(commit_time $2) - $(commit_time $1))); }

relative_date() { 
    first_commit=$(commits | head -1)   # find this once, and save the SHA1 in a global
    seconds_between $first_commit $1; 
}

timestamps_of_sample_commits() {
    sample_size=$1
    sample_commits $sample_size relative_date |
        nl -v 0 -i $(mod $sample_size)   # number the lines with the commit numbers
}

timestamp() {
    : ${first_commit:=$(git rev-list $(current_branch) --reverse | head -1)}  # this is magic
    seconds_between $first_commit $1
}
