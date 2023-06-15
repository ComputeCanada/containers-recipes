#!/bin/bash

# Author: Gemma Hoad (ghoad@sfu.ca)

SCRIPT=$(readlink -f "$0")

TARGET_DIR=$PWD
SOURCE_DIR=$PWD
TARGET_CONTAINER=
SIF_ALLOWED=0
SANDBOX_ALLOWED=1


print_help_text() {
  printf "\nCreate a Singularity/Apptainer container. You can choose to make a sif file or a sandbox. Input source can be a def file, Dockerfile or Docker image.\n\n$SCRIPT [-h|-d] -t <sandbox|sif> [-b <myproject/docker-repository-name>] -n <tool_name_for_output_file/directory> -v <tool_version_for_output_file/directory>\n\n"
  echo "-b      build Apptainer image from a Dockerfile. The value required by this option is the image name to be created, e.g. projectname/repository-name, i.e. the value expected if you were to run 'docker build -t myproject/repository-name .'"
  echo "-i      Input source type, one of <def|Dockerfile|image>"
  echo "-n      name of the tool container to build. This will be combined with the version to make the container (either sif or directory) e.g. enter 'mynewtool' to create mynewtool-1.0.0 or mynewtool-1.0.0.sif (depending on the version and sandbox/sif mode entered). Will be created relative to the current working directory."
  echo "-s      Source to use. Can be a def file, Dockerfile or Docker image name, according to the option -i"
  echo "-v      version of the tool to be added to the output filename e.g. '1.28'. This is combined with the tool name prefix to create for example mytool-1.28.sif or mytool-1.28/"
  echo "-t      type of container to build. Either sandbox or sif, i.e. -t <sandbox|sif>"
  echo "-d      Dry run - commands are displayed, but not run"
  echo "-h      show help text"
  if [[ $SIF_ALLOWED -eq 0 ]]; then
	  echo "Note: creating SIF images is disabled"
  fi
  if [[ "$SANDBOX_ALLOWED" -eq 0 ]]; then
	  echo "Note: creating sandbox containers is disabled"
  fi
  printf "\n"
}

# if there are no input parameters, print help and exit
if [ $# = 0 ]
then
  print_help_text
  exit 0
fi

dry_run=false
#retrieve arguments with flags
while getopts "b:v:t:n:s:i:hd" opt; do
    case $opt in
        b) dockerproject=$OPTARG;;
	s) source_name=$OPTARG;;
	i) source_type=$OPTARG;;
        v) version=$OPTARG;;
        n) tool_name=$OPTARG;;
	t) container_type=$OPTARG;;
        h) print_help_text;
           exit 0;;
        d) dry_run=true;;
       \?) echo "ERROR: Invalid option"
           exit 0;;
    esac
done

# debug statements
#echo "dockerproject  = $dockerproject";
#echo "tool_name      = $tool_name";
#echo "container_type = $container_type";
#echo "version        = $version";
#echo "docker_image   = $docker_image";
#echo "dry_run        = $dry_run";
#printf "\n"

if [[ -z $source_name ]]; then
	echo "ERROR: You must specify a source (option -s)"
	exit 1
fi
if [[ "$source_type" != "def" && "$source_type" != "Dockerfile" && "$source_type" != "image" ]]; then
	echo "ERROR: Unknown source type $source_type. Source type (option -i) must be either def, Dockerfile or image"
	exit 1;
fi
if [[ "$source_type" == "def" || "$source_type" == "Dockerfile" ]]; then
	if [[ ${source_name::1} == "/" || ${source_name::1} == "." || ${source_name::1} == "~" ]]; then
		echo "ERROR: source file $source_name should not start with /, . or ~"
		echo "Please provide a relative path within $SOURCE_DIR"
		exit 1
	fi
	source_file=$SOURCE_DIR/$source_name
	if [[ ! -f $source_file ]]; then
		echo "ERROR: File not found $source_file"
		exit 1;
	fi
fi
if [[ "$source_type" == "Dockerfile" && -z $dockerproject ]]; then
	echo "ERROR: When using a Dockerfile, you must specify the name of a docker project (option -b)"
	exit 1
fi
if [[ "$container_type" != "sandbox" && "$container_type" != "sif" ]]; then
	echo "ERROR: Unknown container type requested: $container_type. Valid values for option -t are <sif|sandbox>."
	exit 1;
fi
if [[ "$container_type" == "sif" && "$SIF_ALLOWED" -eq 0 ]]; then
	echo "sif container requested, but sif support disabled. Please build the container as a sandbox"
	exit 1;
fi
if [[ "$container_type" == "sandbox" && "$SANDBOX_ALLOWED" -eq 0 ]]; then
	echo "sandbox container requested, but sandbox support disabled. Please build the container as a sif image"
	exit 1;
fi

APPTAINER_ARGS=()
if [[ "$container_type" == "sandbox" ]]; then
	APPTAINER_ARGS+=(--sandbox)
fi

# if version is absent or not numeric, bail.
if  [ -z $version ];
then
  echo "ERROR: Version missing. You must enter a version number for the tool. This will be added into the sif file name."
  exit 1;
else
  regex='^[0-9]+([.][0-9]+)*$'
  if ! [[ $version =~ $regex ]] ; then
    echo "ERROR: Version (-v) option is not a valid number.";
    exit 1;
  fi
