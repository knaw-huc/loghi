#!/bin/bash
#docker rmi docker.base
set -e

echo "Change to directory of script..."
DIR_OF_SCRIPT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR_OF_SCRIPT

echo "Building docker image..."
docker build --no-cache . -t docker.base
#docker build --squash --no-cache . -t docker.base
echo "Saving docker image..."
#docker save docker.base >/data/docker/docker.base.tar

