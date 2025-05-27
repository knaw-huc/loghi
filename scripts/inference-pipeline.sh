#!/bin/bash
VERSION=2.2.18
set -e
set -o pipefail

# User-configurable parameters
# Stop on error, if set to 1 will exit program if any of the docker commands fail
STOPONERROR=1

# set to 1 if you want to enable the baseline or region prediction, 0 otherwise
BASELINELAYPA=1
REGIONLAYPA=0

# Set the path to the yaml file and the pth file for the Laypa baseline model. Not required if BASELINELAYPA is 0
LAYPABASELINEMODEL=INSERT_FULL_PATH_TO_YAML_HERE
LAYPABASELINEMODELWEIGHTS=INSERT_FULLPATH_TO_PTH_HERE

# Set the path to the yaml file and the pth file for the Laypa region model. Not required if REGIONLAYPA is 0
LAYPAREGIONMODEL=INSERT_FULL_PATH_TO_YAML_HERE
LAYPAREGIONMODELWEIGHTS=INSERT_FULLPATH_TO_PTH_HERE

# Set to 1 if you want to enable the HTR step, 0 otherwise
HTRLOGHI=1
# Set the path to the htr model. Not required if HTRLOGHI is 0
HTRLOGHIMODEL=INSERT_FULL_PATH_TO_LOGHI_HTR_MODEL_HERE

# Set this to 1 for recalculating reading order, line clustering and cleaning.
# WARNING this will remove regions found by Laypa
RECALCULATEREADINGORDER=1
# If the edge of baseline is closer than x pixels...
RECALCULATEREADINGORDERBORDERMARGIN=50
# Clean borders if 1
RECALCULATEREADINGORDERCLEANBORDERS=0
# How many threads to use for recalculating reading order
RECALCULATEREADINGORDERTHREADS=4

# Detect language of pagexml, set to 1 to enable, 0 otherwise
DETECTLANGUAGE=1
# Interpolate word locations
SPLITWORDS=1
# BEAMWIDTH: higher makes results slightly better at the expense of lot of computation time. In general don't set higher than 10
BEAMWIDTH=1
# Used gpu ids, set to "-1" to use CPU, "0" for first, "1" for second, etc
GPU=0

# Use 2013 PageXML namespace, set to 1 to enable, 0 otherwise
USE2013NAMESPACE=1

# DO NOT MODIFY BELOW THIS LINE
# ------------------------------

function check_error_and_exit {
    # $1 - The error message to display
    # $2 - The status of the last command executed before the function was called

    if [[ $STOPONERROR -eq 1 && $2 -ne 0 ]]; then
        echo "$1 has failed"
        exit 1
    fi
}

# Check for proper command-line arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_images>"
    exit 1
fi


DOCKERLOGHITOOLING=loghi/docker.loghi-tooling:$VERSION
DOCKERLAYPA=loghi/docker.laypa:$VERSION
DOCKERLOGHIHTR=loghi/docker.htr:$VERSION

DOCKERGPUPARAMS=""
if [[ $GPU -gt -1 ]]; then
    DOCKERGPUPARAMS="--gpus device=${GPU}"
    echo "Using GPU ${GPU}"
fi

IMAGES_PATH=`realpath $1`

tmpdir=$(mktemp -d --tmpdir=$IMAGES_PATH tmp.loghi-inference-XXXXXX)
echo "Temporary directory created at: $tmpdir"

mkdir -p "$tmpdir"/imagesnippets/
mkdir -p "$tmpdir"/output

# Housekeeping: remove any existing *.done files
find "$IMAGES_PATH" -name '*.done' -exec rm -f "{}" \;

if [[ $USE2013NAMESPACE -eq 1 ]]; then
    namespace=" -use_2013_namespace "
fi

