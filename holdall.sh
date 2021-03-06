#!/bin/bash

#readonly ARGS=$@
readonly PROGNAME=$(basename $0)
readonly PROGDIR=$(readlink -m $(dirname $0))
readonly DEFAULTNOOFBACKUPSTOKEEP=2

readonly YES=y
readonly CANCEL=n
readonly NOOVRD=x
readonly OVRDHOSTTORMVBL=2
readonly OVRDRMVBLTOHOST=8
readonly OVRDSYNC=s
readonly OVRDERASERECORD=e

readonly SYNCDIRECTIONRMVBLTOHOST=SDRTH
readonly SYNCDIRECTIONHOSTTORMVBL=SDHTR

readonly ERRORMESSAGENoRsync="error: rsync is not installed on the system. This program uses rsync. Use your package manager to install it."
readonly ERRORMESSAGENoOfArgs="error: wrong number of arguments provided - use $PROGNAME -h for help. "
readonly ERRORMESSAGEUnreadableLocsList="error: errorPermissionsLocsList: couldn't read the locations-list file."
readonly ERRORMESSAGEUnwritableLocsList="error: errorPermissionsLocsList: couldn't write to the locations-list file."
readonly ERRORMESSAGENonexistentRmvbl="error: errorPermissionsRmvbl: removable drive directory $RMVBLDIR nonexistent. "
readonly ERRORMESSAGEUnreadableRmvbl="error: errorPermissionsRmvbl: removable drive directory unreadable. "
readonly ERRORMESSAGEUnwritableRmvbl="error: errorPermissionsRmvbl: removable drive directory unwritable. "
readonly ERRORMESSAGEPermissionsSyncStatusFile="error: errorPermissionsSyncStatusFile: could not read/write syncStatusFile. "

readonly WARNINGSyncStatusForNonexistentItems="Warning: This item does not exist on this host or the removable drive but the status file says it should."
readonly WARNINGNonexistentItems="Warning: This item does not exist on this host or the removable drive. "
readonly WARNINGStatusInconsistent="Warning: The sync status for this item is invalid: This host is stated as being up-to-date with changes but there is no synchronisation date. "
readonly WARNINGSyncedButRmvblAbsent="Warning: There is a record of synchronising this item but it is not present on the removable drive. "
readonly WARNINGSyncedButHostAbsent="Warning: There is a record of synchronising this item but it is not present on the local host. "
readonly WARNINGMismatchedItems="Warning: The items on disk have conflicting types - one is a folder but one is a file. "
readonly WARNINGUnexpectedSyncStatusAbsence="Warning: The items both exist but there is no record of a synchronisation date. "
readonly WARNINGFork="Warning: The item has been forked - the removable drive and host version have independent changes. "
readonly WARNINGUnexpectedlyNotOnUpToDateList="Warning: The item is showing no changes since last recorded sync but this host is not listed as having the latest changes. "
readonly WARNINGUnexpectedDifference="Warning: The items differ even though the items' last modifications are dated before their last sync"
readonly WARNINGAmbiguousTimings="Warning: Showing a simulataneous modification and synchronisation - the situation is ambiguous. " 
readonly MESSAGEAlreadyInSync="No changes since last synchronisation. "
readonly MESSAGESyncingRmvblToHost="Syncing removable drive >> host"
readonly MESSAGESyncingHostToRmvbl="Syncing host >> removable drive"

readonly LINEOFDASHES="----------------------------------------------------------------------------------------------------------------------------" # visual separator

# ---------- TO DO ----------
# implement checking if an itemHostLoc is a subfolder of itemRmvblLoc, or vice-versa
# ---------------------------

# these getters aren't encapsulation, they're just for making the code neater elsewhere
getPretend(){ 
	if [[ $PRETEND == "on" ]]; then return 0; else return 1; fi 
}
getVerbose(){
	if [[ $VERBOSE == "on" ]]; then return 0; else return 1; fi 
}
getPermission(){
	if [[ $INTERACTIVEMODE == "off" ]]; then return 0; fi # if we're not in interactive mode then simply return true
	local prompt="$1"
	echo "    $prompt"
	local input=""
	read -p '    (interactive mode) proceed? y/n : ' input </dev/tty
	if [[ "$input" == "y" ]]
	then
		echo "    (interactive mode) proceeding"
		return 0
	else
		echo "    (interactive mode) permission DENIED - skipping"
		return 1
	fi
}
cleanCommentsAndWhitespace(){
	local inputFile="$1"
	# three stetps to clean the input
	# 1. remove comments - grep to keep only the parts of the line before any #
	# 2. remove leading whitespace - sed to replace leading whitespace with nothing
	# 3. remove trailing whitespace - sed to replace trailing whitespace with nothing
	local outputFile="$(\
		grep -o ^[^#]* $inputFile \
		| sed 's/^[[:space:]]*//' \
		| sed 's/[[:space:]]*$//' \
	)"
	echo "$outputFile"
}
echoToLog(){
	getPretend || echo "$(date +%F,%R), $HOSTNAME, $1" >> $LOGFILE
}

