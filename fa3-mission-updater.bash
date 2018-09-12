#!/bin/bash
# Licensed under the terms of the Apache License, version 2.0.

# Enable "Unofficial Bash Strict Mode" (http://redsymbol.net/articles/unofficial-bash-strict-mode/)
set -euo pipefail
IFS=$'\n\t'

if [ ! -d "$1" ] || [ ! -e "$1/mission.sqm" ] || [ ! -e "$1/init.sqf" ]
then
    echo "Please specify the mission folder"
    exit 1
fi

MISSION_FOLDER=$(readlink -f "$1")
MISSION_NAME=$(basename "$MISSION_FOLDER")
NEW_MISSION_NAME="$MISSION_NAME.updated"

# Change the working directory to the same as MISSION_FOLDER
cd "$(dirname "$MISSION_FOLDER")"

# Clone lastest FA3
echo "Cloning latest FA3 to $PWD/$NEW_MISSION_NAME"
git clone -q https://github.com/Raptoer/F3.git "$NEW_MISSION_NAME"

echo "Working out mission FA3 version"

# Create a new branch to hold the mission files
command pushd "$NEW_MISSION_NAME" > /dev/null
git checkout -q -b mission
command popd > /dev/null

# Clear out the current files and copy in the mission
rm -r "$NEW_MISSION_NAME"/*
cp -r "$MISSION_FOLDER"/* "$NEW_MISSION_NAME/"

# Commit the mission
command pushd "$NEW_MISSION_NAME" > /dev/null
git add . &> /dev/null
git commit -m "Mission" &> /dev/null

## Find the most likely commit this mission was derived from
FILES_TO_COMPARE=$(find -type f -iname '*.sqf' -or -iname '*.hpp' -or -iname '*.xml' -or -iname '*.ext')
CANDIDATE_COMMITS=$(
    for FILE in $FILES_TO_COMPARE
    do
        REV_COMMITS=$(git rev-list heads/master -- $FILE)

        for COMMIT in $REV_COMMITS
        do
            for exclude in "${@:2}"
            do
                if [[ $COMMIT = $exclude* ]]
                then
                    continue 2
                fi
            done

            git diff -s --exit-code $COMMIT mission -- $FILE
            if [ $? -eq 0 ]
            then
                echo $COMMIT
                break
            fi
        done
    done
)
# Find the most recent candidate commit
LIKELY_COMMIT=$(
    for COMMIT in $CANDIDATE_COMMITS
    do
        echo $(git log -1 --pretty=format:%ct $COMMIT) $COMMIT
    done | sort -nr -k 1 | head -1 | awk '{print $2}'
)
LIKELY_COMMIT_DESC=$(git describe --always $LIKELY_COMMIT)

echo "Mission was likely created from $LIKELY_COMMIT_DESC (commit $LIKELY_COMMIT):"
git log -1 --format=medium $LIKELY_COMMIT

echo -n "Continue? [yn] "
read PROMPT_RESPONSE
if [[ $PROMPT_RESPONSE != "y" ]]
then
    exit 1
fi

NEW_MISSION_NAME_COMMIT="$NEW_MISSION_NAME-$LIKELY_COMMIT_DESC"
echo "Moving workspace from $NEW_MISSION_NAME to $NEW_MISSION_NAME_COMMIT"
command popd > /dev/null
mv "$NEW_MISSION_NAME" "$NEW_MISSION_NAME_COMMIT"
NEW_MISSION_NAME="$NEW_MISSION_NAME_COMMIT"
command pushd "$NEW_MISSION_NAME" > /dev/null

echo "Attempting automatic update"

# Create branch with sensible mission history
git checkout $LIKELY_COMMIT -b updated
command popd > /dev/null
rm -r "$NEW_MISSION_NAME"/*
cp -r "$MISSION_FOLDER"/* "$NEW_MISSION_NAME/"
command pushd "$NEW_MISSION_NAME" > /dev/null
git add . &> /dev/null
git commit -m "Changes" &> /dev/null

# Rebase the branch to update to latest version
git rebase master || true

# Heuristics

# Use mission version of mission.sqm
git checkout --theirs mission.sqm
git add mission.sqm

# Use template version (ours) for adds and deletes
for conflicted in $(git status --short | grep -E '^AA|^UD|^AU' | awk '{print $2}')
do
    git checkout --ours $conflicted
    git add $conflicted
done
for conflicted in $(git status --short | grep -E '^DU' | awk '{print $2}')
do
    git add $conflicted
done

# Use the template version of README.md
git checkout --ours README.md
git add README.md

# /Heuristics

# Run the mergetool to finish the rebase
git mergetool

echo "The mission has now been updated as much as can be done automatically."
echo "Please run git status to find out which files couldn't be automatically updated, and finish the rebase process after fixing the conflicts"
echo "Remember to delete the .git folder before PBO-ing the updated mission"
