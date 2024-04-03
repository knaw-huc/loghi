#!/bin/bash
VERSION=2.0.0
set -e

# User-configurable parameters
# Model configuration
HTRLOGHIMODELHEIGHT=64

# Set to 1 to finetune an existing model, 0 to train a new model
USEBASEMODEL=0
HTRBASEMODEL=PATH_TO_HTR_BASE_MODEL

# Define a VGSL model
# This is only used if USEBASEMODEL is set to 0
# We recommend using the recommended model from the model library
HTRNEWMODEL="recommended"
# Set channels to 1 to process input as grayscale, 3 for color, 4 for color and mask
channels=1

# Used gpu ids, set to "-1" to use CPU, "0" for first, "1" for second, etc
GPU=0

# Dataset and training configuration
listdir=/data/ovdr/gt-split/
trainlist=$listdir/val.txt
validationlist=$listdir/val_150hs.txt

# The path to your actual images
datadir=/data/ovdr/gt-split/val/

# Training configuration
epochs=1
height=$HTRLOGHIMODELHEIGHT
multiply=1

# Best not to go lower than 2 with batchsize
batch_size=40
model_name=myfirstmodel
learning_rate=0.0003

# DO NOT MODIFY BELOW THIS LINE
# ------------------------------

DOCKERLOGHIHTR=loghi/docker.htr:$VERSION

tmpdir=$(mktemp -d)
mkdir -p $tmpdir/output

# Set new model as default
MODEL=$HTRNEWMODEL
MODELDIR=""

# Base model option
if [[ $USEBASEMODEL -eq 1 ]]; then
    MODEL=" --model "$MODEL
    MODELDIR="-v $(dirname "${MODEL}"):$(dirname "${MODEL}")"
fi

# GPU options
DOCKERGPUPARAMS=""
if [[ $GPU -gt -1 ]]; then
    DOCKERGPUPARAMS="--gpus device=${GPU}"
    echo "Using GPU ${GPU}"
fi

# Starting the training
echo "Starting Loghi HTR training with model $MODEL"
docker run $DOCKERGPUPARAMS --rm  -u $(id -u ${USER}):$(id -g ${USER}) -m 32000m --shm-size 10240m -ti \
    $MODELDIR \
    -v $tmpdir:$tmpdir \
    -v $listdir:$listdir \
    -v $datadir:$datadir \
    $DOCKERLOGHIHTR \
        python3 /src/loghi-htr/src/main.py \
        --train_list $trainlist \
        --do_validate \
        --validation_list $validationlist \
        --learning_rate $learning_rate \
        --channels $channels \
        --batch_size $batch_size \
        --epochs $epochs \
        --gpu $GPU \
        --height $height \
        --use_mask \
        --seed 1 \
        --beam_width 1 \
        --model $MODEL \
        --aug_multiply $multiply \
        --model_name $model_name \
        --output $tmpdir/output

echo "Results can be found at:"
echo $tmpdir
