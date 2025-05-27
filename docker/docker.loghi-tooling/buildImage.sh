#!/bin/bash

set -e

if [ -z $1 ]; then echo "first parameter should be the path of prima-core-libs" && exit 1; fi;
if [ -z $2 ]; then echo "second parameter should be the path of loghi-tooling" && exit 1; fi;
if [ -z $3 ]; then echo "third parameter should be version which loghi-tooling will get" && exit 1; fi;

PRIMACORELIBS="$(realpath $1)"
LOGHITOOLING="$(realpath $2)"
LOGHI_VERSION=$3

echo "Change to directory of script..."
DIR_OF_SCRIPT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR_OF_SCRIPT

dependency_check_data_dir="$HOME/.m2/repository/org/owasp/dependency-check-data"

echo "Copy files for building docker..."
cp -r $PRIMACORELIBS .
cp -r $LOGHITOOLING .
if [ ! -d "$dependency_check_data_dir" ]; then
    mkdir -p dependency-check-data
    echo "dependency-check-data directory created (did not exist)."
else
    cp -r "$dependency_check_data_dir" ./
    echo "dependency-check-data directory copied."
fi

rm -rf ./prima-core-libs/.git
rm -rf ./prima-core-libs/target
rm -rf ./prima-core-libs/java/PrimaBasic/target
rm -rf ./loghi-tooling/.git
rm -rf ./loghi-tooling/target
rm -rf ./loghi-tooling/layoutanalyzer/target
rm -rf ./loghi-tooling/minions/target
rm -rf ./loghi-tooling/layoutds/target
rm -rf ./loghi-tooling/layoutanalyzer/src/test/resources/in/*.png

echo "Building docker image..."

docker build --no-cache -t loghi/docker.loghi-tooling --build-arg LOGHI_VERSION=$LOGHI_VERSION .
echo "cleaning up!"
rm -rf prima-core-libs
rm -rf loghi-tooling
rm -rf dependency-check-data

docker system prune -f
