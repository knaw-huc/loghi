#!/bin/bash
VERSION=2.3.1alpha
set -e
set -o pipefail

CURRENT=$(pwd)

DIR_OF_SCRIPT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR_OF_SCRIPT

BASE="$(realpath $DIR_OF_SCRIPT/..)"

echo pulling base
cd $BASE
git pull
git submodule update --recursive --remote

echo pulling prima-core-libs
cd $BASE/prima-core-libs
git switch master
git pull

echo pulling loghi-tooling
cd $BASE/loghi-tooling
git switch main
git pull

echo pulling loghi-htr
cd $BASE/loghi-htr
git switch master
git pull

echo pulling laypa
cd $BASE/laypa
git switch main
git pull

cd $DIR_OF_SCRIPT

echo "building docker.base"
cd docker.base
./buildImage.sh
cd ..
echo "building docker.loghi-tooling"
cd docker.loghi-tooling/
./buildImage.sh $BASE/prima-core-libs/ $BASE/loghi-tooling $VERSION
cd ..
echo "building docker.htr"
cd docker.htr
./buildImage.sh
cd ..
echo "building docker.htr-wsl"
cd docker.htr-wsl
./buildImage.sh
cd ..
echo "building docker.laypa"
cd docker.laypa
./buildImage.sh $BASE/laypa
cd ..

docker tag loghi/docker.loghi-tooling:latest loghi/docker.loghi-tooling:$VERSION
docker tag loghi/docker.htr:latest loghi/docker.htr:$VERSION
docker tag loghi/docker.htr-wsl:latest loghi/docker.htr-wsl:$VERSION
docker tag loghi/docker.laypa:latest loghi/docker.laypa:$VERSION
