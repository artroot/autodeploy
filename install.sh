#!/usr/bin/bash
#
# By Artem Semenishch <a.semenishch@gmail.com>
# Created: 2019-02-15

SCRIPT_DIR=`dirs`

cd /bin && ln -s $SCRIPT_DIR/gen-env.sh gen-env

echo "/bin/gen-env link created"
