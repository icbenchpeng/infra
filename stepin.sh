#!/bin/bash

ARGV=$*
ARGC=$#

BIN_FILE=$(readlink -f $0)
BIN_PATH=$(dirname ${BIN_FILE})
source $BIN_PATH/docker.cfg

if [ $ARGC -gt 0 ]; then
  next_docker_img=0
  next_mount=0
  next_mount_readonly=0
  for arg in $*; do
    case $arg in
    -h)
      echo "\
Usage $0 [options]

options:
  -gdb            load debug env
  -docker <name>  use docker: <name>
  -mount <dir>    docker mount <dir>
  -readonly <dir> docker mount <dir> as readonly
  others          if only with one tclscript, will use eden to lauch the script
                  otherwise use as bash commands
"
      exit
    ;;
    -docker)
      next_docker_img=1
    ;;
    -mount)
      next_mount=1
    ;;
    -readonly)
      next_mount_readonly=1
    ;;
    -gdb)
      DOCKER_IMG=$DEBUG_DOCKER_IMG
      if [ x$EDEN_HOME == x ]; then
        echo "Error: EDEN_HOME must be set for eden debug" && exit
      fi
    ;;
    *)
      if [ $next_docker_img == 1 ]; then
        DOCKER_IMG_special=$arg
        next_docker_img=0
        continue
      fi
      if [ $next_mount == 1 ]; then
        MOUNT_LIST="$MOUNT_LIST $arg"
        next_mount=0
        continue
      fi
      if [ $next_mount_readonly == 1 ]; then
        MOUNT_READONLY_LIST="$MOUNT_READONLY_LIST $arg"
        next_mount_readonly=0
        continue
      fi
      if [ -f $arg ]; then
        filename=$arg
        FILENAME=`realpath $filename`
        SCRIPTFILE_DIR=`dirname $FILENAME`
        MOUNT_LIST="$MOUNT_LIST $SCRIPTFILE_DIR"
        ext=${filename##*.}
        if [ "x$BASHSCRIPT" == x ] && [ x$ext == xtcl ]; then
          TCLSCRIPT=$FILENAME
        elif [ "x$BASHSCRIPT" == x ] && [ "x$TCLSCRIPT" != x ]; then
          BASHSCRIPT="$TCLSCRIPT $FILENAME"
        else
          BASHSCRIPT="$BASHSCRIPT $FILENAME"
        fi
     elif [ "x$BASHSCRIPT" == x ] && [ "x$TCLSCRIPT" != x ]; then
        BASHSCRIPT="$TCLSCRIPT $arg"
     else
        BASHSCRIPT="$BASHSCRIPT $arg"
      fi
    ;;
    esac
  done
fi

if [ "x$DOCKER_IMG_special" != x ]; then
  DOCKER_IMG=$DOCKER_IMG_special
fi

# choose docker
# automatic load docker

user=`whoami`
dir=`pwd`

function mount {
  src=$1
  dst=$2
  if [ x${mounted[$dst]} != x ]; then
    return
  fi 
  mounted[$dst]=$src
  CMD="$CMD --mount type=bind,src=$src,dst=$dst " 
  return
}

function mount_readonly {
  src=$1
  dst=$2
  if [ x${mounted[$dst]} != x ]; then
    return
  fi 
  mounted[$dst]=$src
  CMD="$CMD --mount type=bind,src=$src,dst=$dst,readonly " 
  return
}

declare -A mounted=()
CMD="docker run --privileged -it --rm --network=host "
mount $dir $dir
if [ x$EDEN_HOME != x ]; then
  mount $EDEN_HOME /Eden
  CHANGE_PATH="$CHANGE_PATH PATH=/Eden/build/src/:\$PATH; "
fi

case $user in
*)
  mount_readonly /home/project       /home/project
  mount          /home/project/$user /home/project/$user
  mount          /home/$user         /home/$user
  ;;
esac

function trim {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  echo "$var"
}

# shell script
if [ "x$BASHSCRIPT" != x ]; then
  str="$CHANGE_PATH $BASHSCRIPT"
  str=`trim $str`
  cmd="-c \"$str\" "
fi
# tcl command
if [ x$TCLSCRIPT != x ]; then
  str="$CHANGE_PATH eden -exit $TCLSCRIPT"
  str=`trim $str`
  strip str
  cmd="-c \"$str\" "
fi

if [ "x$MOUNT_LIST" != x ]; then
  for item in $MOUNT_LIST;
  do
    absitem=`realpath $item`
    echo "About to mount $item as $absitem"
    mount $absitem $absitem
  done
fi

if [ "x$MOUNT_READONLY_LIST" != x ]; then
  for item in $MOUNT_READONLY_LIST;
  do
    absitem=`realpath $item`
    echo "About to mount $item as $absitem"
    mount_readonly $absitem $absitem
  done
fi

CMD="$CMD --workdir $dir --env='DISPLAY' --volume=$HOME/.Xauthority:/root/.Xauthority:rw "
CMD="$CMD --entrypoint /bin/bash --user `id -u`:`id -g` "
CMD="$CMD $DOCKER_IMG $cmd"

echo "execute command: 
$CMD"
echo $CMD > /tmp/.$user
chmod +x /tmp/.$user
/tmp/.$user

