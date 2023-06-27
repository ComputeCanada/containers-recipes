#!/bin/bash

# Author: Gemma Hoad (ghoad@sfu.ca)
# Author: Maxime Boissonneault (maxime.boissonneault@calculquebec.ca)

SCRIPT=$(readlink -f "$0")

if [[ ! -z $CONTAINER_BUILDER_TARGET_DIR ]]; then
	TARGET_DIR=$CONTAINER_BUILDER_TARGET_DIR
else
	TARGET_DIR=$PWD
fi
if [[ ! -z $CONTAINER_BUILDER_SOURCE_DIR ]]; then
	SOURCE_DIR=$CONTAINER_BUILDER_SOURCE_DIR
else
	SOURCE_DIR=$PWD
fi
if [[ ! -z $CONTAINER_BUILDER_SIF_ALLOWED ]]; then
	SIF_ALLOWED=$CONTAINER_BUILDER_SIF_ALLOWED
else
	SIF_ALLOWED=1
fi
if [[ ! -z $CONTAINER_BUILDER_SANDBOX_ALLOWED ]]; then
	SANDBOX_ALLOWED=$CONTAINER_BUILDER_SANDBOX_ALLOWED
else
	SANDBOX_ALLOWED=1
fi
TARGET_CONTAINER=
WORK_DIR=/tmp/container-builder-$RANDOM

print_help_text() {
  printf "\nCreate a Singularity/Apptainer container. You can choose to make a sif file or a sandbox. Input source can be a def file, Dockerfile or Docker image.\n\n$SCRIPT [-h|-d] -t <sandbox|sif> -n <tool_name_for_output_file/directory> -v <tool_version_for_output_file/directory> -s <myproject/docker-repository-name>|<myimage:mytag>|<myfile.def>\n\n"
  echo "-i      Input source type, one of <def|Dockerfile|image>"
  echo "-n      name of the tool container to build. This will be combined with the version to make the container (either sif or directory) e.g. enter 'mynewtool' to create mynewtool-1.0.0 or mynewtool-1.0.0.sif (depending on the version and sandbox/sif mode entered). Will be created relative to the current working directory."
  echo "-s      Source to use. Can be a def file, Dockerfile or Docker image name, according to the option -i."
  echo "         - Building from Dockerfile: the value should be the path to the Dockerfile"
  echo "         - Building from a podman pull image: the value shold be the parameter you would typically pass to podman pull or docker pull"
  echo "         - Building from def file recipe: the value should be <myfile.def>"
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
while getopts "v:t:n:s:i:hd" opt; do
    case $opt in
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

echo "Working in directory $WORK_DIR"
mkdir -p $WORK_DIR && cd $WORK_DIR

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
    module load podman
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
module load apptainer/1.1
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
    else
      printf $failed_msg
      exit 1;
    fi
  else
    exit 0; # exit from dry run
  fi
fi

# mode 2: build apptainer image from Dockerfile
# mode 3: build apptaimer image from pulling docker
if [[ "$source_type" == "Dockerfile" || "$source_type" == "image" ]]; then
  if [[ "$source_type" == "Dockerfile" ]]; then
    dockerproject="$(basename $(dirname $source_file)).$RANDOM"
    tmp_tarball="${dockerproject}.tar"
    cmd1="podman build --no-cache -t $dockerproject -f $source_file"
    grep $USER /etc/subuid > /dev/null || echo "WARNING: User $USER does not have subuid privilege on this node. Some builds may fail. Contact your administrator if needed."
    grep $USER /etc/subgid > /dev/null || echo "WARNING: User $USER does not have subgid privilege on this node. Some builds may fail. Contact your administrator if needed."
  else
    dockerproject="$source_name"
    tmp_tarball="$(basename $source_name | cut -d':' -f1).tar"
    cmd1="podman pull $source_name"
  fi
  cmd2="podman save --format oci-archive -o $tmp_tarball $dockerproject"
  cmd3="apptainer build ${APPTAINER_ARGS[@]} $TARGET_CONTAINER oci-archive://$tmp_tarball" 
  cmd4="rm $tmp_tarball"
  cmd5="podman rmi $dockerproject"

  if [ $dry_run = true ]; then
    printf "Commands that run when not in dry_run (-d) mode:\n"
    echo "  $cmd1"
    echo "  $cmd2"
    echo "  $cmd3"
    echo "  $cmd4"
    echo "  $cmd5"
  else
    printf "** Running: $cmd1\n"
    $cmd1 && command1_success=1

    if [ $command1_success = 1 ]; then
      printf "\n** Running: $cmd2\n"
      $cmd2 && command2_success=1
    fi
    if [ $command2_success = 1 ]; then
      printf "\n** Running: $cmd3\n"
      $cmd3 |& grep -v "EPERM" && command3_success=1
    fi
    if [ $command3_success = 1 ]; then
      printf "\n** Running: $cmd4\n"
      $cmd4 && command4_success=1
    fi
    if [ $command4_success = 1 ]; then
      printf "\n** Running: $cmd5\n"
      $cmd5 && command5_success=1
    fi
  fi

  echo "command1_success: $command1_success"
  echo "command2_success: $command2_success"
  echo "command3_success: $command3_success"
  echo "command4_success: $command4_success"
  echo "command5_success: $command5_success"
  echo "dry_run         : $dry_run"
  printf "success_msg     : $success_msg"

  if  [ $dry_run = true ]; then
    if [ $command1_success = 1 ] && [ $command2_success = 1 ] && [ $command3_success = 1] && [ $command4_success = 1] && [ $command5_success = 1]; then
      printf $success_msg
    else
      printf $failed_msg
      exit 1;
    fi
  else
    exit 0; # exit from dry run
  fi
fi

echo "Adjusting permissions of $TARGET_CONTAINER with chmod -R u+w go+rX"
chmod -R u+w go+rX $TARGET_CONTAINER

echo "Cleaning up $WORK_DIR"
rm -rf $WORK_DIR