showHelp(){
	cat <<- _EOF_
	$PROGNAME HELP:
	
	$PROGNAME is for synchronising files/folders between several different 
	computers privately or over an "air-gap", using a removable drive.
	e.g. files/folders on one system are synchronised with a removable drive,
	     and then the removable drive is synchronised with the second system.
	
	$PROGNAME can synchronise computers over an "air-gap", e.g. with computers that do not have internet access.
	Crucially, $PROGNAME will detect problems e.g. if a file has been forked between different computers.
	
	$PROGNAME uses rsync and by default the "--backup-dir" option is used, such that $DEFAULTNOOFBACKUPSTOKEEP synchronisations can be manually reverted.
	
	USAGE: 
	$PROGNAME [OPTIONS: h,p,v,a,i,l,s,f,b] syncTargetFolder
	  - "syncTargetFolder" should be the removable drive directory, e.g. /media/USBStick
	
	OPTIONS:
	  -h	display this message and exit
	  -p	run in pretend mode - do not write to disk, only pretend to. Use to safely preview the program.
	  -v	run in verbose mode - display extra messages
	  -a	run in automatic mode - does not prompt for input (does not apply to interactive mode)
	  -i	run in interactive mode - user must approve or refuse each rsync and rm command individually
	  -l	display a list of synced/syncable items only, do not sync.
	  -s    use to append a NEW location to the locations-list file e.g. "-s work/docs/reports" or "-s work/docs/reports|accountingReports" . Then proceeds with sync.
	  -f	give this option and then a locations-list file to override the default. If not present a template will be created.
	  -b    give this option and then a custom number of backups to keep when writing (to override default = $DEFAULTNOOFBACKUPSTOKEEP). 0 is allowed.
	
	SETUP:
	On first-time run a locations-list file will be created.
	To synchronise a file/folder you will need to put its location into the locations-list file. You can edit 
	the locations-list file directly or use the -s option to add one location at a time.
	On first-time run user must approve creation of a new sync status file.

	THE LOCATIONS-LIST FILE:
	On the removable drive there is a separate locations-list file for each computer you sync with.
	The default filename for this host is syncLocationsOn_$HOSTNAME
	Inside the locations of folders/files to sync are listed, one per line.
	To copy a folder/file to a different name you can give the alternate name after a "|" delimiter - see example 2 below:
	TWO EXAMPLES:
	Imagine you ran
	   $PROGNAME /media/USBStick
	it would find the locations-list file and read the first location, which is:
	e.g. 1)
	   /home/quentin/documents/work
	it would read this line and sync "/home/quentin/documents/work" with "/media/USBStick/work"
	e.g. 2)
	   /home/quentin/documents/work|schoolWork
	it would read this line and sync "/home/quentin/documents/work" with "/media/USBStick/schoolWork"
	_EOF_
}
usage(){
	echo "Usage: $PROGNAME [OPTIONS: h,p,v,a,i,l,s,f,b] syncTargetFolder"
	echo use $PROGNAME -h to see full help text
}
addLocation(){
	local locationToAdd="$1"
	getPermission "append $locationToAdd to locations-list file?" && (getPretend || echo "$locationToAdd" >> $LOCSLIST)
	return $?
}
listLocsListContents(){
	echo ""
	echo "LIST MODE"
	echo "locations-list file has instructions to sync the following locations from this host:"
	echo "(the basename of these locations is used as the file/folder name on the removable drive, unless indicated)"
	echo ""
	echo -------synced files/folders-------
	cleanCommentsAndWhitespace $LOCSLIST \
	| sed \
		-e "s:|\(.*\):\t <- (syncs to different name '\1'):" 
		# using ":" instead of "/" as delimeter in "sed s-match-replace" because at runtime $RMVBLDIR will itself contain one or more "/"
	echo ""
	
	# LOCSLIST may contain e.g.
	# /folders/work1/
	# /folders/work2
	# /folders/work3|reports
	# and would want listOfItemNames to contain
	# work1
	# work2
	# reports
	# so need to do some regex to make it happen
	
	# regex used to create listOfItemNames:
	# 1: remove comments
	# 2: grep to get alises - keep only end of line backwards until any |
	# 3: sed to remove a possible trailing / from end of a folder address
	# 4: grep to get basenames - keep only from end of line backwards until any /
	# 5: grep to remove blank lines
	# 6: sort
	# 7: uniq to remove entries that are invalid because they clash with other entries - keep only non-repeated lines
	local listOfItemNames="$(\
	cleanCommentsAndWhitespace $LOCSLIST \
	| grep -o "[^|]*$" \
	| sed 's:^\(.*\)/$:\1:' \
	| grep -o "[^/]*$" \
	| grep -v "^\s*$" \
	| sort \
	| uniq --unique \
	)"
	
	local listOfItemNamesOnRmvbl="$(ls -B $RMVBLDIR)"
	local listItemsNotSynced=$(comm -23 <(echo "$listOfItemNamesOnRmvbl") <(echo "$listOfItemNames"))
	# comm -23 is returning things appearing in $listOfItemNamesOnRmvbl but not in $listOfItemNames
	local listItemsNotSyncedButAreSyncable=$(grep -v "^syncStatus$" <<< "$listItemsNotSynced" | grep -v "^syncLocationsOn_" | grep -v "^syncLog$")
	# this last command hides this program's info files from the list
	
	echo -------other files/folders on the removable drive-------
	echo "$listItemsNotSyncedButAreSyncable"
	
	scanLocsList
	exit 0
}

