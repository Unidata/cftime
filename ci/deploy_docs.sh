#!/bin/bash
set -e # exit with nonzero exit code if anything fails
export GH_PAGES_DIR="$HOME/gh-pages"

# Decrypt and activate the deploy key
echo Setting up access...
openssl aes-256-cbc -K $encrypted_2f711532c6dd_key -iv $encrypted_2f711532c6dd_iv -in ${TRAVIS_BUILD_DIR}/ci/deploy_key.enc -out ${TRAVIS_BUILD_DIR}/ci/deploy_key -d
chmod 600 ${TRAVIS_BUILD_DIR}/ci/deploy_key
eval `ssh-agent -s`
ssh-add ${TRAVIS_BUILD_DIR}/ci/deploy_key

# Clone *this* git repo, but only the gh-pages branch.
echo Cloning gh-pages...
if [[ ! -d $GH_PAGES_DIR ]]; then
    git clone -q -b gh-pages --single-branch git@github.com:${TRAVIS_REPO_SLUG}.git $GH_PAGES_DIR
fi
cd $GH_PAGES_DIR

# inside this git repo we'll pretend to be a new user
git config user.name "Travis CI"
git config user.email "travis@nobody.org"

# The first and only commit to this new Git repo contains all the
# files present with the commit message "Deploy to GitHub Pages".
echo Updating docs...
cp -R ${TRAVIS_BUILD_DIR}/docs/_build/html/ ./
touch .nojekyll

echo Staging...
git add -A .
git commit --amend --reset-author --no-edit

# Push up to gh-pages
echo Pushing...
git push --force origin gh-pages
