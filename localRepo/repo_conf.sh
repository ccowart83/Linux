#!/bin/bash

#
# Keep my local CentOS 6.4 repo mirror up to date. The local repo
# mirror is used by all CentOS 6.4 hosts on the internal nework.
#
mirror_repo="/shared/repo"
if [ ! -d $mirror_repo ] ; then
    echo "ERROR: mirror repo directory does not exist: $mirror_repo"
    exit 1
fi

#
# This is the generated repo file that is used in the
# /etc/yum.repos.d directory.
#
mirror_repo_file="$mirror_repo/yum.repos.d/local.repo"

#
# This is the test directory.
#
mirror_repo_test="$mirror_repo/test"
