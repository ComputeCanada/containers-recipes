# Container Scripts

## build_container_script.sh
This script will build a Singularity/Apptainer image. It can build this using 3 optional sources:
- a def file (singularity definition file, listing the image build commands)
- a Dockerfile (Docker equivalent of a singularity def file - contains system build commmands)
- a Docker image

The latter two input sources require docker to be installed and sudo access.

This script can output 2 optional Apptainer image formats:
- sif file (bundled image)
- directory of container files ('sandbox' unbundled image)

```
Create a Singularity/Apptainer container. You can choose to make a sif file or a sandbox. Input source can be a def file, Dockerfile or Docker image.

./build_container_image.sh [-h|-d|-s|-i] [-a <def file>] [-b <myproject/docker-repository-name>] [-c <docker image>] -t <tool_name_for_output_file/directory> -v <tool_version_for_output_file/directory>

-a      build Apptainer image from def file recipe (<myfile.def>)
-b      build Apptainer image from a Dockerfile. You must run this script from the directory containing the Dockerfile. The value required by this option is the image name to be created, e.g. projectname/repository-name, i.e. the value expected if you were to run 'docker build -t myproject/repository-name .'
-c      create Apptainer image from Docker image (<myimage:mytag>)
-t      name of the tool container image to build. This will be combined with the version to make either the sif file name being built (option -i) or the directory in which the image files will be placed (option -s) e.g. enter '/home/myusername/mynewtool' to create /home/myusername/mynewtool-1.0.0 or /home/myusername/mynewtool-1.0.0.sif (depending on the version and sandbox/sif mode entered). Lack of path will create the new file(s) in the current working directory.
-i      make sif file. This file is like a compressed directory structure and is read-only. Either -i or -s must be chosen. Not both.
-s      make sandbox. This is a directory containing all the image files and is writable.  Either -i or -s must be chosen. Not both.
-v      version of the tool to be added to the output filename e.g. '1.28'. This is combined with the toolname prefix (-t) to create, for example, mytool-1.28.sif or mytool-1.28/
-d      Dry run - commands are displayed, but not run
-h      show help text
```
