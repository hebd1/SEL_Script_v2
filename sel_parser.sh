#!/bin/bash

#This daily script parses the saved SEL of each node in each cluster and creates a daily report of critical and frequently occuring events. System Event Logs are collected and saved to /uufs/chpc.utah.edu/common/home/chpc-data/SEL_Archive. This script then parses SEL_Archive, generates a daily report saved to /uufs/chpc.utah.edu/common/home/chpc-data/SEL_Reports, and emails the reported formatted in HTML. Last updated 01/028/2020 -eli hebdon 

export PATH="/usr/lib64/qt-3.3/bin:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin"
NOW=$(date +"%Y-%m-%d" 2>/dev/null)
CLUSTER=$(manpath -q | rev | cut -d ":" -f 1 | rev | cut -d "/" -f 3 | cut -d "." -f 1 2>/dev/null)
ARCHIVEDIR="/uufs/chpc.utah.edu/common/home/chpc-data/sel_scripts/logs/sel_archive"
REPORTDIR="/uufs/chpc.utah.edu/common/home/chpc-data/sel_scripts/logs/sel_reports"
DICTIONARY='/uufs/chpc.utah.edu/common/home/chpc-data/sel_scripts/bin/critical.txt'


#returns true if the given parameter contains an event that occured within the last month
is_recent() {

	RECENTEVENTS=$(echo "$1" | grep -E "(^|\s)$(date +"%m")/([0][1-9]|[12][0-9]|3[01])/$(date +"%Y")($|\s)")
	if [ -n "$RECENTEVENTS" ]; then
		return 0 # 0 = true
	else
		return 1 # 1 = false
	fi
}