# First step: Laypa
if [[ $BASELINELAYPA -eq 1 ]]; then
    echo "Running Laypa baseline detection"

    LAYPADIR="$(dirname "${LAYPABASELINEMODEL}")"

    docker run $DOCKERGPUPARAMS --rm -it -u $(id -u "${USER}"):$(id -g "${USER}") -m 32000m --shm-size 10240m \
        -v "$LAYPADIR":"$LAYPADIR" \
        -v "$IMAGES_PATH":"$IMAGES_PATH" \
        $DOCKERLAYPA \
            python run.py \
            -c $LAYPABASELINEMODEL \
            -i "$IMAGES_PATH" \
            -o "$IMAGES_PATH" \
            --opts MODEL.WEIGHTS "" TEST.WEIGHTS $LAYPABASELINEMODELWEIGHTS | tee -a "$tmpdir"/log.txt

    # Check if failed
    status=$?
    check_error_and_exit "Laypa baseline detection" $status

    # Set as_single_region flag by default
    as_single_region=" -as_single_region "
    echo "Laypa baseline detection done"

    if [[ $REGIONLAYPA -eq 1 ]]; then
        echo "Running Laypa region detection"
        LAYPAREGIONDIR="$(dirname "${LAYPAREGIONMODEL}")"

        docker run $DOCKERGPUPARAMS --rm -it -u $(id -u "${USER}"):$(id -g "${USER}") -m 32000m --shm-size 10240m \
        -v "$LAYPAREGIONDIR":"$LAYPAREGIONDIR" \
        -v "$IMAGES_PATH":"$IMAGES_PATH" \
        $DOCKERLAYPA \
            python run.py \
            -c $LAYPAREGIONMODEL \
            -i "$IMAGES_PATH" \
            -o "$IMAGES_PATH" \
            --opts MODEL.WEIGHTS "" TEST.WEIGHTS $LAYPAREGIONMODELWEIGHTS | tee -a $tmpdir/log.txt

        # Check if failed
        status=$?
        check_error_and_exit "Laypa region detection" $status

        as_single_region=""
        echo "Laypa region detection done"
    fi

    # Second step: extract baselines and regions
    echo "Extracting baselines and regions"

    docker run --rm -u $(id -u "${USER}"):$(id -g "${USER}") \
        -v "$IMAGES_PATH":"$IMAGES_PATH" \
        $DOCKERLOGHITOOLING \
            /src/loghi-tooling/minions/target/appassembler/bin/MinionExtractBaselines \
            -input_path_image "$IMAGES_PATH" \
            -input_path_png "$IMAGES_PATH"/page/ \
            -input_path_page "$IMAGES_PATH"/page/ \
            -output_path_page "$IMAGES_PATH"/page/ \
            -recalculate_textline_contours_from_baselines \
            $as_single_region \
            $namespace | tee -a "$tmpdir"/log.txt

    # Check if failed
    status=$?
    check_error_and_exit "MinionExtractBaselines" $status

    echo "Extracting baselines and regions done"
fi

