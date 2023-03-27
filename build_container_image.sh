#!/bin/bash

# Author: Gemma Hoad (ghoad@sfu.ca)

SCRIPT=$(readlink -f "$0")

print_help_text() {
  printf "\nCreate a Singularity/Apptainer container. You can choose to make a sif file or a sandbox. Input source can be a def file, Dockerfile or Docker image.\n\n$SCRIPT [-h|-d|-s|-i] [-a <def file>] [-b <myproject/docker-repository-name>] [-c <docker image>] -t <tool_name_for_output_file/directory> -v <tool_version_for_output_file/directory>\n\n"
  echo "-a      build Apptainer image from def file recipe (<myfile.def>)"
  echo "-b      build Apptainer image from a Dockerfile. You must run this script from the directory containing the Dockerfile. The value required by this option is the image name to be created, e.g. projectname/repository-name, i.e. the value expected if you were to run 'docker build -t myproject/repository-name .'"
  echo "-c      create Apptainer image from Docker image (<myimage:mytag>)"
  echo "-t      name of the tool container to build. This will be combined with the version to make either the sif file name being built (option -i) or the directory in which the image files will be placed (option -s) e.g. enter '/home/myusername/mynewtool' to create /home/myusername/mynewtool-1.0.0 or /home/myusername/mynewtool-1.0.0.sif (depending on the version and sandbox/sif mode entered). Lack of path will create the new file(s) in the current working directory."
  echo "-v      version of the tool to be added to the output filename e.g. '1.28'. This is combined with the tool name prefix to create for example mytool-1.28.sif or mytool-1.28/"
  echo "-s      make sandbox. This is a directory containing all the image files and is writable. Either -i or -s must be chosen. Not both."
  echo "-i      make sif file. This file is like a compressed directory structure and is read-only. Either -i or -s must be chosen. Not both."
  echo "-d      Dry run - commands are displayed, but not run"
  echo "-h      show help text"
  printf "\n"
}

# if there are no input parameters, print help and exit
if [ $# = 0 ]
then
  print_help_text
  exit 0
fi

dry_run=false
sandbox_mode=false
sif_image_mode=false
#retrieve arguments with flags
while getopts "a:b:c:v:t:sihd" opt; do
    case $opt in
        a) def_file=$OPTARG;;
        b) dockerproject=$OPTARG;;
        c) docker_image=$OPTARG;;
        v) version=$OPTARG;;
        t) tool_name=$OPTARG;;
        s) sandbox_mode=true;;
        i) sif_image_mode=true;;
        h) print_help_text;
           exit 0;;
        d) dry_run=true;;
       \?) echo "ERROR: Invalid option"
           exit 0;;
    esac
done

# debug statements
#echo "def_file       = $def_file";
#echo "dockerproject  = $dockerproject";
#echo "tool_name      = $tool_name";
#echo "sandbox_mode   = $sandbox_mode";
#echo "sif_image_mode = $sif_image_mode";
#echo "version        = $version";
#echo "docker_image   = $docker_image";
#echo "dry_run        = $dry_run";
#printf "\n"

# Bail if too many options are provided 
# (i.e. if user requests sif file builds from multiple sources)
if ( [ ! -z $def_file ] && [ ! -z $dockerproject ] ) ||
        ( [ ! -z $def_file ] && [ ! -z $docker_image ] ) ||
        ( [ ! -z $docker_image ] && [ ! -z $dockerproject ] );
then
  echo "ERROR: You must use options -a (build from def file), -b (build from Dockerfile - myuser/repository-name) and -c (build from docker image) exclusively (not together)."
  exit 1
fi

if [ $sandbox_mode = true ] && [ $sif_image_mode = true ];
then
  echo "ERROR: Please choose to create the Apptainer image as either a sif file (-i) or sandbox directory of files (-s). Not both."
  exit 1
elif  [ $sandbox_mode = false ] && [ $sif_image_mode = false ];
then
  echo "ERROR: Please choose to create the Apptainer image as either a sif file (-i) or sandbox directory of files (-s). One of these 2 options is required."
  exit 1
fi


# if string is defined and file does not exist, bail.
if [ ! -z $def_file ] && [ ! -f $def_file ];
then
  echo "ERROR: File not found (-a option): $def_file"
  exit 1;
fi

# if string is defined and Dockerfile does not exist in the current directory, bail.
if  [ ! -z $dockerproject ] && [ ! -f "Dockerfile" ];
then
  echo "ERROR: Dockerfile not found. Please change directory to where the Dockerfile is located."
  exit 1;
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
  echo "ERROR: Absent tool name (-t <tool_name>) in arguments provided. This is the prefix of the file or directory being built by the script and will have the -v version number added (final result example: mytool-2.34 directory or mytool-2.34.sif). This file or directory must *not* already exist."
  exit 1;
else
  # build sif file name: toolname-version.sif
  tool_and_version="$tool_name-$version"
  if [ $sandbox_mode = true ]; then
    printf "Building $tool_and_version\n"
  else
    printf "Building $tool_and_version.sif\n"
  fi
fi

# if building a sif file from a dockerfile or image, 
# podman must be installed, or bail.
if [ ! -z $dockerproject ] || [ ! -z $docker_image ];
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


# if sif file already exists, bail. Likewise for sandbox directory if requested.
if [ $sif_image_mode = true ] && [ -f "${tool_and_version}.sif" ];
then
  echo "ERROR: sif file already exists: $tool_and_version.sif"
  echo "Please move this file before continuing."
  exit 1;
elif [ $sandbox_mode = true ] && [ -d $tool_and_version ]; then
  echo "ERROR: sandbox directory already exists: $tool_and_version"
  echo "Please move this file before continuing."
  exit 1;
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
success_msg="\nBuild completed successfully!\nNew Apptainer/Singularity image: $tool_and_version"
if [ $sif_image_mode = true ]; then
  success_msg+=".sif"
fi
success_msg+="\n"

# mode 1: build apptainer image from def file
if [ ! -z $def_file ]; then
  if [ $sandbox_mode = true ]; then
    cmd="apptainer build --force --sandbox $tool_and_version $def_file"
    echo "Building image in sandbox directory from def file (creating Apptainer image from recipe)"
  else
    cmd="apptainer build --force ${tool_and_version}.sif $def_file"
    echo "Building sif file from def file (creating Apptainer image from recipe)"
  fi

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

# We've upgraded this script to using podman which does not need root privs.
## if we've reached this stage, we need to be root to access the docker images
##if [ "$EUID" -ne 0 ]
##  then echo "Please run as root, so the script can access podman images"
##  exit
##fi


# mode 2: build apptainer image from Dockerfile
if [ ! -z $dockerproject ]; then

  cmd1="podman build -t $dockerproject ."
  if [ $sandbox_mode = true ]; then
    cmd2="apptainer build --sandbox $tool_and_version $(podman images | awk '{print $1}' | awk 'NR==2')"
  else
    cmd2="apptainer build ${tool_and_version}.sif $(podman images | awk '{print $1}' | awk 'NR==2')"
  fi

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
if [ ! -z $docker_image ]; then

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

  if [ $sandbox_mode = true ]; then
    cmd="apptainer build --sandbox $tool_and_version $docker_image"
  else
    cmd="apptainer build ${tool_and_version}.sif $docker_image"
  fi

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
