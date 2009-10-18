#!/bin/sh
# Copyright (c) 2009 Rainbows! developers

# pipefail is non-POSIX, but useful in ksh/bash
(
	set +e
	set -o pipefail
)
if test $? -eq 0
then
	set -o pipefail
else
	echo >&2 "WARNING: your shell does not understand pipefail"
fi

set -e

T=$(basename $0)
if test -z "$model"
then
	case $T in
	t1???-thread-pool-*.sh) model=ThreadPool ;;
	t2???-thread-spawn-*.sh) model=ThreadSpawn ;;
	t3???-revactor-*.sh) model=Revactor ;;
	t4???-rev-*.sh) model=Rev ;;
	*) model=any ;;
	esac
fi

set -u
ruby="${ruby-ruby}"

case $model in
Rev) require_rev ;;
Revactor) require_revactor ;;
esac

# ensure a sane environment
TZ=UTC LC_ALL=C LANG=C
export LANG LC_ALL TZ
unset CDPATH

die () {
	echo >&2 "$@"
	exit 1
}

_TEST_RM_LIST=""
trap 'rm -f $_TEST_RM_LIST' 0
PATH=$PWD/bin:$PATH
export PATH

test -x $PWD/bin/unused_listen || die "must be run in 't' directory"

wait_for_pid () {
	path="$1"
	nr=30
	while ! test -s "$path" && test $nr -gt 0
	do
		nr=$(($nr - 1))
		sleep 1
	done
}

require_revactor () {
	if ! $ruby -rrevactor -e "puts Revactor::VERSION" >/dev/null 2>&1
	then
		echo >&2 "skipping $T since we don't have Revactor"
		exit 0
	fi
}

require_rev() {
	if ! $ruby -rrev -e "puts Rev::VERSION" >/dev/null 2>&1
	then
		echo >&2 "skipping $T since we don't have Rev"
		exit 0
	fi
}

# given a list of variable names, create temporary files and assign
# the pathnames to those variables
rtmpfiles () {
	for id in "$@"
	do
		_tmp=$(mktemp -t rainbows.$$.$id.XXXXXXXX)
		eval "$id=$_tmp"
		_TEST_RM_LIST="$_TEST_RM_LIST $_tmp"
	done
}

dbgcat () {
	id=$1
	eval '_file=$'$id
	echo "==> $id <=="
	sed -e "s/^/$id:/" < $_file
}
