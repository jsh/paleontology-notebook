#!/bin/bash -eu
# combine output files into single, csv file
source .config
RESULTS=/tmp
SIZES=$RESULTS/sizes
TIMES=$RESULTS/times

## track how long the whole thing takes
report-elapsed-time() {
    local elapsed_seconds minutes seconds
    (( elapsed_seconds = SECONDS - begin_script ))
    (( minutes = elapsed_seconds / 60 ))
    seconds=$((elapsed_seconds - minutes*60))
    printf "Total elapsed time %02d:%02d\n" $minutes $seconds | tee $TIMES/total.times
}


# combine all csv files into a single, summary csv
summarize() {
    local results=$1
    (
        cd $results        # do this in a subshell, so you don't have to track the cds
        cat nweeks.csv |
            join -t, - ncommits.csv |
            join -t, - ncommitters.csv |
            join -t, - nauthors.csv |
            join -t, - nfiles.csv |
            sed 's/ //g' > all.csv
    ) 
}

main() {
    # summarize all repos
    for results in $SIZES/*; do
        summarize $results
    done
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