scanLocsList(){
	
	# this scanning needs to become quite a bit more sophisticated for the updated format of the locs list...
	
	# check for repeated names/repeated locations
	
	# ---GUIDE TO THE PIPING/REGEX USED---
	# 
	# because sed, piping and regular expressions have the same readability as ancient Chinese handwritten by a drunken doctor
	# 
	# sed 's/^\([^#]*\)#.*/\1/' $LOCSLIST strips out comments
	# sed "s/^.*|\(.*\)/\1/" then replaces "/file/addresses|alias" with "alias"
	# sed "s/^.*\/\(.*\)/\1/" then replaces any addresses left over with their basenames
	# grep -v "^\s.*$" then strips out empty lines
	# sort then sorts alphabetically
	# uniq -d then finds ADJACENT repeated lines
	
	# check for names appearing more than once
	local listOfRepeatedNames=$(\
	cleanCommentsAndWhitespace $LOCSLIST \
	| sed -e "s/^.*|\(.*\)/\1/" -e "s/^.*\/\(.*\)/\1/" \
	| grep -v "^\s*$" \
	| sort \
	| uniq -d \
	)
	
	# similarly, sed "s/^\(.*\)|.*/\1/" replaces "/file/address|alias" with "/file/address" - i.e. strips out aliases
	# otherwise identical to the above
	
	# check for items appearing more than once
	local listOfRepeatedLocations=$(\
	cleanCommentsAndWhitespace $LOCSLIST \
	| sed "s/^\(.*\)|.*/\1/" \
	| grep -v "^\s*$" \
	| sort \
	| uniq -d \
	)
	
	# return 0 if no repeats were found
	if [[ (-z $listOfRepeatedNames) && (-z $listOfRepeatedLocations) ]]; then return 0; fi
	# else complain and exit
	echo "error: there are repeated names and/or repeated locations in $LOCSLIST"
	echo "repeated names:"
	echo $listOfRepeatedNames
	echo "repeated locations:"
	echo $listOfRepeatedLocations
	echo "please remove the duplicates by editing the file $LOCSLIST"
	exit 9;
}
createLocsListTemplateDialog(){
	echo "The locations-list file $LOCSLIST does not exist."
	if [[ $AUTOMATIC == "on" ]]
	then
		echo automatic mode set - skipping dialog asking to create a template locations-list file
		return 0
	fi
	echo "   You can generate a new template locations-list file at $LOCSLIST"
	echo "   $YES to make a new template there"
	echo "   $CANCEL to not"
	local input=""
	read -p '   > ' input 
	if [[ $input == $YES ]]
	then
		getPretend && return 0
		# a here script
		cat <<- _EOF_ >$LOCSLIST
		# this file is for use with the synchronisation program $PROGNAME (in $PROGDIR)
		# This file supports comments on a line after a #.
		# give the locations of files and folders you wish to sync.
		# One item per line, format: 'address|name', where optional '|name' is used to sync things to a different name
		# 
		# --- help and examples ---
		# two examples:
		# /home/somewhere/correspondence             # this would sync  /home/somewhere/correspondence  with  /<location of removable drive>/correspondence
		# /home/somewhere/someOldReports|workStuff   # this would sync  /home/somewhere/someOldReports  with  /<location of removable drive>/workStuff
		# (where  /<location of removable drive>/ should be the location of your removable drive, specified as the argument to $PROGNAME)
		# for help see: $PROGNAME -h
		# 
		# ---(some more examples)---
		# /home/mike/payslips 
		# /home/mike/work/spreadsheets    # because I can't work without them!
		# /home/mike/Documents/contactsList.xml 
		# /home/mike/Documents/systemspecs.pdf|systemspecsOf$HOSTNAME.pdf 
		# /home/mike/Documents/myScripts 
		# /media/internalHDD/myScripts|myScriptsHDD 
		# /media/internalHDD/Pictures/motivationalPosters 
		# /home/mike/work/stupidReport.pdf|importantReading.pdf 
		# ---(end of examples)---
		_EOF_
		echo "new file created."
		echoToLog "created template locs list file $LOCSLIST"
	else
		echo "not generating a file"
	fi
}
noSyncStatusFileDialog(){
	echo "could not find sync data file $SYNCSTATUSFILE."
	if [[ $AUTOMATIC != "on" ]]
	then
		echo "   Create the file?"
		echo "   $YES to create a new blank file and begin using it"
		echo "   $CANCEL to abort the program"
		local input=""
		read -p '   > ' input
	else
		echo Automatic mode set - creating new sync status file $SYNCSTATUSFILE
		local input=$YES
	fi
	if [[ $input == $YES ]]
	then
		getPretend || touch $SYNCSTATUSFILE
		echoToLog "created sync data file $SYNCSTATUSFILE"
	else
		echo "not generating a file"
	fi
}
eraseItemFromStatusFileDialog(){
	local itemName="$1"
	if [[ $AUTOMATIC != "on" ]]
	then
		echo "   Erase the status for $itemName?"
		echo "   $YES to erase"
		echo "   $CANCEL to take no action"
		local input=""
		read -p '   > ' input </dev/tty # </dev/tty means read from keyboard, not from redirects. Since this is inside the redirected while loop it must avoid being redirected too
	else
		echo Automatic mode set - erasing this item from the status
		echo "creating backup of current status $SYNCSTATUSFILE in $SYNCSTATUSFILE.bckp"
		getPretend || cp $SYNCSTATUSFILE $SYNCSTATUSFILE.bckp
		local input=$YES
	fi
	if [[ $input == $YES ]]
	then
		echo erasing
		# erase this item from the log
		eraseItemFromStatusFile "$itemName"
	else
		echo not erasing
	fi
	return 0
}
eraseItemFromStatusFile(){
	getPretend && return 0
	local itemName="$1"
	sed -e "s/^$itemName $HOSTNAME LASTSYNCDATE .*//" -e "s/\(^$itemName UPTODATEHOSTS.*\) $HOSTNAME,\(.*\)/\1\2/" <$SYNCSTATUSFILE >"$SYNCSTATUSFILE.tmp" && mv "$SYNCSTATUSFILE.tmp" "$SYNCSTATUSFILE"
	grep -v '^\s*$' <"$SYNCSTATUSFILE" | sort >"$SYNCSTATUSFILE.tmp" && mv "$SYNCSTATUSFILE.tmp" "$SYNCSTATUSFILE"
	echoToLog "$itemName, erased from sync data file"
}
chooseVersionDialog(){
	local itemName="$1"
	local itemHostLoc="$2"
	local itemHostModTime=$3
	local itemHostModTimeReadable=$(date --date=@$itemHostModTime +%c) # the '@' indicates the date format as the number of seconds since the epoch
	local itemRmvblLoc="$4"
	local itemRmvblModTime=$5
	local itemRmvblModTimeReadable=$(date --date=@$itemRmvblModTime +%c)
	local itemSynctime=$6
	local itemSyncTimeReadable=$(date --date=@$itemSyncTime +%c)
	
	if [[ $AUTOMATIC == "on" ]]
	then
		echo -n "Automatic mode on > "
		if [[ $itemRmvblModTime -gt $itemHostModTime ]]
		then
			echo "writing newer $itemRmvblLoc from $itemRmvblModTimeReadable onto $itemHostLoc from $itemHostModTimeReadable"
			synchronise "$itemName" $SYNCDIRECTIONRMVBLTOHOST "$itemHostLoc" "$itemRmvblLoc"
		else 
			echo "writing newer $itemHostLoc from $itemHostModTimeReadable onto $itemRmvblLoc from $itemRmvblModTimeReadable"
			synchronise "$itemName" $SYNCDIRECTIONHOSTTORMVBL "$itemHostLoc" "$itemRmvblLoc"
		fi
	else # print some information to help the user choose whether to write host>rmvbl or rmvbl>host
		echo "   USER INPUT REQUIRED  -  keep which version of itemName $itemName?"
		if [[ -d "$itemRmvblLoc" ]]
		then 
			echo "   listing FILES modified since last synchronisation"
		else
			echo "   using diff --side-by-side --suppress-common-lines"
		fi
		echo $LINEOFDASHES
		diff -y <(echo "Host (ls folder contents/file contents) on left") <(echo "Removable drive (ls folder contents/file contents) on right")
		diff -y <(echo "Host mod time $itemHostModTimeReadable") <(echo "Removable drive mod time $itemRmvblModTimeReadable")
		# (just using diff -y here so it lines up with listing below)
		echo $LINEOFDASHES
		if [[ -d "$itemRmvblLoc" ]] # if a directory: show diff of recursive dir contents and list files that differ
		then
			# use a sed to remove the unwanted top-level directory address, leaving just the part of the file address relative to $itemHostLoc($itemRmvblLoc)
			local unsyncedModificationsHost=$(sed "s:^$itemHostLoc/::" <(find $itemHostLoc -newermt @$itemSyncTime | sort))
			local unsyncedModificationsRmvbl=$(sed "s:^$itemRmvblLoc/::" <(find $itemRmvblLoc -newermt @$itemSyncTime | sort))
			diff -y <(echo -e "$unsyncedModificationsHost") <(echo -e "$unsyncedModificationsRmvbl")
		else # if a file: show diff of the two files
			diff -y --suppress-common-lines "$itemHostLoc" "$itemRmvblLoc"
		fi
		echo $LINEOFDASHES
		echo "   (blank if no difference)"
		# time for the dialog itself
		echo "   $NOOVRD to take no action this time (re-run to see this dialog again)"
		echo "   $OVRDHOSTTORMVBL to sync the host copy onto the removable drive copy"
		echo "   $OVRDRMVBLTOHOST to sync the removable drive copy onto the host copy"
		local input=""
		read -p '   > ' input </dev/tty
		if [[ $input == $OVRDHOSTTORMVBL ]]
		then
			synchronise "$itemName" $SYNCDIRECTIONHOSTTORMVBL "$itemHostLoc" "$itemRmvblLoc"
		else
			if [[ $input == $OVRDRMVBLTOHOST ]]
			then
				synchronise "$itemName" $SYNCDIRECTIONRMVBLTOHOST "$itemHostLoc" "$itemRmvblLoc"
			else
				echo "$itemName: taking no action"
			fi
		fi # end if [ ...user input... ]
	fi # end if [ automatic mode ]
}

