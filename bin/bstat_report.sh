#!/bin/bash

source bstats.sh
begin_notebook=$SECONDS

echo There have been $(ncommits --all) total commits
echo There have been $(ncommits) commits in $(current_branch)
echo There have been $(ncommitters) committers
echo there are currently $(nfiles) files
echo the SHA1 of the first revision was $first_revision
echo the first revision had $(nfiles $first_revision) files

echo the "first revision:"; echo

git log -1 $first_revision | cat

(( elapsed_seconds = SECONDS - begin_notebook ))
(( minutes = elapsed_seconds / 60 ))
seconds=$((elapsed_seconds - minutes*60))
printf "Elapsed time running notebook %02d:%02d\n" $minutes $seconds
