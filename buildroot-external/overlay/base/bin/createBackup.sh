#!/bin/sh
#
# simple wrapper script to generate a CCU compatible sbk file
#
# Copyright (c) 2016-2017 Jens Maus <mail@jens-maus.de>
#

BACKUPDIR=/usr/local/tmp

if [ -n "${1}" ]; then
  BACKUPDIR=$1
fi

# make sure BACKUPDIR exists
TMPDIR=$(mktemp -d -p /usr/local/tmp)

# make sure ReGaHSS saves its current settings
echo 'load tclrega.so; rega system.Save()' | tclsh 2>&1 >/dev/null

# create a gzipped tar of /usr/local
tar --owner=root --group=root --exclude=/usr/local/tmp --exclude=/usr/local/lost+found --exclude-tag=.nobackup --one-file-system --ignore-failed-read -czf ${TMPDIR}/usr_local.tar.gz /usr/local 2>/dev/null

# sign the configuration with the current key
crypttool -s -t 1 <${TMPDIR}/usr_local.tar.gz >${TMPDIR}/signature

# store the current key index
crypttool -g -t 1 >${TMPDIR}/key_index

# store the firmware VERSION
source /boot/VERSION 2>/dev/null
cp /boot/VERSION ${TMPDIR}/firmware_version

# create sbk file
tar -C ${TMPDIR} --owner=root --group=root -cf ${BACKUPDIR}/"$(hostname)-${VERSION}-$(date +%Y-%m-%d-%H%M).sbk" usr_local.tar.gz signature key_index firmware_version 2>/dev/null

# remove all temp files
rm -rf ${TMPDIR}