unexpectedAbsenceDialog(){
	local itemName="$1"
	local itemHostLoc="$2"
	local itemRmvblLoc="$3"
	local absentItem=$4
	
	if [[ $absentItem == "host" ]]
	then
		echo Host item $itemHostLoc expected but does not exist
		local absenceMessage="sync $itemRmvblLoc on removable drive onto $itemHostLoc"
	else
		if [[ $absentItem == "removable" ]]
		then
			echo Removable drive item $itemRmvblLoc expected but does not exist
			local absenceMessage="sync $itemHostLoc on host onto $itemRmvblLoc"
		else
			echo unexpectedAbsenceDialog: invalid arg no.6 - hard-coded error exists
			exit 100
			return 1
		fi
	fi
	
	if [[ $AUTOMATIC == "on" ]]
	then
		echo -n "Automatic mode on > "
		echo will $absenceMessage
		local input=$OVRDSYNC
	else
		# the dialog
		echo "   $NOOVRD to take no action this time (re-run to see this dialog again) "
		echo "   $OVRDSYNC to $absenceMessage"
		echo "   $OVRDERASERECORD to erase the status for this item (though erasing the status may not solve the problem - be careful)"
		local input=""
		read -p '   > ' input </dev/tty
	fi
	
	# taking action
	if [[ $input == $OVRDSYNC ]]
	then
		if [[ $absentItem == "removable" ]]
		then
			synchronise "$itemName" $SYNCDIRECTIONHOSTTORMVBL "$itemHostLoc" "$itemRmvblLoc"
		else # then can assume $absentItem == "host"
			synchronise "$itemName" $SYNCDIRECTIONRMVBLTOHOST "$itemHostLoc" "$itemRmvblLoc"
		fi
	else
		if [[ $input == $OVRDERASERECORD ]]
		then
			eraseItemFromStatusFile "$itemName"
		else
			echo "$itemName: taking no action"
		fi
	fi
}

synchronise(){
	# once the caller has decided which direction to sync, this function handles the multiple steps involved
	# 1. Synchronising with rsync in syncSourceToDest  2. removing old backups at dest  3. updating the status
	
	local itemName="$1"
	local syncDirection=$2
	local itemHostLoc="$3"
	local itemRmvblLoc="$4"
	
	case $syncDirection in
		$SYNCDIRECTIONHOSTTORMVBL)
			echo "$itemName: $MESSAGESyncingHostToRmvbl"
			syncSourceToDest "$itemHostLoc" "$itemRmvblLoc"
			local copyExitVal=$?
			if [[ $copyExitVal -eq 0 ]]; then writeToStatus "$itemName" $syncDirection; fi
			echoToLog "$itemHostLoc, copied to, $itemRmvblLoc, rsync exit status=$copyExitVal"
			removeOldBackups "$itemRmvblLoc"
			;;
		$SYNCDIRECTIONRMVBLTOHOST)
			echo "$itemName: $MESSAGESyncingRmvblToHost"
			syncSourceToDest "$itemRmvblLoc" "$itemHostLoc"
			local copyExitVal=$?
			if [[ $copyExitVal -eq 0 ]]; then writeToStatus "$itemName" $syncDirection; fi
			echoToLog "$itemRmvblLoc, copied to, $itemHostLoc, rsync exit status=$copyExitVal"
			removeOldBackups "$itemHostLoc"
			;;
		*)
			echo synchronise was passed invalid argument $syncDirection, there is a hard-coded fault
			echo "(synchronise expects $SYNCDIRECTIONRMVBLTOHOST or $SYNCDIRECTIONHOSTTORMVBL)"
			exit 101
			;;
	esac
}


