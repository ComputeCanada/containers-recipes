# Dockerfile to run genpipes in a container
# Genpipes in a container repository: https://github.com/c3g/genpipes_in_a_container
# Main Genpipes repository: https://bitbucket.org/mugqic/genpipes/src
# Author: Pierre-Olivier Quirion (@poquirion)  
#
# To run with podman
# podman run  --rm   --device /dev/fuse --cap-add SYS_ADMIN  -it  -v /tmp:/tmp  --mount type=volume,source=cvmfs_cache,destination=/cvmfs-cache  <genpipes_image> 
# To run with singularity
# mkdir ~/cvmfs_cache
# singularity run  -S /var/run/cvmfs -B ~/cvmfs_cache:/cvmfs-cache --fusemount "container:cvmfs2 cvmfs-config.computecanada.ca /cvmfs/cvmfs-config.computecanada.ca"    --fusemount "container:cvmfs2 soft.mugqic /cvmfs/soft.mugqic"   --fusemount "container:cvmfs2 ref.mugqic /cvmfs/ref.mugqic" <genpipes_image>

FROM centos:7.9.2009
MAINTAINER P-O Quirion po.quirion@mcgill.ca

WORKDIR /tmp

# All yum cmd

ENV CVMFS_VERSION latest
ENV CC_STACK latest
ENV MODULE_VERSION 4.1.2
RUN yum install -y https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-${CVMFS_VERSION}.noarch.rpm \
             https://package.computecanada.ca/yum/cc-cvmfs-public/prod/RPM/computecanada-release-${CC_STACK}.noarch.rpm
RUN yum update -y \
  && yum install -y ImageMagick pigz which wget unzip.x86_64 make.x86_64 gcc expectk file \
  dejagnu less tcl-devel.x86_64 cvmfs-config-computecanada \
  cvmfs-fuse3 cvmfs-config-default \
  && yum clean all

RUN mkdir /cvmfs-cache  && chmod 777 /cvmfs-cache  /cvmfs
RUN mkdir /cvmfs/ref.mugqic /cvmfs/soft.mugqic /cvmfs/cvmfs-config.computecanada.ca

# module
RUN wget https://github.com/cea-hpc/modules/releases/download/v${MODULE_VERSION}/modules-${MODULE_VERSION}.tar.gz
RUN tar xzf modules-${MODULE_VERSION}.tar.gz && \
    rm modules-${MODULE_VERSION}.tar.gz \
    && cd  modules-${MODULE_VERSION}  && ./configure && make -j 7  && make install \
    && cd .. && rm -rf modules-${MODULE_VERSION} && rm -rf /usr/local/Modules/modulefiles/*
# CVMFS
ADD default.local /etc/cvmfs/default.local
ADD soft.mugqic.local /etc/cvmfs/config.d/soft.mugqic.local
ADD ref.mugqic.local /etc/cvmfs/config.d/ref.mugqic.local

RUN ["ln", "-s", "/usr/local/Modules/init/profile.sh", "/etc/profile.d/z00_module.sh"]
RUN echo "source /etc/profile.d/z00_module.sh" >>  /etc/bashrc
ADD devmodule/genpipes "/usr/local/Modules/modulefiles/."


ADD genpipesrc    /usr/local/etc/genpiperc
RUN ["ln", "-s", "/usr/local/etc/genpiperc", "/etc/profile.d/z90_genpipes.sh"]

ADD init_genpipes /usr/local/bin/init_genpipes
RUN chmod 755 /usr/local/bin/init_genpipes
ENTRYPOINT ["init_genpipes"]
