#!/bin/bash

if [ ! -d "$1" ] || [ ! -d "$1/mission.sqm" ] || [ ! -d "$1/init.sqf" ]
then
    echo "Please specify the mission folder"
    exit 1
fi

MISSION_FOLDER=$(readlink -f $1)
MISSION_NAME=$(basename "$MISSION_FOLDER")

# Clone lastest FA3
git clone -q https://github.com/Raptoer/F3.git $MISSION_NAME.updated

# Move into new mission folder
command pushd $MISSION_NAME.updated > /dev/null

# Create a new branch to hold the mission files
git checkout -q -b mission

# Clear out the current files and copy in the mission
rm -r ./* .gitignore
cp -r "$MISSION_FOLDER"/* .
cp -r "$MISSION_FOLDER"/.gitignore .gitignore

# Commit the mission
git add . &> /dev/null
git commit -m "Mission" &> /dev/null

## Find the most likely commit this mission was derived from
# Don't compare ws_fnc to prevent poisoning due to the mission maker updating ws_fnc themselves
FILES_TO_COMPARE=$(find -type f -not -path "*.git/*" -not -path "*ws_fnc/*")
CANDIDATE_COMMITS=$(
    for FILE in $FILES_TO_COMPARE
    do
        REV_COMMITS=$(git rev-list --branches=master master -- $FILE)

        for COMMIT in $REV_COMMITS
        do
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
    done | sort -nr | head -1 | awk '{print $2}'
)

# Create branch with sensible mission history
git checkout $LIKELY_COMMIT -b updated
rm -r ./* .gitignore
cp -r "$MISSION_FOLDER"/* .
cp -r "$MISSION_FOLDER"/.gitignore .gitignore
git add . &> /dev/null
git commit -m "Changes" &> /dev/null

# Rebase the branch to update to latest version
git rebase master

# Use mission version of mission.sqm
git checkout --theirs mission.sqm
git add mission.sqm

echo "The mission has now been updated as much as can be done automatically."
echo "Please run git status to find out which files couldn't be automatically updated, and finish the rebase process after fixing the conflicts"
echo "Remember to delete the .git folder before PBO-ing the updated mission"

# Return
command popd > /dev/null