syncSourceToDest(){
	local sourceLoc="$1"
	local destLoc="$2"
	local copyExitVal=""
	
	# set the options string for rsync
	local shortOpts="-rtgop" # short options always used
	getVerbose && shortOpts="$shortOpts"v # if verbose then make rsync verbose too
	local longOpts="--delete" # long options always used
	if [[ $NOOFBACKUPSTOKEEP -gt 0 ]]
	then 
		# then have rsync use a backup - add 'b' and '--backup-dir=' options to the options string
		local backupName=$(dirname "$destLoc")/$(basename "$destLoc")-removed-$(date +%F-%H%M)~
		shortOpts="$shortOpts"b 
		local longOptBackup="--backup-dir=$backupName" 
	else
		local longOptBackup=""
	fi
	getPretend && longOpts="$longOpts --dry-run" # if pretending make rsync pretend too    # note: rsync --dry-run does not always _entirely_ avoid writing to disk...?
	
	# for proper behaviour with directories need a slash after the source, but with files this syntax would be invalid
	if [[ -d "$sourceLoc" ]] # if it is a directory
	then
		getPermission "want to call rsync $shortOpts $longOpts $longOptBackup $sourceLoc/ $destLoc" && rsync $shortOpts $longOpts "$longOptBackup" "$sourceLoc"/ "$destLoc"
		copyExitVal=$?
		
		# but this leaves the destination's top-level dir modification time to be 
		# NOW instead of that of the source, so sync this final datum before finishing
		getPretend || touch -m -d "$(date -r "$sourceLoc" +%c)" "$destLoc" # WHOAH. BE CAREFUL WITH QUOTES - but this works OK apparently
		
	else # if it is a file
		getPermission "want to call rsync $shortOpts $longOpts $longOptBackup $sourceLoc $destLoc" && rsync $shortOpts $longOpts "$longOptBackup" "$sourceLoc" "$destLoc"
		copyExitVal=$?
	fi
	
	getVerbose && echo "copy complete"
	
	if [[ $copyExitVal -ne 0 ]]; then echo "WARNING: copy command returned error - exit status $copyExitVal - assuming complete failure"; fi
	return $copyExitVal
}
removeOldBackups(){ # not fully tested - e.g. not with pretend option set, not with strange exceptional cases
	local locationStem="$1"
	
	ls -d "$locationStem"* 2>/dev/null | grep "$locationStem-removed" >/dev/null 
	local oldBackupsExist=$?
	if [[ $oldBackupsExist -ne true ]]; then return 0; fi
	
	getVerbose && echo checking for expired backups
	local oldBackups=$(ls -d "$locationStem"-removed* | sort | head --lines=-$NOOFBACKUPSTOKEEP)
	getVerbose && echo -e "backups existing:\n$(ls -1d "$locationStem"-removed* | sort)"
	if [[ ! -z $oldBackups ]]
	then
		local rmOptsString="-r"
		getVerbose && rmOptsString="$rmOptsString"v
		ls -d "$locationStem"-removed* | sort | head --lines=-$NOOFBACKUPSTOKEEP | while read oldBackupName # loop over expired backups
		do
			getPermission "want to call rm $rmOptsString $oldBackupName" && (getPretend || rm $rmOptsString "$oldBackupName")
		done
	fi
}

writeToStatus(){
	getPretend && return 0; # in pretend mode simply skip this entire function
	local itemName="$1"
	local syncDirection="$2"
	
	#  - make sure a date line exists 
	grep "^$itemName $HOSTNAME LASTSYNCDATE .*" $SYNCSTATUSFILE >/dev/null
	local dateLineExists=$? # if not true then create a new date line
	if [[ $dateLineExists -ne true ]]; then echo "$itemName $HOSTNAME LASTSYNCDATE x">>$SYNCSTATUSFILE; fi
	#  - make sure a hosts line exists 
	grep "^$itemName UPTODATEHOSTS.*$" $SYNCSTATUSFILE >/dev/null
	local hostsLineExists=$? # if not true then make a new hosts line
	if [[ $hostsLineExists -ne true ]]; then echo "$itemName UPTODATEHOSTS">>$SYNCSTATUSFILE; fi
	
	# edit the date line to set date of last sync to current time 
	sed "s/^$itemName $HOSTNAME LASTSYNCDATE.*/$itemName $HOSTNAME LASTSYNCDATE $(date +%s)/" <$SYNCSTATUSFILE >"$SYNCSTATUSFILE.tmp" && mv "$SYNCSTATUSFILE.tmp" "$SYNCSTATUSFILE"
	
	# update the hosts line
	if [[ $syncDirection == $SYNCDIRECTIONHOSTTORMVBL ]]
	then
		# then removable drive just accepted a change from this host, delete all other hosts from up-to-date list
		sed "s/^$itemName UPTODATEHOSTS.*/$itemName UPTODATEHOSTS $HOSTNAME,/" <$SYNCSTATUSFILE >"$SYNCSTATUSFILE.tmp" && mv "$SYNCSTATUSFILE.tmp" "$SYNCSTATUSFILE"
	else
		if [[ $syncDirection == $SYNCDIRECTIONRMVBLTOHOST ]]
		then
			# then this host just accepted a change from removable drive, it should be on the up-to-date hosts list
			# if it's not already on the list...
			grep "^$itemName UPTODATEHOSTS.* $HOSTNAME,.*$" $SYNCSTATUSFILE >/dev/null
			local alreadyOnUpToDateHostsList=$?
			if [[ alreadyOnUpToDateHostsList -ne true ]]
			then
				# ... then append it to up-to-date hosts list
				sed "s/^$itemName UPTODATEHOSTS\(.*\)$/$itemName UPTODATEHOSTS\1 $HOSTNAME,/" <$SYNCSTATUSFILE >"$SYNCSTATUSFILE.tmp" && mv "$SYNCSTATUSFILE.tmp" $SYNCSTATUSFILE
			fi
		else
			echo writeToStatus was passed invalid argument $syncDirection, there is a hard-coded fault
			exit 102
		fi
	fi
	getVerbose && echo "$itemName: status updated."
}