#only run once on notchrm
if [ "$HOSTNAME" = notchrm 2>/dev/null ]
then
        echo "Running SEL Parser cron" | logger 2>/dev/null

	# Setup HTMl table file for critical events
	(
	cat <<-EOF
	<table><caption>---Potential Amber Lights---</caption>
        <tr id=table_header><th>Node</th><th>Date</th><th>Event</th><th>Info</th></tr>
	EOF
	) > ${REPORTDIR}/critical.html

        # Main HTML file and CSS
	(
	cat <<-EOF
	
	<html>
	    <head>
	        <title>SEL Report</title>
	    </head>
	    <style type="text/css">
	        table {
	            width: 80%;
	            max-width: 800px;
	            border-collapse: separate;
	            border-spacing: 0px;
	            border: 2px solid black;
	        }
	        th, td {
	            padding: 5px, 5px;
	            text-align: left;
	            border: 1px solid black;
	        }
	        td {
	            font-size: 14px;
	        }
	        th {
	            font-size: 14px;
	            font-weight: bold;
	            padding-top: 10px;
	            padding-bottom: 10px;
	        }
	        caption {
	            font-size: 20px;
	            font-weight: bold;
	        }
	       
	    </style>
	    <body>
	
	EOF

        # loop through archive directories
        for path in ${ARCHIVEDIR}/*; do

               CLUSTER=$(basename "$path" 2>/dev/null)         
               printf "\n----------------$CLUSTER----------------\n" >> ${REPORTDIR}/${NOW}.rpt 2>/dev/null
	       echo "<table><caption>---$CLUSTER---</caption>"
	       echo "<tr id=table_header><th>Node</th><th>Occurances</th><th>Event</th><th>Info</th></tr>"
	       # variables used to alternate table row color
	       CLOGROW=0
	       CRITICALROW=0
               for node in ${ARCHIVEDIR}/${CLUSTER}/*; do
                       LOG=$(find $node -name "*${NOW}*" 2>/dev/null)
                       HOST=$(basename "$node" 2>/dev/null)
                       #no log found on node, save as unresponsive
                       if [ -z "$LOG" 2>/dev/null ] 
                       then
                               echo "$HOST," >> ${REPORTDIR}/unresponsive.tmp 2>/dev/null
		       else
			       # parse out recent critical events
			       CRITICAL=$(cat "${LOG}" | grep -f "$DICTIONARY" | tail -1) 
			       if [[ -n "$CRITICAL" ]] && is_recent "$CRITICAL"; then
					DATE=$(echo "${CRITICAL}" | cut -d "|" -f 2)
					EVENT=$(echo "${CRITICAL}" | cut -d "|" -f 4)
					INFO=$(echo "${CRITICAL}" | cut -d "|" -f 5)
					if [[ $((CRITICALROW%2)) -eq 0 ]];then
                                        	ROWCSS=$(echo '')
                                        else 
                                        	ROWCSS=$(echo 'background-color: #B8B8B8')
                                        fi

					echo "<tr style='$ROWCSS'><td>$HOST</td><td>$DATE</td><td>${EVENT}</td><td>$INFO</td></tr>" >> ${REPORTDIR}/critical.html
					CRITICALROW=$((CRITICALROW+1))
			       fi

			       # only parse logs with recent events				
			       if is_recent "$(cat $LOG)"; then
                              	 	#parse out frequently occuring events that clog up the log
                              	 	CLOG=$(cat "${LOG}" | cut -d "|" -f 4,5 | sort | uniq -c | sort -n | tail -1 2>/dev/null)                            
			      	 	OCCURANCES=$(echo "$CLOG" | awk '{ print $1 }')
			      	 	EVENT=$(echo "$CLOG" | cut -d '|' -f1 | cut -d ' ' -f6-)
			      	 	INFO=$(echo "$CLOG" | cut -d ' ' -f2- | cut -d '|' -f2)
                              	 	if [[ $OCCURANCES -gt 100 ]] && [[ ! "${LOG}" =~ "#" ]]; then
			      	 	 	if [[ $((CLOGROW%2)) -eq 0 ]];then
			      	 	 		ROWCSS=$(echo '')
			      	 	 	else 
			      	 	 		ROWCSS=$(echo 'background-color:#B8B8B8')
			      	 	 	fi
                              	 	        echo $HOST " | " $CLOG " | " >> ${REPORTDIR}/${NOW}.rpt 2>/dev/null

			      	 	        echo "<tr style='$ROWCSS'><td>$HOST</td><td>$OCCURANCES</td><td>${EVENT}</td><td>$INFO</td></tr>"
			      	 	CLOGROW=$((CLOGROW+1))
                              	 	fi
			       fi
                       fi
               
                done
		echo "</table><br>"
        done

	#finish html
        echo "</table><br>" >> ${REPORTDIR}/critical.html
        ) > ${REPORTDIR}/report.html

 
       #parse out top issues and append to the top of the report
       FOCUSED=$(cat "${REPORTDIR}/${NOW}.rpt" | grep -f "$DICTIONARY" | tail -1 2>/dev/null)
       echo -e "--------Critical Events---------\n${FOCUSED}\n$(cat "${REPORTDIR}/${NOW}.rpt")" > ${REPORTDIR}/${NOW}.rpt
       echo -e "<h3> Report for $NOW </h3><p> Tables below list both recent critical events as well as frequently occuring events that clog up the SEL of each node. Events must occur within the last month to be considered recent.</p>$(cat "${REPORTDIR}/critical.html")\n$(cat "${REPORTDIR}/report.html")" > ${REPORTDIR}/report.html

        #place unresponsive nodes in report
        UNRESPONSIVE=$(cat ${REPORTDIR}/unresponsive.tmp 2>/dev/null)
        echo -e "\n--------Unresponsive Nodes---------\n${UNRESPONSIVE}\n" >> ${REPORTDIR}/${NOW}.rpt
        echo -e "\nUnresponsive Nodes:\n${UNRESPONSIVE}\n" >> ${REPORTDIR}/report.html
        echo "<p>The SEL of each node is collected by 'sel_logger.sh' via cron.daily and stored at /uufs/chpc.utah.edu/common/home/chpc-data/sel_scripts/logs/sel_archive. Archive parsing is accomplished by 'sel_parser.sh' on notchrm cron.d. Reports are also saved in text format to /uufs/chpc.utah.edu/common/home/chpc-data/sel_scripts/logs/sel_reports.</p></body></html>" >> ${REPORTDIR}/report.html 
	rm ${REPORTDIR}/unresponsive.tmp 2>/dev/null
       
fi

# Email the report
(
echo From: $whoami@@$hostname
echo To: eli.hebdon@utah.edu
echo "Content-Type: text/html;"
echo "Subject:SEL Report ${NOW}"
echo
cat ${REPORTDIR}/report.html
) | /usr/sbin/sendmail -t

#remove html files
rm ${REPORTDIR}/report.html 2>/dev/null
rm ${REPORTDIR}/critical.html 2>/dev/null
exit 0
