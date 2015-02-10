  #!/bin/sh
#
# Deploying application to frontend and backend servers
#

PROGNAME=`basename $0`
VERSION="Version 0.12,"
AUTHOR="2013, sys (email: sys@corp.flirchi.com)"

stOK=0
stCR=1
stUK=2
PID=$$

clRED='\033[01;31m' # Light Red
clGRN='\033[01;32m' # Light Green
clYEL='\033[01;33m' # Light Yellow
clBLU='\033[01;34m' # Light Blue
clMAG='\033[01;35m' # Light Magenta
clCYA='\033[01;36m' # Light Cyan
clWHT='\033[01;37m' # Light White
clRST='\033[00;00m' # Normal White

HOST=`hostname | cut -f1 -d '.'`

#
# Default values.
#

ULCK=0
SLCK=0
FRN=0
ORIGIN="master"
PHORIGIN="master"
BASE_DIR="/home/deploy"
DEPLOY_INFO='/tmp/deploy.lock'
DIR="flirchi"
ENV="production"
SRV_CDN="10.10.0.12"
SRV_PROD="10.1.0.2 10.1.0.3 10.1.0.4 10.1.0.6 10.1.0.7 10.1.0.8 10.1.0.9 10.1.0.19 10.1.0.30 10.1.0.70 10.1.0.71 10.1.0.72 10.1.0.74 10.1.0.76 10.1.0.77 10.1.0.78  10.1.0.85 10.1.0.86 10.1.0.13 10.1.0.204 10.1.0.37 10.1.0.80 10.1.0.81 10.1.0.75 10.1.0.73"
MAIL_PROD="207.244.64.193 207.244.64.204 207.244.64.208 207.244.64.207 207.244.64.206 207.244.64.203 207.244.64.209 10.1.0.16 10.1.0.20 10.1.0.43 10.1.0.44 10.1.0.45 10.1.0.42 10.1.0.46 10.1.0.47 10.1.0.48 10.1.0.49 10.1.0.50 10.10.0.3 10.10.0.7 10.1.0.206"
SRV_STAGE="10.1.0.18"
USER="wdata"
DOCROOT="/home/wdata"

UNAME=""
UEMAIL=""
PARAMS=`echo -n "$@" | sed "s/--user.name [a-zA-Z0-9.]*//g; s/--user.email [a-zA-Z0-9.@]*//g; s/  */ /g; s/^[ ]*//"`
DATE=$(date "+%Y-%m-%d %H:%M:%S")

RST=0
FPM_RC_SCRIPT="/usr/local/etc/rc.d/php-fpm"
FPM_RST_FILE="/tmp/php-fpm_restart.txt"

FULL=0
PHLIGHT_UPD=0
COMMIT=""
files_changed=""
png_files_changed=""
force_flag=""
COMPILE_CONTENT=0

#
# Output version.
#

print_version() {
  echo "$VERSION $AUTHOR"
}

#
# Output usage information.
#

print_help() {
  print_version
  cat <<-EOF
$PROGNAME is a source code deploying script.

Usage: ./$PROGNAME [options]

Options:
  -h, --help
    Print detailed help screen
  -v, --version
    Print version information
  -e, --env
    Set destination environment:
      prod|production - production servers (default)
      stage           - stage server @sys1 (sets default branch for flirchi and phlight repos to stage)
      mail            - mail servers
      cdn             - cdn servers
      lock            - php1 server
  -u, --unlock
    Unlock deploy process blocked due to an error
  -c, --checkout
    Checkout to specified rev and lock production copy
  -r, --restart
    Restart PHP-FPM on all servers
  -F, --foreign
    Deploy foreign version of the site
  -f, --full
    Deploy with full recompile autoload and i18n_update tasks
EOF
}

#
# executing command, exit if error.
#

ERTrap() {
  COMMAND=$1
  ERROR_MSG=$2
  SUCCESS_MSG=$3
  RET=$4
  MSG=$5

  if [ -n "$COMMAND" ] && [ -z $RET ]; then
    MSG=`$COMMAND 2>&1`
    RET=$?
  fi

  if [ $RET -ne 0 ]; then
    echo -e "$clYEL<-- $clRED$ERROR_MSG$clYEL -->$clRST"
    echo -e "$clYEL|                            |$clRST"
    cat /home/deploy/troll.txt
    echo -e "$clYEL|                            |$clRST"
    echo -e "$clRED Error is: $clRST"
    echo -e "$clCYA$MSG$clRST"
    echo -e "$clYEL|                            |$clRST"
    echo -e "$clYEL<---------------------------->$clRST";
    echo
    echo "Exiting..."
  else
    echo -e "$clYEL<-- $clGRN$SUCCESS_MSG$clYEL -->$clRST"
    echo -e "$clYEL|                            |$clRST"
    echo -e "$clCYA$MSG$clRST"
    echo -e "$clYEL|                            |$clRST"
    echo -e "$clYEL<---------------------------->$clRST";
  fi
  echo
  return $RET
}