readOptions(){
	PRETEND="off"
	VERBOSE="off"
	AUTOMATIC="off"
	NOOFBACKUPSTOKEEP=$DEFAULTNOOFBACKUPSTOKEEP
	CUSTOMLOCATIONSFILE=""
	ADDEDLOCATION=""
	LISTMODE="off"
	INTERACTIVEMODE="off"
	
	while getopts ":hpvaf:b:s:li" opt # the first colon suppress getopts' error messages and I substitute my own. The others indicate that an argument is taken.
	do
		case $opt in
		h)	showHelp; exit 0;;
		p)	readonly PRETEND="on"; echo PRETEND MODE;; # leaves messages unchanged but doesn't actually do any writes
		v)	readonly VERBOSE="on";; 
		a)	readonly AUTOMATIC="on";; # automatically answers dialogs, does not require keyboard input
		f)	readonly CUSTOMLOCATIONSFILE="$OPTARG";;
		b)	readonly NOOFBACKUPSTOKEEP="$OPTARG";;
		s)	readonly ADDEDLOCATION="$OPTARG";;
		l)	readonly LISTMODE="on";; # If "on" program will branch away from main flow to show a list and exit early instead
		i)	readonly INTERACTIVEMODE="on";; # If "on" program lets user veto rsync or rm commands
		\?)	echo invalid option "$OPTARG"; exit 1;;
		esac
	done
	
	# check that number of backups to keep is a positive integer === a string containing only digits
	if [[ "$NOOFBACKUPSTOKEEP" =~ .*[^[:digit:]].* ]]
	then
		echo "invalid number given to option '-b' : '$NOOFBACKUPSTOKEEP' "
		exit 1
	fi
}
modTimeOf(){
	# returns the latest mod time of argument $1
	# if passed a file, it returns the mod time of the file, 
	# if passed a directory, returns the latest mod time of the directory, its subdirectories, and its contained files.
	# in the format seconds since epoch
	
	local queriedItem="$1"
	local itemModTime=""
	local fileModTime=""
	local subdirModTime=""
	
	if [[ ! -e "$queriedItem" ]]; then echo "modTimeOf called on nonexistent file/folder $queriedItem - hard-coded mistake exists"; exit 103; fi
	
	if [[ -d "$queriedItem" ]] # if it is a directory
	then
		fileModTime=$(find "$queriedItem" -type f -exec date -r \{\} +%s \; | sort -n | tail -1) # = most recent mod time among the files (if no files present returns empty string)
		subdirModTime=$(find "$queriedItem" -type d -exec date -r \{\} +%s \; | sort -n | tail -1) # = most recent mod time among the dirs (including $queriedItem itself)
		# subdirModTime includes the top dir itself; it cannot be blank. 
		if [[ -z $fileModTime ]] # if there were no files (i.e. only (sub)directories)
		then
			itemModTime=$subdirModTime
		else
			if [[ $fileModTime -gt $subdirModTime ]]; then itemModTime=$fileModTime; else itemModTime=$subdirModTime; fi # choose the newer of the mod times
		fi
	else # if it is a file
		itemModTime=$(date -r "$queriedItem" +%s)
	fi
	
	echo $itemModTime
}
noRsync(){ # NOT TESTED =P
	echo $ERRORMESSAGENoRsync
	exit 3
}
main(){
	if [[ $@ == *"--help"*  ]]; then showHelp; exit 0; fi
	readOptions "$@"
	shift $(($OPTIND-1)) # builtin function "getopts" (inside readOptions) is always used in conjunction with "shift"
	
	if [[ $# -ne 1 ]]
	then
		echo $# command-line arguments given, 1 expected
		usage	
		exit 2
	fi
	which rsync >/dev/null || noRsync # noRsync deals with eventuality that rsync isn't installed
	# should also use this method to detect presence of other required programs, just in case.
	
	# check the removable drive is ready
	readonly RMVBLDIR=$(readlink -m $1)
	if [[ ! -d $RMVBLDIR ]]; then echo $ERRORMESSAGENonexistentRmvbl; exit 4; fi
	if [[ ! -r $RMVBLDIR ]]; then echo $ERRORMESSAGEUnreadableRmvbl ; exit 5; fi
	if [[ ! -w $RMVBLDIR ]]; then echo $ERRORMESSAGEUnwritableRmvbl ; exit 6; fi
	echo "syncing with [removable drive] directory $RMVBLDIR"
	# name of log file
	readonly LOGFILE="$RMVBLDIR/syncLog"
	
	# check the locations-list file is ready
	if [[ -z "$CUSTOMLOCATIONSFILE" ]]
	then
		readonly LOCSLIST="$RMVBLDIR/syncLocationsOn_$HOSTNAME" 
	else
		readonly LOCSLIST="$(readlink -m $CUSTOMLOCATIONSFILE)"
	fi
	if [[ ! -e $LOCSLIST ]]; then createLocsListTemplateDialog; fi
	if [[ ! -r $LOCSLIST ]]; then echo $ERRORMESSAGEUnreadableLocsList; exit 7; fi
	echo "reading locations from locations-list file $LOCSLIST"
	# optionally append a new entry to LOCSLIST
	if [[ ! -z "$ADDEDLOCATION" ]]
	then
		if [[ ! -w $LOCSLIST ]]; then echo $ERRORMESSAGEUnwritableLocsList; exit 8; fi
		addLocation "$ADDEDLOCATION"
	fi
	# if we are in list mode then list the contents of LOCSLIST and exit
	if [[ $LISTMODE == "on" ]]
	then
		listLocsListContents # prints/explains contents of LOCSLIST and exits
	fi
	scanLocsList # exits if there are issues with contents of $LOCSLIST
	noOfEntriesInLocsList=$(cleanCommentsAndWhitespace $LOCSLIST \
	   | grep -v '^\s*$' \
	   | wc -l \
	)
	if [[ $noOfEntriesInLocsList -eq 0 ]]; then
		echo "the locations-list file is empty. You can:"
		echo " - add a single file/folder to it with the -s option (see help)"
		echo " - or edit the file directly at: $LOCSLIST"
		exit 0
	fi
	getVerbose && echo found $noOfEntriesInLocsList entries in locations-list file
	
	# check the status file is ready
	readonly SYNCSTATUSFILE="$RMVBLDIR/syncStatus"
	if [[ ! -e $SYNCSTATUSFILE ]]; then noSyncStatusFileDialog; fi # noSyncStatusFileDialog will create a syncStatusFile or exit
	if [[ ! -r $SYNCSTATUSFILE || ! -w $SYNCSTATUSFILE ]]; then echo $ERRORMESSAGEPermissionsSyncStatusFile; exit 10; fi
	
	getVerbose && echo leaving $NOOFBACKUPSTOKEEP 'backup(s) when writing'
	
	# begin iterating over the locations listed in LOCSLIST
	# |while...   : ... stores line contents thus: (first thing on a line) > itemHostLoc [delimeter='|'] (the rest of the line) > itemAlias
	cleanCommentsAndWhitespace $LOCSLIST \
	   | while IFS='|' read itemHostLocRaw itemAlias 
	do
		# because I am PIPING into the loop, this is in a subshell, all variables are LOCAL TO THE LOOP
		# that means all variables declared in the loop are declared locally to the loop
		# and also that CHANGES that occur in this loop to variables declared outside, are also local to the loop
		# nothing that happens in this loop can affect anything in the rest of the script!
		# it's just for file I/O and user I/O
		
		# ------ Step 1: get the item's name and locations ------
		
		local itemHostLoc=$(readlink -m "$itemHostLocRaw")
		if [[ -z "$itemAlias" ]]; then local itemName=$(basename "$itemHostLoc"); else local itemName="$itemAlias"; fi
		local itemRmvblLoc=$RMVBLDIR/"$itemName"
		echo ---$itemName-$LINEOFDASHES
		
		echo syncing $itemHostLoc with $itemRmvblLoc
		
		# ------ Step 2: retrieve data about this item from SYNCSTATUSFILE ------
		
		# does a sync time for this item-this host exist in SYNCSTATUSFILE?
		local itemDateLine=$(grep "^$itemName $HOSTNAME LASTSYNCDATE .*" $SYNCSTATUSFILE)
		grep "^$itemName $HOSTNAME LASTSYNCDATE .*" $SYNCSTATUSFILE >/dev/null
		local itemSyncedPreviously=$?
		
		# if given, what is the sync time?
		if [[ $itemSyncedPreviously -eq true ]]
		then
			# extract the sync time from the file using a regular expression
			itemSyncTime=$(sed "s/$itemName $HOSTNAME LASTSYNCDATE \([[:digit:]][[:digit:]]*\)/\1/" <<<"$itemDateLine") #date string format is seconds since epoch 
		fi
		
		if [[ $itemSyncedPreviously -eq true ]]
		then
			getVerbose && echo status file: synced previously on = $(date --date=@$itemSyncTime +%c)
		else
			getVerbose && echo status file: first-time sync
		fi
		
		# is this host shown as up to date with this item?
		grep "^$itemName UPTODATEHOSTS.* $HOSTNAME,.*$" $SYNCSTATUSFILE >/dev/null
		local hostUpToDateWithItem=$?
		if [[ $hostUpToDateWithItem -eq true ]]
		then
			getVerbose && echo status file: this host has latest changes
		else
			getVerbose && echo status file: this host does not have latest changes
		fi
		
		# an example of an invalid state for the status 
		if [[ ($hostUpToDateWithItem -eq true) && ($itemSyncedPreviously -ne true) ]]
		then
			echo "$itemName: $WARNINGStatusInconsistent"
			echoToLog "$itemName, $WARNINGStatusInconsistent"
			# then offer to erase the log
			eraseItemFromStatusFileDialog "$itemName" # does or does not erase
			# then skip - it's best to take it from the top again after a big change like that
			echo "$itemName: Skipping synchronisation"
			continue
		fi
		
		# ------ Step 3: retrieve data from this item from disk ------
		
		# check existence
		[[ -e "$itemHostLoc" ]]; local itemHostExists=$?
		[[ -e "$itemRmvblLoc" ]]; local itemRmvblExists=$?
		
		# ------ Step 4: logic ------
		
		# --------------------------------if neither removable drive nor host exist--------------------------------
		if [[ $itemHostExists -ne true && $itemRmvblExists -ne true ]]
		then 
			if [[ $itemSyncedPreviously -eq true || $hostUpToDateWithItem -eq true ]]
			then 
				# BRANCH END
				echo "$itemName: $WARNINGSyncStatusForNonexistentItems"
				echoToLog "$itemName, $WARNINGSyncStatusForNonexistentItems"
				eraseItemFromStatusFileDialog "$itemName"
			else 
				# BRANCH END
				echo "$itemName: $WARNINGNonexistentItems"
				echoToLog "$itemName, $WARNINGNonexistentItems"
				echo "$itemName: skipping "
			fi
			continue
		fi
		
		# --------------------------------if host exists, but removable drive doesn't--------------------------------
		if [[ $itemHostExists -eq true && $itemRmvblExists -ne true ]]
		then
			if [[ $itemSyncedPreviously -ne true ]]
			then 
				# BRANCH END
				# then sync Host onto the Rmvbl
				synchronise "$itemName" $SYNCDIRECTIONHOSTTORMVBL "$itemHostLoc" "$itemRmvblLoc"
			else 
				# BRANCH END
				# then we have an error, offer override
				echo "$itemName: $WARNINGSyncedButRmvblAbsent"
				echoToLog "$itemName, $WARNINGSyncedButRmvblAbsent"
				unexpectedAbsenceDialog "$itemName" "$itemHostLoc" "$itemRmvblLoc" "removable"
			fi
			continue
		fi
		
		# --------------------------------if removable drive exists, but host doesn't--------------------------------
		if [[ $itemHostExists -ne true && $itemRmvblExists -eq true ]]
		then
			if [[ $itemSyncedPreviously -ne true ]]
			then 
				# BRANCH END
				# then sync Rmvbl onto Host 
				synchronise "$itemName" $SYNCDIRECTIONRMVBLTOHOST "$itemHostLoc" "$itemRmvblLoc"
			else 
				# BRANCH END
				# then we have an error, offer override
				echo "$itemName: $WARNINGSyncedButHostAbsent"
				echoToLog "$itemName, $WARNINGSyncedButHostAbsent"
				unexpectedAbsenceDialog "$itemName" "$itemHostLoc" "$itemRmvblLoc" "host"
			fi
			continue
		fi
		
		# --------------------------------if both removable drive and host exist--------------------------------
		if [[ $itemHostExists -eq true && $itemRmvblExists -eq true ]]
		then
			# check for mismatched items
			if [[ ((-d "$itemHostLoc") && (! -d "$itemRmvblLoc")) || ((! -d "$itemHostLoc") && (-d "$itemRmvblLoc")) ]]
			then 
				echo "$itemName: $WARNINGMismatchedItems"
				echoToLog "$itemName, $WARNINGMismatchedItems"
				# offer override??
				echo "$itemName: skipping"
				continue
			fi
			
			# ----- logic based on comparisons of modification times -----

			itemRmvblModTime=$(modTimeOf "$itemRmvblLoc")
			itemHostModTime=$(modTimeOf "$itemHostLoc")
			getVerbose && echo from disk: mod time of version on host: $(date --date=@$itemHostModTime +%c)
			getVerbose && echo from disk: mod time of version on removable drive: $(date --date=@$itemRmvblModTime +%c)
			
			if [[ $itemSyncedPreviously -ne true ]]
			then
				# then the status in file is in contradiction with the state on disk
				# offer override to erase the status and proceed
				echo "$itemName: $WARNINGUnexpectedSyncStatusAbsence"
				echoToLog "$itemName, $WARNINGUnexpectedSyncStatusAbsence"
				eraseItemFromStatusFileDialog "$itemName" # hmmm... the user may not see the advantage of erasing an "unexpectedly absent" status...
				chooseVersionDialog "$itemName" "$itemHostLoc" $itemHostModTime "$itemRmvblLoc" $itemRmvblModTime 0 # never synced before so pass a zero for sync time
				continue
			fi
			# so below here assume $itemSyncedPreviously is true
			
			if [[ $itemRmvblModTime -gt $itemSyncTime && $itemSyncTime -gt $itemHostModTime ]]
			then
				if [[ $hostUpToDateWithItem -eq true ]]
				then
					# BRANCH END
					# then item has been modified directly on the removable drive (instead of on a host)
					echo "$itemName: Note: Apparently the removable drive has been modified directly (instead of recieving a change from a host) (host mod older than sync time older than removable drive mod but local host listed as up-to-date)"
					echoToLog "$itemName, removable drive version was modified directly - change appeared not from a host"
					# but that's fine, proceed.
					# sync removable drive onto host
					synchronise "$itemName" $SYNCDIRECTIONRMVBLTOHOST "$itemHostLoc" "$itemRmvblLoc"
				else
					# BRANCH END
					# then have history: modded here > synced to removable drive > removable drive accepted change from elsewhere (possibly directly instead of from a host)
					getVerbose && echo "removable drive has been modified since last sync (and host hasn't)"
					# so update this host with that change
					# sync removable drive onto host
					synchronise "$itemName" $SYNCDIRECTIONRMVBLTOHOST "$itemHostLoc" "$itemRmvblLoc"
				fi
				continue
			fi
			if [[ $itemHostModTime -gt $itemSyncTime && $itemSyncTime -gt $itemRmvblModTime ]]
			then
				if [[ $hostUpToDateWithItem -eq true ]]
				then
					# BRANCH END
					# then have history: removable drive synced with host > removable drive hasn't been updated since that sync > host has been updated since that sync
					getVerbose && echo "host has been modified since last sync (and removable drive hasn't)"
					# so update the removable drive with the changes made on this host
					# sync host to removable drive
					synchronise "$itemName" $SYNCDIRECTIONHOSTTORMVBL "$itemHostLoc" "$itemRmvblLoc"
				else
					# BRANCH END
					# item has been forked
					echo "$itemName: $WARNINGFork"
					echoToLog "$itemName, $WARNINGFork"
					echo "$itemName: status file: synced on $(date --date=@$itemSyncTime +%c)"
					# offer override
					chooseVersionDialog "$itemName" "$itemHostLoc" $itemHostModTime "$itemRmvblLoc" $itemRmvblModTime $itemSyncTime
				fi
				continue
			fi
			if [[ $itemRmvblModTime -gt $itemSyncTime && $itemHostModTime -gt $itemSyncTime ]]
			then
				# BRANCH END
				# item has been forked
				echo "$itemName: $WARNINGFork"
				echoToLog "$itemName, $WARNINGFork"
				echo "$itemName: status file: synced on $(date --date=@$itemSyncTime +%c)"
				# offer override
				chooseVersionDialog "$itemName" "$itemHostLoc" $itemHostModTime "$itemRmvblLoc" $itemRmvblModTime $itemSyncTime
				continue
			fi
			if [[ $itemSyncTime -gt $itemRmvblModTime && $itemSyncTime -gt $itemHostModTime ]]
			then
				if [[ $hostUpToDateWithItem -eq true ]]
				then
					# BRANCH END
					# then have history: host and removable drive were synced > no changes > now they are being synced again
					# i.e. no changes since last sync
					# no action needed - except perhaps displaying a message
					# use diff to confirm both versions are actually the same
					echo "$itemName: $MESSAGEAlreadyInSync"
					echo "$itemName: Confirming versions are identical - this may take a few seconds..."
					local notTheSame=""
					if [[ -d "$itemRmvblLoc" ]]
					then
						notTheSame=$(diff --brief --recursive "$itemHostLoc" "$itemRmvblLoc") # this can be a bit slow on large directories....
					else
						notTheSame=$(diff "$itemHostLoc" "$itemRmvblLoc")
					fi
					if [[ ! -z $notTheSame ]]
					then
						echo $WARNINGUnexpectedDifference
						echoToLog "$itemName, $WARNINGUnexpectedDifference"
						chooseVersionDialog "$itemName" "$itemHostLoc" $itemHostModTime "$itemRmvblLoc" $itemRmvblModTime $itemSyncTime
						continue
					fi
					echo "$itemName: skipping"
				else
					# BRANCH END
					# status in file contradicts the state on disk
					# (because it shows that we synced with this host AFTER last mod, 
					#                      so how come this host isn't on the up-to-date list?)
					echo "$itemName: $WARNINGUnexpectedlyNotOnUpToDateList"
					echoToLog "$itemName, $WARNINGUnexpectedlyNotOnUpToDateList"
					echo "$itemName: status file: synced on $(date --date=@$itemSyncTime +%c)"
					# offer override
					chooseVersionDialog "$itemName" "$itemHostLoc" $itemHostModTime "$itemRmvblLoc" $itemRmvblModTime $itemSyncTime
				fi
				continue
			fi
			# BRANCH END
			# if [[ we reach this line ]]; then 
			#	sync time must be simulataneous with local mod time and/or removable drive mod time (within 1s)
			# 	(so can't sensibly decide what to do)
			echo "$itemName: $WARNINGAmbiguousTimings"
			echoToLog "$itemName, $WARNINGAmbiguousTimings"
			echo "$itemName: status file: synced on $(date --date=@$itemSyncTime +%c)"
			# offer override
			chooseVersionDialog "$itemName" "$itemHostLoc" $itemHostModTime "$itemRmvblLoc" $itemRmvblModTime $itemSyncTime
			
			continue
		fi # end of the "if all exist" block
		
		# ----------------note that that's all four of the non/existence cases, this area is UNREACHABLE----------------
		
	done # end of while loop over items
	
	# trim log file to a reasonable length
	tail -n 500 "$LOGFILE" > "$LOGFILE.tmp" 2> /dev/null && mv "$LOGFILE.tmp" "$LOGFILE"
	
	getVerbose && echo $LINEOFDASHES
	
	echo end of script
}

main "$@"

