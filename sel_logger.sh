#!/bin/bash

#This daily script queries system event logs and updates the BMC time of the node. If the logs are full, logs are saved to /uufs/chpc.utah.edu/common/home/chpc-data/SEL_Archive and then cleared. Last updated 12/12/19 -eli hebdon 

export PATH="/usr/lib64/qt-3.3/bin:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin"
NOW=$(date +"%Y-%m-%d" 2>/dev/null)
HOST=$(echo $HOSTNAME 2>/dev/null)
LOG=$(ipmitool sel elist 2>/dev/null)
ARCHIVEDIR="/uufs/chpc.utah.edu/common/home/chpc-data/sel_scripts/logs/sel_archive/ash"
COUNT=$(echo "$LOG" | wc -l 2>/dev/null)

ipmitool sel time set now &>/dev/null
COUNT=$(echo "$LOG" | wc -l)

#log to syslog that we ran and save log to archive
echo "Running SEL Archive cron"  | logger 2>/dev/null
echo "$LOG" > ${ARCHIVEDIR}/${HOST}/${NOW}.log

#clear the event log if it's full or has more than 200 events   
if [[ "$LOG" =~ "Log full" || $COUNT -gt 200 ]]
then
        echo "Clearing event log for ${HOST}" | logger 2>/dev/null
        ipmitool sel clear &>/dev/null
fi

exit 0
