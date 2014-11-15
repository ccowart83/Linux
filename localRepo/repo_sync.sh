#!/bin/bash

#
# Keep the local mirror repo in sync with the external repo.
# This can be run in a cron jobs as follows:
#
#    # Update once per day at 10:00PM.
#    0 22 * * * /shared/repo/bin/repo_sync.sh
#
# The configuration information is /shared/repo/bin/repo_conf.sh.
#
umask 0

#
# Keep my local CentOS 6.4 repo mirror up to date. The local repo
# mirror is used by all CentOS 6.4 hosts on the internal nework.
#
medir=$(dirname -- $(readlink -f $0))
if [ -f "$medir/repo_conf.sh" ] ; then
    . $medir/repo_conf.sh
else
    echo "ERROR: missing file: $medir/repo_conf.sh."
    exit 1
fi
if [[ "$mirror_repo" == "" ]] ; then
    echo "ERROR: mirror_repo not defined."
    exit 1
fi
if [[ "$mirror_repo_file" == "" ]] ; then
    echo "ERROR: mirror_repo_file not defined."
    exit 1
fi

# Semaphore file used to avoid collisions.
semaphore="$mirror_repo/.busy"
if [ -f $semaphore ] ; then
    echo "WARNING: sync already running: $(cat $semaphore)"
    exit 0
fi
echo "pid=$$, host=$(hostname -f), user=$(whoami), date='$(date)', sem=$semaphore" >$semaphore
chmod a+rw $semaphore

# Trap ^C interrupt.
function keyboard_interrupt() {
    echo
    echo "^C interrupt, exiting..."
    rm -f $semaphore
    exit 1
}
trap keyboard_interrupt SIGINT

# Emulate a 2D array.
# The first entry is the source, the second is the dst.
# Note that the trailing backslashes are important to rsync.
list=(
    # First pair.
    #"rsync://mirrors.cat.pdx.edu/centos/6.4/"
    "rsync://mirror.linux.duke.edu/centos/6/"
    "${mirror_repo}/centos/6.4/"

    # Second pair.
    # URL: http://elrepo.org/tiki/Download
    ##! "rsync://mirrors.thzhost.com/elrepo/elrepo/el6/x86_64/"
    'rsync://mirrors.neterra.net/elrepo/elrepo/el6/x86_64/'
    "${mirror_repo}/elrepo/el6/x86_64/"
)

# Packages to exclude.
excludes=(
    'local_centos_6.4_xen4_x86_64'
    'local_centos_6.4_centosplus_x86_64'
    'local_centos_6.4_fasttrack_x86_64'
)

# Iterate over the pairs and rsync.
# Note the bandwidth is limited to be a good citizen.
# Also note that there is some trickiness where I used the --filter
# option because the equivalent --exclude command didn't work.
len=$(( ${#list[@]} / 2 - 1 ))
for i in $(seq 0 $len) ; do
    srcidx=$(( $i * 2 ))
    src=${list[$srcidx]}

    dstidx=$(( $srcidx + 1 ))
    dst=${list[$dstidx]}

    echo
    echo '# ================================================================'
    echo '# rsync'
    echo "#   src: $src"
    echo "#   dst: $dst"
    echo '# ================================================================'
    if [ ! -d $dst ] ; then
	mkdir -p $dst
    fi
    rsync -avzP \
	--delete \
	--bwlimit=1024 \
	--prune-empty-dirs \
	--include='*.rpm' \
	--exclude='i386' \
	--exclude='repodata' \
	--exclude='isos'\
	--exclude='xen4'\
	--filter='-! */' \
	$src $dst
done

# Now create the yum repo data.
mirrored_pkgs=$(find $mirror_repo -type d -name x86_64)
for mirrored_pkg in ${mirrored_pkgs[@]}; do
    echo
    echo '# ================================================================'
    echo "# createrepo --update $mirrored_pkg"
    echo '# ================================================================'
    createrepo --pretty --workers 4 --update $mirrored_pkg
done

echo
echo '# ================================================================'
echo "# creating $mirror_repo/yum.repos.d/local.repo"
echo '# ================================================================'
local_repo="$mirror_repo_file"
local_repo_dir=$(dirname -- $local_repo)
if [ ! -d $local_repo_dir ] ; then
    mkdir -p $local_repo_dir
fi
if [ -f $local_repo ] ; then
    rm -f ${local_repo}
fi
offset=$(( ${#mirror_repo} + 2))
i=0
for mirrored_pkg in ${mirrored_pkgs[@]}; do
    #echo $mirrored_pkg
    title=$(echo $mirrored_pkg | cut -c ${offset}- | tr '/' '_')
    if (( $i > 0 )) ; then
	echo >>${local_repo}
    fi
    title="local_$title"
    prefix=''
    for exclude in ${excludes[@]}; do
	if [[ "$exclude" == "$title" ]] ; then
	    prefix='##!'
	fi
    done
    cat >>${local_repo} <<EOF
${prefix}[$title]
${prefix}name=$title
${prefix}baseurl=file://$mirrored_pkg
${prefix}gpgcheck=0
${prefix}enabled=1
EOF
    i=$(( $i + 1 ))
done

echo
echo '# ================================================================'
echo "# available repos"
echo '# ================================================================'
for mirrored_pkg in ${mirrored_pkgs[@]}; do
    echo $mirrored_pkg
done
echo
echo "local_repo_file: $local_repo"

rm -f $semaphore

echo
echo "repo_sync done"
