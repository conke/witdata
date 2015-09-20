#!/bin/sh

if [ $# = 1 ]; then
	DIR=~
	JDK=$1
elif [ $# = 3 ]; then
	# FIXME
	DIR=${2%%/}
	JDK=$3
else
	echo "usage: $0 [-d <InstallPath>] <JDK Package>!"
	exit 1
fi

JAVA_HOME=`tar -tf $JDK | head -n 1`
JAVA_HOME=${JAVA_HOME%/}
echo "Installing $JAVA_HOME ..."
JAVA_HOME=$DIR/$JAVA_HOME

if [ ! -x $JAVA_HOME/bin/javac ]; then
	tar xf $JDK -C $DIR || exit 1
fi

if [ -e /etc/redhat-release ]; then
	sh_config="$HOME/.bashrc"
else
	sh_config="$HOME/.profile"
fi

sed -i -e '/JAVA_HOME/d' -e '/CLASS_PATH/d' $sh_config

cat >> $sh_config << EOF
export JAVA_HOME=$JAVA_HOME
export CLASS_PATH=.:\$JAVA_HOME/lib:\$JAVA_HOME/jre/lib
export PATH=\$JAVA_HOME/bin:\$PATH
EOF

#source $sh_config
#javac -version || exit 1

#echo "JDK successfully installed to $JAVA_HOME"
