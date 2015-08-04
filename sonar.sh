#!/usr/bin/env bash
cd /var/www/nabludai
git pull origin master
/etc/init.d/sonar-runner
