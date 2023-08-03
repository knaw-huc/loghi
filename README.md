# Loghi

Loghi is a set of tools for Handwritten Text Recognition. 

Two sample scripts are provided to make starting everything a little bit easier. 
na-pipeline.sh: for transcribing scans
na-pipeline-train.sh: for training new models. 

## Quick start

Install Loghi so that you can use its pipeline script.
```bash
git clone https://github.com/knaw-huc/loghi.git
cd loghi
```

## Use the docker images
The easiest method to run Loghi is to use the default dockers images on [Docker Hub](https://hub.docker.com/u/loghi).
The docker images are usually pulled automatically when running [`na-pipeline.sh`](na-pipeline.sh) mentioned later in this document, but you can pull them separately with the following commands:

```bash
docker pull loghi/docker.laypa
docker pull loghi/docker.htr
docker pull loghi/docker.loghi-tooling
```

If you do not have Docker installed follow [these instructions](https://docs.docker.com/engine/install/) to install it on your local machine.

If you instead want to build the dockers yourself with the latest code:
```bash
git submodule update --init --recursive
cd docker
./buildAll.sh
```
This also allows you to have a look at the source code inside the dockers. The source code is available in the submodules.


## Inference

But first go to:
https://surfdrive.surf.nl/files/index.php/s/YA8HJuukIUKznSP
and download a laypa model (for detection of baselines) and a loghi-htr model (for HTR).

suggestion for laypa:
- general

suggestion for loghi-htr that should give some results:
- generic-2023-02-15

It is not perfect, but a good starting point. It should work ok on 17th and 18th century handwritten dutch. For best results always finetune on your own specific data.

edit the [`na-pipeline.sh`](na-pipeline.sh) using vi, nano, other whatever editor you prefer. We'll use nano in this example

```bash
nano na-pipeline.sh
```
Look for the following lines:
```
LAYPAMODEL=INSERT_FULL_PATH_TO_YAML_HERE
LAYPAMODELWEIGHTS=INSERT_FULLPATH_TO_PTH_HERE
HTRLOGHIMODEL=INSERT_FULL_PATH_TO_LOGHI_HTR_MODEL_HERE
```
and update those paths with the location of the files you just downloaded. If you downloaded a zip: you should unzip it first.

if you do not have a NVIDIA-GPU and nvidia-docker setup additionally change

```text
GPU=0
```
to
```text
GPU=-1
```
It will then run on CPU, which will be very slow. If you are using the pretrained model and run on CPU: please make sure to download the Loghi-htr model starting with "float32-". This will run faster on CPU than the default mixed_float16 models.


Save the file and run it:
```bash
./na-pipeline.sh /PATH_TO_FOLDER_CONTAINING_IMAGES
```
replace /PATH_TO_FOLDER_CONTAINING_IMAGES with a valid directory containing images (.jpg is preferred/tested) directly below it.

The file should run for a short while if you have a good nvidia GPU and nvidia-docker setup. It might be a long while if you just have CPU available. It should work either way, just a lot slower on CPU.

When it finishes without errors a new folder called "page" should be created in the directory with the images. This contains the PageXML output.

## Training an HTR model

### Input data

Expected structure
```text
training_data_folder
|- training_all_train.txt
|- training_all_val.txt
|- image1_snippets
    |-snippet1.png
    |-snippet2.png
```

`training_all_train.txt` should look something something like:
```text
/path/to/training_data_folder/image1_snippets/snippet1.png	textual representation of snippet 1
/path/to/training_data_folder/image1_snippets//snippet2.png text on snippet 2
```
n.b. path to image and textual representation should be separated by a tab.

##### Create training data
You can create training data with the following command:
```bash
./create_train_data.sh /full/path/to/input /full/path/to/output
```
`/full/path/to/output` is `/full/path/to/training_data_folder` in this example
`/full/path/to/input` is expected to look like:
```text
input
|- image1.png
|- image2.png
|- page
    |- image1.xml
    |- image2.xml
```
`page/image1.xml` should contain information about the baselines and should have the textual representation of the text lines.  

### Change script
Edit the [`na-pipeline-train.sh`](na-pipeline-train.sh) script using your favorite editor:

```bash
nano na-pipeline-train.sh
```

Find the following lines:
```text
listdir=INSERT_FULL_PATH_TO_TRAINING_DATA_FOLDER
trainlist=INSERT_FULL_PATH_TO_TRAINING_DATA_LIST
validationlist=INSERT_FULL_PATH_TO_VALIDATION_DATA_LIST
```
In this example: 
```text
listdir=/full/path/to/training_data_folder
trainlist=/full/path/to/training_data_folder/train_list.txt
validationlist=/full/path/to/training_data_folder/val_list.txt
```

if you do not have a NVIDIA-GPU and nvidia-docker setup additionally change:

```text
GPU=0
```
to
```text
GPU=-1
```
It will then run on CPU, which will be very slow.


### Run script
Finally, to run the HTR training run the script:

```bash
./na-pipeline-train.sh
```

## For later updates use:
To update the submodules to the head of their branch (the latest/possibly unstable version) run the following command:
```bash
git submodule update --recursive --remote
```

