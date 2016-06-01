#!/usr/bin/env bash

. $HOME/.bashrc

rvm use default &>/dev/null
rvm gemset use selenium &>/dev/null

OS=$(uname -s)

BASEDIR=${1:-$HOME/backup/sz}
mkdir -p $BASEDIR

XVFB=$(ps aux | grep $USER | awk '$11 ~ /Xvfb/ { print $11; }' | grep -c Xvfb)
if (( $XVFB == 0 )); then
    nohup Xvfb :1 -screen 0 1600x1200x8 &>/dev/null &
    sleep 3
fi

DISPLAY=:1 saezei.rb $BASEDIR 2>> $BASEDIR/saezei.log
if (( $? != 0 )); then
    exit 1
fi 

DIR=$(ls -dtr $BASEDIR/*/ | tail -1)

saezei_convert.rb $DIR 2>> $BASEDIR/saezei_convert.log
if (( $? != 0 )); then
    exit 2
fi 

saezei_compile.rb $DIR 2>> $BASEDIR/saezei_compile.log
if (( $? != 0 )); then
    exit 3
fi 
