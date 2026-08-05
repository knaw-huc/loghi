#!/bin/bash
VERSION=2.3.1alpha
set -e
set -o pipefail


# User-configurable parameters
# Percentage split for training and validation sets
trainsplit=90

# Include text styles in the output
include_text_styles=1

# Skip unclear text regions
skip_unclear=1

# DO NOT MODIFY BELOW THIS LINE
# ------------------------------

# Function to provide usage instructions
function usage() {
  echo "Usage: create-train-data.sh <input_path> <output_path> [numthreads]"
  echo "input_path: path to images and pagexml to be converted. The pageXML must be one level deeper"
  echo "            than the images in a directory called \"page\""
  echo "output_path: path to store the training data"
  echo "numthreads: number of threads to use for processing the images (default: 4)"
}

# Argument validation 
if [ "$#" -lt 2 ]; then
  echo "Illegal number of parameters"
  usage
  exit 1
fi

# Set default number of threads and allow override
numthreads=4
if [ -n "$3" ]; then
  numthreads=$3
  echo "Setting numthreads=$numthreads"
fi

# Obtain absolute paths for input and output directories
inputdir=$(realpath $1/)
outputdir=$(realpath $2/)

mkdir -p $outputdir

# Prepare file lists
filelist=$outputdir/training_all.txt
filelisttrain=$outputdir/training_all_train.txt
filelistval=$outputdir/training_all_val.txt

# Docker image for Loghi tooling
DOCKERLOGHITOOLING=loghi/docker.loghi-tooling:$VERSION

# Flags for Loghi processing
# Check user input and set flag accordingly
if [[ $include_text_styles -eq 1 ]]; then
  INCLUDETEXTSTYLES=" -include_text_styles "
else
  INCLUDETEXTSTYLES=""
fi
if [[ $skip_unclear -eq 1 ]]; then
  SKIP_UNCLEAR=" -skip_unclear "
else
  SKIP_UNCLEAR=""
fi

# Housekeeping: remove any existing *.done files
find $inputdir -name '*.done' -exec rm {} \;

# Informative output
echo "Input directory: $inputdir"
echo "Output directory: $outputdir"
echo "File lists:"
echo "  All: $filelist"
echo "  Training: $filelisttrain"
echo "  Validation: $filelistval"
echo "Input files: $(find $inputdir | wc -l)"

# Run Loghi's MinionCutFromImageBasedOnPageXMLNew in Docker
echo "Running image segmentation and text extraction..."
docker run -u $(id -u ${USER}):$(id -g ${USER}) --rm \
       -v $inputdir/:$inputdir/ \
       -v $outputdir:$outputdir \
       $DOCKERLOGHITOOLING \
       /src/loghi-tooling/minions/target/appassembler/bin/MinionCutFromImageBasedOnPageXMLNew \
       -input_path $inputdir \
       -outputbase $outputdir \
       -channels 4 \
       -output_type png \
       -write_text_contents \
       -threads $numthreads \
       $INCLUDETEXTSTYLES \
       -no_page_update \
       $SKIP_UNCLEAR \
       -use_2013_namespace

echo "Output files: $(find $outputdir | wc -l)"

# Generate the image/text pair list
echo "Generating file lists..."
> $filelist
old_ifs="$IFS"; IFS=$(echo -en "\n\b");
for input_path in $(find $outputdir -name '*.png'); do
  filename=${input_path##*/}
  filename="${filename%.*}"
  base="${input_path%.*}"
  text=$(< $base.txt)
  echo -e "$input_path\t$text" >> $filelist
done
IFS=$old_ifs

# Create training and validation file lists
echo "Splitting data into training and validation sets..."
shuf $filelist | split -l $(( $(wc -l <$filelist) * $trainsplit / 100 ))
mv xab $filelistval
mv xaa $filelisttrain
