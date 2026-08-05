#!/bin/bash
VERSION=2.3.1alpha
set -e
set -o pipefail

# User-configurable parameters
# Model configuration

# Set to 1 to finetune an existing model, 0 to train a new model
USEBASEMODEL=0
HTRBASEMODEL=PATH_TO_HTR_BASE_MODEL

# Define a VGSL model
# This is only used if USEBASEMODEL is set to 0
# We recommend using the recommended model from the model library
HTRNEWMODEL="recommended"

# Used gpu ids, set to "-1" to use CPU, "0" for first, "1" for second, etc
GPU=0

# Dataset and training configuration
listdir=PATH_TO_LISTDIR
trainlist=$listdir/training_all_train.txt
validationlist=$listdir/training_all_val.txt

# If the images are not in subpath of listdir add the path to your actual images,
# Defaults to /tmp/path_to_training_images
datadir=/tmp/path_to_training_images

# Training configuration
epochs=1
multiply=1

# Replace the final layer during basemodel finetuning
# This is recommended if your data contains many characters that the model has not been trained on
REPLACEFINALLAYER=0

# Best not to go lower than 2 with batchsize
batch_size=40
model_name=myfirstmodel
learning_rate=0.0003

tmpdir=$(mktemp -d)

#set the outputdir
outputdir=$tmpdir/output
# example outputdir to /home/loghiuser/loghi-model-output
#outputdir=/home/loghiuser/loghi-model-output


# DO NOT MODIFY BELOW THIS LINE
# ------------------------------

DOCKERLOGHIHTR=loghi/docker.htr:$VERSION


# Set new model as default
MODEL=$HTRNEWMODEL
MODELDIR=""
REPLACEFINAL=""

#DO NOT REMOVE THIS PLACEHOLDER LINE, IT IS USED FOR AUTOMATIC TESTING"
#PLACEHOLDER#

mkdir -p $outputdir

# Base model option
if [[ $USEBASEMODEL -eq 1 ]]; then
    MODEL=$HTRBASEMODEL
    MODELDIR="-v $(dirname "${MODEL}"):$(dirname "${MODEL}")"
    echo $MODELDIR
fi

# Replace final layer option
if [[ $REPLACEFINALLAYER -eq 1 ]]; then
    REPLACEFINAL="--replace_final_layer"
    echo $MODELDIR
fi

# GPU options
DOCKERGPUPARAMS=""
if [[ $GPU -gt -1 ]]; then
    DOCKERGPUPARAMS="--gpus device=${GPU}"
    echo "Using GPU ${GPU}"
fi


# Starting the training
echo "Starting Loghi HTR training with model $MODEL"
docker run $DOCKERGPUPARAMS --rm -u $(id -u ${USER}):$(id -g ${USER}) -m 32000m --shm-size 10240m -ti \
    $MODELDIR \
    -v $tmpdir:$tmpdir \
    -v $listdir:$listdir \
    -v $datadir:$datadir \
    -v $outputdir:$outputdir \
    $DOCKERLOGHIHTR \
        bash -c "TF_USE_LEGACY_KERAS=0 python3 /src/loghi-htr/src/main.py \
        --train_list $trainlist \
        --do_validate \
        --validation_list $validationlist \
        --learning_rate $learning_rate \
        --batch_size $batch_size \
        --epochs $epochs \
        --gpu $GPU \
        --seed 1 \
        --beam_width 1 \
        --model $MODEL \
        --aug_multiply $multiply \
        --model_name $model_name \
        --output $outputdir \
        $REPLACEFINAL "

echo "Results can be found at:"
echo $tmpdir