fi

# remove .sif suffix from $tool_name, if it exists.
tool_name=${tool_name%.sif}

# if no tool name is entered, bail. Otherwise, build the full sif file/directory name.
if [ -z $tool_name ];
then
  echo "ERROR: Absent tool name (-n <tool_name>) in arguments provided. This is the prefix of the file or directory being built by the script and will have the -v version number added (final result example: mytool-2.34 directory or mytool-2.34.sif). This file or directory must *not* already exist."
  exit 1;
else
  # build sif file name: toolname-version.sif
  tool_and_version="$tool_name-$version"
  if [[ "$container_type" == "sandbox" ]]; then
    TARGET_CONTAINER="$TARGET_DIR/$tool_and_version"
  else
    TARGET_CONTAINER="$TARGET_DIR/$tool_and_version.sif"
  fi
  printf "Building $TARGET_CONTAINER\n"
fi


# if building a sif file from a dockerfile or image, 
# podman must be installed, or bail.
if [[ "$source_type" == "Dockerfile" || "$source_type" == "image" ]];
then
  if ! command -v podman &> /dev/null
  then
    `module load podman`
  fi

  if ! command -v podman &> /dev/null
  then
    echo "ERROR: podman will not install using the command 'module load podman'. It is required to build a sif file from a Dockerfile or docker image"
    exit 1;
  fi
fi


# if container already exists, bail
if [[ -e "$TARGET_CONTAINER" ]]; then
	echo "ERROR: container $TARGET_CONTAINER already exists. Please remove it before continuing."
	exit 1
fi

#----------------------------------------------------------------
# Now input option checks have been completed, build the sif file

echo "Loading apptainer modules..."
#module use /cvmfs/soft-dev.computecanada.ca/easybuild/modules/2020/Core
module load apptainer/1.1.3
printf "apptainer version: "
apptainer version

command1_success=0
command2_success=0
failed_msg="\nERROR: build failed\n"
success_msg="\nBuild completed successfully!\nNew Apptainer/Singularity image: $TARGET_CONTAINER\n"

# mode 1: build apptainer image from def file
if [[ "$source_type" == "def" ]]; then
  cmd="apptainer build ${APPTAINER_ARGS[@]} $TARGET_CONTAINER $source_file"
  echo "Building from def file (creating Apptainer image from recipe"

  if [ $dry_run = true ]; then
    printf "Command that runs when not in dry_run (-d) mode:\n  $cmd\n"
  else
    printf "** Running: $cmd\n"
    $cmd && command1_success=1
  fi

  if [ $dry_run = true ]; then
    if [ $command1_success = 1 ]; then
      printf $success_msg
      exit 0;
    else
      printf $failed_msg
      exit 1;
    fi
  else
    exit 0; # exit from dry run
  fi
fi

# mode 2: build apptainer image from Dockerfile
if [[ "$source_type" == "Dockerfile" ]]; then

  cmd1="podman build -t $dockerproject -f $source_file"
  cmd2="apptainer build ${APPTAINER_ARGS[@]} $TARGET_CONTAINER $(podman images | awk '{print $1}' | awk 'NR==2')"

  if [ $dry_run = true ]; then
    printf "Commands that run when not in dry_run (-d) mode:\n"
    echo "  $cmd1"
    echo "  $cmd2"
  else
    printf "** Running: $cmd1\n"
    $cmd1 && command1_success=1

    if [ $command1_success = 1 ]; then
      printf "\n** Running: $cmd2\n"
      $cmd2 && command2_success=1
    fi
  fi

  echo "command1_success: $command1_success"
  echo "command2_success: $command2_success"
  echo "dry_run         : $dry_run"
  printf "success_msg     : $success_msg"

  if  [ $dry_run = true ]; then
    if [ $command1_success = 1 ] && [ $command2_success = 1 ]; then
      printf $success_msg
      exit 0;
    else
      printf $failed_msg
      exit 1;
    fi
  else
    exit 0; # exit from dry run
  fi
fi


# mode 3: build apptainer image from docker image 
# (e.g. docker://myproject/myapp:latest)
# Creates a sif file named myapp_latest.sif in the current directory
if [[ "$source_type" == "image" ]]; then
  docker_image=$source_name

  # bail if docker image not found
  if [ -z "$(podman images -q $docker_image)" ]; then
    echo "ERROR: Docker image $docker_image not found locally"
    exit 1
  fi

  # add "docker://" prefix to image name for build command
  docker_image_regex="^docker://.*"

  if [ ! -z $docker_image ] && ! [[ "$docker_image" =~ $docker_image_regex ]];
  then
    docker_image="docker://$docker_image"
  fi

  cmd="apptainer build ${APPTAINER_ARGS[@]} $TARGET_CONTAINER $docker_image"
  
  if [ $dry_run = true ]; then
    printf "Command that runs when not in dry_run (-d) mode:\n\t$cmd\n"
  else
    printf "** Running: $cmd\n"
    $cmd && command1_success=1
  fi

  if  [ $dry_run = true ]; then
    if [ $command1_success = 1 ]; then
      printf $success_msg
      exit 0;
    else
      printf $failed_msg
      exit 1;
    fi
  else
    exit 0; # exit from dry run
  fi
fi  
