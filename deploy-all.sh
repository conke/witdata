#!/bin/sh

cd `dirname $0`
TOP=$PWD

function ssh_setup
{
	kt="rsa"
	kf="id_$kt"

	if [ ! -f ~/.ssh/${kf} ]; then
		ssh-keygen -P '' -f ~/.ssh/${kf}
	fi

	#key=`cat ~/.ssh/${kf}.pub`
	#grep "$key" ~/.ssh/authorized_keys > /dev/null 2>&1|| echo "$key" >> ~/.ssh/authorized_keys

	total=${#hosts[@]}
	count=1

	for host in ${hosts[@]}
	do
		echo "Copying $kf [$count/$total]: $host ..."
		# TODO: no-interactive support
		ssh-copy-id $host

		((count++))
		echo
	done

	for host in ${hosts[@]}
	do
		ssh $host echo "login $host successfully!"
	done
	echo
}

destroy=0
init=0

while [ $# -gt 0 ]
do
	case $1 in
	-i|--init)
		init=1
		;;
	-d|--destroy)
		destroy=1
		;;
	*)
		echo "usage: `basename $0 [-d|--destroy] [-i|--init]`"
		exit 1
	esac

	shift
done

if [ -e ./.config ]; then
	. ./.config
fi

if [ -n "$config_master" ]; then
	master=$config_master
else
	master=`hostname` # FIXME
fi

slaves=($config_slaves)
hosts=($master $config_slaves)

if [ ${#hosts[@]} -gt 1 ]; then
	mode="cluster"
else
	# TODO: support standalone
	mode="pseudo"
fi

if [ -n "$config_repo" ]; then
	repo="$config_repo"
else
	repo='/mnt/witpub/cloud/hadoop/'
fi

# FIXME: only for hbase and zk
if [ -n "$config_data_root" ]; then
	data_root="$config_data_root"
else
	data_root="$HOME/data"
fi

apps=""

if [ -n "$config_hadoop" ]; then
	hadoop=$config_hadoop
	apps="hadoop"
fi

if [ -n "$config_hive" ]; then
	hive=$config_hive
	apps="$apps hive"
fi

if [ -n "$config_pig" ]; then
	pig=$config_pig
	apps="$apps pig"
fi

if [ -n "$config_zk" ]; then
	zk=$config_zk
	apps="$apps zookeeper"
fi

if [ -n "$config_hbase" ]; then
	hbase=$config_hbase
	apps="$apps hbase"
fi

if [ $init -eq 1 ]; then
	ssh_setup
	exit $?
fi

if [ -z "$JAVA_HOME" ]; then
	echo -e "JAVA_HOME not set!\n"
	exit 1
fi

if [ -e /etc/redhat-release ]; then
	profile="$HOME/.bash_profile"
else
	profile="$HOME/.profile"
fi

function add_export
{
	local key=$1
	local val=$2

	grep -w $key $profile > /dev/null
	if [ $? -eq 0 ]; then
		sed -i "s:$key=.*:$key=$val:" $profile
	else
		echo "export $key=$val" >> $profile
	fi

	if [ $? -ne 0 ]; then
		echo "fail to export $key!"
		exit 1
	fi

	eval export $key=$val
}

function del_export
{
	local key=$1

	sed -i "/export $key/d" $profile
	unset $key
}

function check_profile_path
{
	local path=$1

	grep "PATH=$path:" $profile > /dev/null || \
		grep "PATH=.*:$path$" $profile > /dev/null || \
			grep "PATH=.*:$path:" $profile > /dev/null

	return $?
}

function add_path
{
	local path=$1

	check_profile_path $path || echo "export PATH=$path:\$PATH" >> $profile
	check_profile_path $path || exit 1

	# FIXME
	echo $PATH | grep -w $path || \
		eval export PATH="$path:\$PATH"
}

function del_path
{
	local path=$1
	check_profile_path $path && sed -i "#PATH=.*$path#d" $profile

	local NEW_PATH=`echo $PATH | sed -e 's#$path:##' | sed -e 's#:$path##'`
	eval export PATH=$NEW_PATH
}

function extract
{
	local pkg=$1
	local dir

	if [ -n "$2" ]; then
		dir=$2
	else
		dir=$HOME
	fi

	echo -n "extracting $pkg ... "
	tar xf $repo/${pkg}.tar.gz -C $dir || {
		echo "failed"
		exit 1
	}
	echo "done"
}

function execute
{
	func=$1

	echo "#########################################"
	echo "  executing $func() ..."
	echo "#########################################"

	$func
	if [ $? -ne 0 ]; then
		echo "fail to run $func!"
		exit 1
	fi

	echo
}

for app in $apps
do
	if [ ! -e ./$app.sh ]; then
		echo "$app.sh does not exists!"
		exit 1
	fi

	. ./$app.sh

	if [ $destroy -eq 1 ]; then
		execute ${app}_destroy
		cd $TOP

		for host in ${hosts[@]}
		do
			ssh $host << EOF
rm -rf $data_root
EOF
			echo
		done
	else
		for host in ${hosts[@]}
		do
			ssh $host << EOF
mkdir -p $data_root
EOF
			echo
		done

		execute ${app}_deploy
		cd $TOP
		execute ${app}_validate
		cd $TOP
	fi

	echo
done
