current_branch() { git symbolic-ref --short HEAD; }
commits() { local top=${1:-HEAD}; git rev-list --abbrev-commit --reverse $top; } # define a function

ncommits() { commits $1 | wc -l; }

committers() { git shortlog -ns ${1:-HEAD}; }
ncommitters() { committers $1 | wc -l; }

# count the files in the named commit without checking them out
files() { git ls-tree -r --full-tree --name-only ${1:-HEAD}; }
nfiles() { files $1 | wc -l; }
first_revision=$(git rev-list --all | tail -1)