# Third step: cut out snippets
if [[ $HTRLOGHI -eq 1 ]]; then
    echo "Cutting out snippets"

    docker run -u $(id -u "${USER}"):$(id -g "${USER}") --rm \
       -v "$IMAGES_PATH"/:"$IMAGES_PATH"/ \
       $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionCutFromImageBasedOnPageXMLNew \
           -input_path "$IMAGES_PATH" \
           -outputbase "$tmpdir"/imagesnippets/ \
           -tmpdir "$tmpdir" \
           -output_type png \
           -channels 4 \
           -threads 4 $namespace| tee -a "$tmpdir"/log.txt

    # Check if failed
    status=$?
    check_error_and_exit "MinionCutFromImageBasedOnPageXMLNew" $status

    # Collect all the snippets in a file
    find "$tmpdir"/imagesnippets/ -type f -name '*.png' > "$tmpdir"/lines.txt

    echo "Running HTR"
    LOGHIDIR="$(dirname "${HTRLOGHIMODEL}")"

    echo docker run $DOCKERGPUPARAMS -u $(id -u "${USER}"):$(id -g "${USER}") --rm -m 32000m --shm-size 10240m -ti \
        -v "$tmpdir":"$tmpdir" \
        -v "$LOGHIDIR":"$LOGHIDIR" \
        $DOCKERLOGHIHTR \
            bash -c "LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4 python3 /src/loghi-htr/src/main.py \
            --model $HTRLOGHIMODEL  \
            --batch_size 64 \
            --inference_list $tmpdir/lines.txt \
            --results_file $tmpdir/results.txt \
            --gpu $GPU \
            --output $tmpdir/output/ \
            --beam_width $BEAMWIDTH " | tee -a "$tmpdir"/log.txt


    docker run $DOCKERGPUPARAMS -u $(id -u "${USER}"):$(id -g "${USER}") --rm -m 32000m --shm-size 10240m -ti \
        -v "$tmpdir":"$tmpdir" \
        -v "$LOGHIDIR":"$LOGHIDIR" \
        $DOCKERLOGHIHTR \
            bash -c "LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4 python3 /src/loghi-htr/src/main.py \
            --model $HTRLOGHIMODEL  \
            --batch_size 64 \
            --inference_list $tmpdir/lines.txt \
            --results_file $tmpdir/results.txt \
            --gpu $GPU \
            --output $tmpdir/output/ \
            --beam_width $BEAMWIDTH " | tee -a "$tmpdir"/log.txt

    # Check if failed
    status=$?
    check_error_and_exit "Loghi HTR" $status
    
    echo "Loghi HTR done"

    # Fourth step: merge results back into PageXML
    docker run -u $(id -u "${USER}"):$(id -g "${USER}") --rm \
        -v "$LOGHIDIR":"$LOGHIDIR" \
        -v "$IMAGES_PATH"/:"$IMAGES_PATH"/ \
        $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionLoghiHTRMergePageXML \
            -input_path "$IMAGES_PATH"/page \
            -results_file "$tmpdir"/results.txt \
            -config_file $HTRLOGHIMODEL/config.json \
            -htr_code_config_file "$tmpdir"/output/config.json \
            $namespace | tee -a "$tmpdir"/log.txt

    # Check if failed
    status=$?
    check_error_and_exit "MinionLoghiHTRMergePageXML" $status
    
    echo "Merging HTR results into PageXML done"
fi

# Fifth step: Recalculate reading order
if [[ $RECALCULATEREADINGORDER -eq 1 ]]; then
    echo "Recalculating reading order"
    clean_borders=""

    if [[ $RECALCULATEREADINGORDERCLEANBORDERS -eq 1 ]]; then
        echo "and cleaning borders"
        clean_borders=" -clean_borders "
    fi
    docker run -u $(id -u "${USER}"):$(id -g "${USER}") --rm \
        -v "$IMAGES_PATH"/:"$IMAGES_PATH"/ \
        $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionRecalculateReadingOrderNew \
            -input_dir "$IMAGES_PATH"/page/ \
            -border_margin $RECALCULATEREADINGORDERBORDERMARGIN \
            -threads $RECALCULATEREADINGORDERTHREADS \
            $clean_borders \
            $namespace| tee -a "$tmpdir"/log.txt

    # Check if failed
    status=$?
    check_error_and_exit "MinionRecalculateReadingOrder" $status
fi


if [[ $DETECTLANGUAGE -eq 1 ]]; then
    echo "Detecting language..."
    docker run -u $(id -u "${USER}"):$(id -g "${USER}") --rm \
        -v "$IMAGES_PATH"/:"$IMAGES_PATH"/ \
        $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionDetectLanguageOfPageXml \
            -page "$IMAGES_PATH"/page/ \
            $namespace | tee -a "$tmpdir"/log.txt

    # Check if failed
    status=$?
    check_error_and_exit "MinionDetectLanguageOfPageXml" $status
fi


if [[ $SPLITWORDS -eq 1 ]]; then
    echo "MinionSplitPageXMLTextLineIntoWords..."
    docker run -u $(id -u "${USER}"):$(id -g "${USER}") --rm \
        -v "$IMAGES_PATH"/:"$IMAGES_PATH"/ \
        $DOCKERLOGHITOOLING /src/loghi-tooling/minions/target/appassembler/bin/MinionSplitPageXMLTextLineIntoWords \
            -input_path "$IMAGES_PATH"/page/ \
            $namespace | tee -a "$tmpdir"/log.txt

    # Check if failed
    status=$?
    check_error_and_exit "MinionSplitPageXMLTextLineIntoWords" $status
fi

# cleanup results
rm -rf "$tmpdir"
