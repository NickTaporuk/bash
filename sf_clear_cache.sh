#!/usr/bin/env bash
PWD=`pwd`;
CMD='app/console cache:clear';
COMMAND=''
sudo chmod -R 0777 $PWD ;

if [[ -n "$1" && "$1" -ne 'y' ]];
 then COMMAND="$CMD --env=$1";
 else COMMAND="$CMD --env=dev";
fi

if [[ "$2" = "y" || "$1" = "y" ]];
 then COMMAND="$COMMAND --no-warmup"
fi

$COMMAND;
sudo chmod -R 0777 $PWD;