#
# Parse exit code.
#

EXPars() {
  if [ $1 -ne 0 ]; then
    logger -t deploy "$logMSG :: FAILED"
    unlock_deploy
    exit $1
  fi
}

#
# Pull git data.
#

pull_data() {
  echo
  echo -e "$clBLU====$clWHT Pulling data... $clBLU====$clRST"
  echo

  flPrdLstCom=$(cd $BASE_DIR/$DPATH/$DIR.git && git log --pretty=oneline -n1 | cut -f1 -d ' ')
  [ -z "$COMMIT" ] && flFrmLstCom=$(cd $BASE_DIR/$DPATH/phlight.git && git log --pretty=oneline -n1 | cut -f1 -d ' ')

  projects="$DIR.git phlight.git"
  gitcommand="pull origin master"
  if [ ! -z "$COMMIT" ]; then
    projects="$DIR.git"
    gitcommand="checkout $COMMIT"
  fi

  synccmd='cd {} && git '$gitcommand' > ../{}.output 2>&1'
  cd $BASE_DIR/$DPATH && parallel --joblog parallellog.output \
    $synccmd ::: $projects

  cd $BASE_DIR/$DPATH

  i=0
  while read line; do
    i=$((i+1))
    if [ $i -eq 1 ]; then continue; fi
    set -- $line;
    exit_code=${7}
    task_name=${10}
    err=0
    if [ $exit_code -ne 0 ]; then
      err=$exit_code
    fi
    listing=`cat ${BASE_DIR}/${DPATH}/${task_name}.output`
    ERTrap "" $task_name" git $gitcommand has FAILED!" $task_name" git $gitcommand is OK" $exit_code "$listing"
  done < parallellog.output

  if [ -z "$COMMIT" ] && [ $(cat $BASE_DIR/$DPATH/phlight.git.output | grep "Already up-to-date." | wc -l) -eq 0 ]; then
    PHLIGHT_UPD=1
  fi

  rm $BASE_DIR/$DPATH/*.output
  EXPars $err

  cd $BASE_DIR/$DPATH/$DIR.git
  if [ $(git diff --name-status $flPrdLstCom | wc -l) -ne 0 ]; then
    flPRODLST="$DIR.git:
$(git diff --name-status $flPrdLstCom)"
    flPROD_files_changed=$(git diff --name-status $flPrdLstCom | awk '{ print $2 }' | tr '\n' ' ')
    #png_files_changed=$(git diff --name-status --diff-filter=ACM $flPrdLstCom | awk '{ if ($2 ~ /.png/) print $2 }' | tr '\n' ' ')
  fi

  if [ -z "$COMMIT" ]; then
    cd $BASE_DIR/$DPATH/phlight.git
    if [ $(git diff --name-status $flFrmLstCom | wc -l) -ne 0 ]; then
      flFRAMLST="phlight.git:
$(git diff --name-status $flFrmLstCom)"
    fi
    flFRAM_files_changed=$(git diff --name-status $flFrmLstCom | awk '{ print "../phlight/"$2 }' | tr '\n' ' ')
  fi

  files_changed=$flPROD_files_changed" "$flFRAM_files_changed
  if echo "$files_changed" | grep -q ".css" || echo "$files_changed" | grep -q ".js"; then
    COMPILE_CONTENT=1
  fi

 #if echo "$png_files_changed" | grep -q ".png"; then
   #png_files_changed=$(echo $png_files_changed | sed -e 's/[[:space:]]*$//')
   #pngquant --ext=.png --force "$BASE_DIR/$ENV/$DIR/$png_files_changed"
   #cd $BASE_DIR/$DPATH/$DIR.git && git add $png_files_changed && git commit -m 'minify img: $png_files_changed' && git push
 #fi

  if [ $FULL -eq 1 ]; then
    force_flag="force"
    files_changed="full"
  fi
}

#
# Run application tasks.
#

compile_content() {
  echo
  echo -e "$clBLU====$clWHT Running compilation and migrations... $clBLU====$clRST"
  echo

  tasks_file=$BASE_DIR/$DPATH/$DIR.git/tasks.lst

  if [ "$DPATH" = "production" ]; then
     printf "db_migrate\t\n" >> $tasks_file
  fi
  [ $COMPILE_CONTENT -eq 1 ] && printf "compile_static_new\t%s\n" "$force_flag" >> $tasks_file
  printf "compile_i18n\t\n" >> $tasks_file

  printf "compile_load\t%s\n" "$files_changed" >> $tasks_file
  printf "i18n_update\t%s\n" "$files_changed" >> $tasks_file

  cd $BASE_DIR/$DPATH/$DIR.git && cat $tasks_file | parallel -j0 --colsep '\t' --joblog parallellog.output "./run {1} {2} > {1}.output" > /dev/null 2>&1
  rm $tasks_file

  i=0
  while read line; do
    i=$((i+1))
    if [ $i -eq 1 ]; then continue; fi
    set -- $line;
    exit_code=${7}
    task_name=${10}
    err=0
    if [ $exit_code -ne 0 ]; then
      err=$exit_code
    fi
    listing=`cat $BASE_DIR/$DPATH/$DIR.git/${task_name}.output`
    ERTrap "" "Task "$task_name" has FAILED!" "Task "$task_name" is OK" $exit_code "$listing"
  done < parallellog.output

  rm $BASE_DIR/$DPATH/$DIR.git/*.output
  EXPars $err

  echo
  echo -e "$clBLU====$clWHT All Done $clBLU====$clRST"
  echo
}

#
# Sync content on each app server
#

sync_content() {
  echo
  echo -e "$clBLU====$clWHT Synchronizing content $clBLU====$clRST"
  echo

  printf "$clYEL<--$clMAG Processing $clCYA${SRV} $clYEL-->$clRST"
  echo
  echo

  sync_list=${DIR}.git
  if [ $PHLIGHT_UPD -eq 1 ]; then
    sync_list="{"$sync_list",phlight.git}"
  fi

  parallel -j0 --joblog $BASE_DIR/$DPATH/parallellog.output \
    rsync -aHz --delete --exclude={tmp/,.git*,node_modules/} $BASE_DIR/$DPATH/${sync_list} wdata@{}:${DOCROOT}/ '2>/dev/null' ::: $SRV

  if [ $RST -eq 1 ]; then
    touch $FPM_RST_FILE
    parallel scp $FPM_RST_FILE wdata@{}:/tmp ::: $SRV
  fi

  i=0; FAIL=0; server_log=""
  while read line; do
    i=$((i+1))
    if [ $i -eq 1 ]; then continue; fi
    set -- $line;
    exit_code=${7}
    server_part=${4}")\t"$(echo ${14} | tr "@:" "\n" | tail -n 2 | head -n 1)
    server_log=$server_log$server_part
    if [ $exit_code -ne 0 ]; then
      FAIL=$exit_code
      server_log=$server_log":\t${clRED}FAIL${clCYA}\n"
    else
      server_log=$server_log":\t${clGRN}OK${clCYA}\n"
    fi
  done < $BASE_DIR/$DPATH/parallellog.output
  rm $BASE_DIR/$DPATH/parallellog.output

  ERTrap "" "Synchronization has FAILED" "Synchronization is OK" "$FAIL" "`echo $server_log | sort -n`"
  EXT=$?

  logger -t deploy "$logMSG :: OK"
  if [ ! -z "$flPRODLST" ]; then
    echo "$flPRODLST" | tr '\t' ' ' |
    while read line; do
      logger -t deploy "$line"
    done
  fi
  if [ ! -z "$flFRAMLST" ]; then
    echo "$flFRAMLST" | tr '\t' ' ' |
    while read line; do
      logger -t deploy "$line"
    done
  fi

  rm -f /tmp/deploy.$PID
  EXPars $EXT

  echo
  echo -e "$clBLU====$clWHT All Done $clBLU====$clRST"
  echo
}

unlock_deploy() {
  `rm -f $DEPLOY_INFO >/dev/null 2>&1`
  if [ "$?" -ne 0 ]; then
    echo
    echo -e "$clRED====$clWHT Error wile unlocking. Can't remove $DEPLOY_INFO $clRED====$clRST"
    echo
    exit ${stUK}
  fi
}

### Run

#
# Test input parameters.
#

while test -n "$1"; do
  case $1 in
    --help|-h)
      print_help
      exit $stOK
      ;;
    --version|-v)
      print_version
      exit $stOK
      ;;
    --env|-e)
      ENV=$2
      shift
      ;;
    --checkout|-c)
      COMMIT=$2
      shift
      ;;
    --unlock|-u)
      ULCK=1
      ;;
    --restart|-r)
      RST=1
      ;;
     --foreign|-F)
      FRN=1
      DOCROOT="/home/wdata/foreign";
      ;;
    --full|-f)
      FULL=1
      ;;
    --user.name)
      UNAME=$2
      shift
      ;;
    --user.email)
      UEMAIL=$2
      shift
      ;;
    *)
      echo "Unknown parameter: $1"
      echo "Type \"$0 -h\" to see the help"
      exit ${stUK}
      ;;
  esac
  shift
done
logMSG="$UNAME ($UEMAIL) [$DATE]: ./$PROGNAME $PARAMS"

#
# Set env dependent parameters.
#

ORIGIN="origin "$ORIGIN
PHORIGIN="origin "$PHORIGIN
case "$ENV" in
  prod|production)
    SRV=$SRV_PROD
    if [ $FRN -eq 1 ]; then
        DPATH="production/foreign"
    else
        DPATH="production"
    fi
    ;;
  stage)
    SRV=$SRV_STAGE
    ORIGIN="origin stage"
    if [ $FRN -eq 1 ]; then
        DPATH="stage/foreign"
    else
        DPATH="stage"
    fi
    ;;
  mail)
    SRV=$MAIL_PROD
    if [ $FRN -eq 1 ]; then
        DPATH="production/foreign"
    else
        DPATH="production"
    fi
    ;;
  cdn)
    SRV=$SRV_CDN
    if [ $FRN -eq 1 ]; then
        DPATH="production/foreign"
    else
        DPATH="production"
    fi
    ;;
  *)
    echo "Unknown env value: $ENV"
    echo "Valid: prod|production|stage|mail|cdn"
    echo "Type \"$0 -h\" to see the help"
    exit ${stUK}
    ;;
esac

#
# validate revision hash if specified
#

if [ ! -z "$COMMIT" ]; then
cd $BASE_DIR/$DPATH/$DIR.git
  `cd $BASE_DIR/$DPATH/$DIR.git >/dev/null 2>&1 && git rev-parse --verify $COMMIT >/dev/null 2>&1`
  if [ $? -ne 0 ]; then
    echo "Can't find rev with hash: $2"
    exit ${stUK}
  fi
fi

#
# Get prev lock
#

LOCKEDBY=0
if [ -f $DEPLOY_INFO ]; then
  LOCKEDBY=`cat $DEPLOY_INFO`

  if [ $ULCK -eq 1 ]; then
    # Unlock end exit
    `rm -f $DEPLOY_INFO >/dev/null 2>&1`
    if [ "$?" -eq "0" ]; then
      echo
      echo -e "$clGRN====$clWHT Deploy is unlocked $clGRN====$clRST"
      echo
    else
      echo
      echo -e "$clRED====$clWHT Error wile unlocking. Can't remove $DEPLOY_INFO $clRED====$clRST"
      echo
      exit ${stUK}
    fi
  else
    # Show info about locker
    mtime=`stat $DEPLOY_INFO | awk '{ print $9, $10, $11, $12}'`
    githash=`cd $BASE_DIR/$DPATH/$DIR.git >/dev/null 2>&1 && git log -1`
    echo -e "$clRED====$clWHT Locked by $clRED"$LOCKEDBY"$clWHT at "$mtime" in: $clBLU"
    echo -e "$githash $clRED====$clRST"
    exit ${stOK}
  fi

else
  if [ $ULCK -eq 1 ]; then
    echo
    echo -e "$clRED====$clWHT Deploy is not locked. $clRED====$clRST"
    echo
    exit ${stUK}
  fi
fi

#
# Lock by user.
#

if [ ! -z "$UEMAIL" ]; then
  echo $UEMAIL > $DEPLOY_INFO
fi

pull_data
compile_content
sync_content

# if !need lock => remove $DEPLOY_INFO
if [ -z "$COMMIT" ]; then
  unlock_deploy
fi
