#!/usr/bin/env bash

#/etc/init.d/sonar-runner run analyse project
#/etc/init.d/sonar stop | start | restart
HOST='sonar.itftc.com'
USER='nkuropatkin'

ssh $USER@$HOST 'bash -s'< sonar.sh
