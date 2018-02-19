#!/bin/bash -e
#
# Deploy your branch on VIP Go.
#

# This script uses various Circle CI and Travis CI environment 
# variables, Circle prefix their environment variables with 
# `CIRCLE_` and Travis with `TRAVIS_`. 
# Documentation:
# https://circleci.com/docs/1.0/environment-variables/
# https://docs.travis-ci.com/user/environment-variables/

set -ex

DEPLOY_SUFFIX="-built"

BRANCH="${CIRCLE_BRANCH:-$TRAVIS_BRANCH}"
SRC_DIR="${TRAVIS_BUILD_DIR:-$PWD}"
BUILD_DIR="/tmp/vip-go-build"

if [[ -z "$BRANCH" ]]; then
	echo "No branch specified!"
	exit 1
fi

if [[ -d "$BUILD_DIR" ]]; then
	echo "WARNING: ${BUILD_DIR} already exists. You may have accidentally cached this"
	echo "directory. This will cause issues with deploying."
	exit 1
fi

cd $SRC_DIR

if [[ $CIRCLECI ]]; then
	CIRCLE_REPO_SLUG="${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}";
fi
REPO_SLUG=${CIRCLE_REPO_SLUG:-$TRAVIS_REPO_SLUG}
REPO_SSH_URL="git@github.com:${REPO_SLUG}"
COMMIT_SHA=${CIRCLE_SHA1:-$TRAVIS_COMMIT}
DEPLOY_BRANCH="${BRANCH}${DEPLOY_SUFFIX}"

if [[ "$BRANCH" == *${DEPLOY_SUFFIX} ]]; then
	echo "WARNING: Attempting to build from branch '${BRANCH}' to deploy '${DEPLOY_BRANCH}', seems like recursion so aborting."
	exit 0
fi

echo "Deploying $BRANCH to $DEPLOY_BRANCH"

# By default, this script will use the name and email of the
# author of the current commit, and use those when deploying
# the built code. If you want to override this, you can set
# the `DEPLOY_GIT_USER` and/or `DEPLOY_GIT_EMAIL` environment
# variables. Documentation links for environment variables on
# Circle CI and Travis CI are above.
COMMIT_USER_NAME="$( git log --format=%ce -n 1 $COMMIT_SHA )"
COMMIT_USER_EMAIL="$( git log --format=%cn -n 1 $COMMIT_SHA )"
GIT_USER="${DEPLOY_GIT_USER:-$COMMIT_USER_NAME}"
GIT_EMAIL="${DEPLOY_GIT_EMAIL:-$COMMIT_USER_EMAIL}"

git clone "$REPO_SSH_URL" "$BUILD_DIR"
cd "$BUILD_DIR"
git fetch origin
# If the deploy branch doesn't already exist, create it from the empty root.
if ! git rev-parse --verify "remotes/origin/$DEPLOY_BRANCH" >/dev/null 2>&1; then
	echo -e "\nCreating $DEPLOY_BRANCH..."
	git checkout --orphan "${DEPLOY_BRANCH}"
else
	echo "Using existing $DEPLOY_BRANCH"
	git checkout "${DEPLOY_BRANCH}"
fi

# Ensure we're in the right dir
cd "$BUILD_DIR"

# Remove existing files
git rm -rfq .

# Sync built files
if ! command -v 'rsync'; then
	sudo apt-get install -q -y rsync
fi

echo "Syncing files... quietly"
rsync --cvs-exclude -a "$SRC_DIR/" "$BUILD_DIR" --exclude-from "$SRC_DIR/ci/deploy-exclude.txt"

# Add changed files
git add -A .

if [ -z "$(git status --porcelain)" ]; then
	echo "No changes to deploy"
	exit 0
fi

# Commit it.
MESSAGE=$( printf 'Build changes from %s\n\n%s' "${COMMIT_SHA}" "${CIRCLE_BUILD_URL}" )
# Set the Author to the commit (expected to be a client dev) and the committer
# will be set to the default Git user for this CI system
git commit --author="${GIT_USER} <${GIT_EMAIL}>" -m "$MESSAGE"

# Push it (push it real good).
git push origin "$DEPLOY_BRANCH"
