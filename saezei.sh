#!/usr/bin/env bash

. $HOME/.bashrc

rvm use default
rvm gemset use selenium

OS=$(uname -s)

BASEDIR=${1:-$HOME/backup/sz}
mkdir -p $BASEDIR

if [[ "$OS" == "OpenBSD" ]]; then
    ps -a | awk '$5 ~ /Xvfb/ { print $5; }' | grep -q Xvfb
else
    ps -a | awk '$4 ~ /Xvfb/ { print $4; }' | grep -q Xvfb
fi

if (( $? != 0 )); then
    nohup Xvfb :1 -screen 1 1600x1200x8 &>/dev/null &
    sleep 1
fi

DISPLAY=:1 saezei.rb $BASEDIR 2>> $BASEDIR/saezei.log
if (( $? != 0 )); then
    exit 1
fi 

DIR=$(ls -tr $BASEDIR/*/ | tail -1)

saezei_convert.rb $BASEDIR/$DIR 2>> $BASEDIR/saezei_convert.log
if (( $? != 0 )); then
    exit 2
fi 

saezei_compile.rb $BASEDIR/$DIR 2>> $BASEDIR/saezei_compile.log
if (( $? != 0 )); then
    exit 2
fi 
