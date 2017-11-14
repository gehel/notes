#!/bin/bash
#########################################################################################
### Script for sending notifications using "Notify My Androids" API                     #
###    Author : Markp1989@gmail.com  Version: 25JULY2011                                #
###    Author : chiristod@illinois.edu  Version: 12FEBRUARY2015                         #
###             (simplified, converted into wrapper for other Bash scripts)             #
#########################################################################################
## Requirements:	curl                                                                #
#########################################################################################
## Usage: notify <command>                                                              #
#########################################################################################
## API Documentation:	https://www.notifymyandroid.com/api.jsp                         #
#########################################################################################

function error_exit {
##this function is used to exit the program in the event of an error.
    echo "[ error ] Notification not sent:"
    echo "$errormessage"
    exit 1

}
function clean_exit {
    echo "[ info ] Notification sent"
    ##removing output file when notification was sent okay
    rm "$notifyout"
    exit 0
}

apikey_file="/home/gehel/.notify/api-key.txt"

## API Key must exist in a directory called .notify; go to http://www.notifymyandroid.com/ to get one
if [ ! -f $apikey_file ]; then
	errormessage="~/.notify/api-key.txt file doesn't exist"
	error_exit
fi
APIkey=`cat $apikey_file`

# check that there is an actual command to run
if [ "$#" -lt 1 ]; then
    errormessage="usage: $0 <command>"
	error_exit
fi

##renaming parameters to make rest of the code more readable.
application="Bash Script"
event="Script Finished"
description=$@
priority=0

##the urls that are used to send the notification##
baseurl="https://www.notifymyandroid.com/publicapi"
verifyurl="$baseurl/verify"
posturl="$baseurl/notify"

##choosing a unique temp file based on the time (date,month,hour,minute,nano second),to avoid concurent usage interfering with each other
notifyout=/tmp/androidNotify$(date '+%d%m%Y%H%M%S%N')

function send_notification {
    ##sending the notification using curl
    curl --silent --data-ascii "apikey=$APIkey" --data-ascii "application=$application" --data-ascii "event=$event" --data-asci "description=$description" --data-asci "priority=$priority" $posturl -o $notifyout
}

function check_notification {
    ##checking that the notification was sent ok.
	if [ ! -f $notifyout ]; then
	    errormessage="curl failed"
	    error_exit
	fi
    ##api returns message 200 if the notification was sent
    if grep -q 200 $notifyout; then
        clean_exit
    else
	    ##getting the error reported by the API, this may break if the API changes its output, will change as soon as I can find a commandline xml parser
	    errormessage="$(cut -f4 -d'>' $notifyout | cut -f1 -d'<')"
	    error_exit
    fi
}

##running the functions
$@
send_notification
check_notification
