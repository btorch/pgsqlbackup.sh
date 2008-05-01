#!/bin/bash
#
# PostgreSQL Backup Script Ver 0.4 (BETA)
# Based from the autopostgresbackup script
# 
#
# TODO:
# Check disk space before Backing up databases
# Decide which pgdump format to use
#
# Visit http://www.zeroaccess.org/postgresql for more info
#
#=====================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#=====================================================================
#
#=====================================================================
# Please Note!!
#=====================================================================
#
# I take no resposibility for any data loss or corruption when using
# this script. This script will not help in the event of a hard drive 
# failure. A copy of the PG dumps should always be kept on some
# type of offline storage. You should copy your backups offline 
# regularly for best protection.
#
#=====================================================================

#==========================================
# PLEASE SET THE VARIABLES BELLOW ACCORDING 
# TO YOUR SYSTEM NEEDS
#==========================================

# Username to access the PostgreSQL 
USERNAME=postgres

# Database server host or socket directory
DBHOST=localhost

# List of DBNAMES for Backup 
# The keyword "all" will backup everything
# e.g : DBNAMES="database1 database2 database3"
DBNAMES="all"

# Backup directory location e.g /backups
BACKUPDIR="/var/lib/pgsql/backups2"

#========================================
# MAIL SETUP
#========================================
# What would you like to be mailed to you?
# - log   : send only log file
# - files : send log file and sql files as attachments (see docs)
# - stdout : will simply output the log to the screen if run manually.
# - quiet : Only send logs if an error occurs to the MAILADDR.
MAILCONTENT="stdout"

# Set the maximum allowed email size in k. (4000 = approx 5MB email [see docs])
MAXATTSIZE="4000"

# Email Address to send mail to? (user@domain.com)
MAILADDR="admin@zeroaccess.org"


#============================================================
# ADVANCED OPTIONS
#=============================================================

# Options to Vacuum before running the backup
# 0 : Do not perform any Vacuum functions
# 1 : Vacuum only (Default)
# 2 : Vacuum and Analyze
# 3 : Do a Full Vacuum and Analyze *Note* This can take a long time.
VACUUM=1

# Include CREATE DATABASE commands in backup?
CREATE_DATABASE=yes

# What pgdump format to use ? (Custom = 0 | plain SQL text = 1)
# PGDUMP_FORMAT=1 (NOT YET IMPLEMENTED)

# Include OIDS in the dump (if you don't what this is say no)
DUMP_OIDS=no

# Choose Compression type. (gzip or default = bzip2)
COMP=bzip2

# Additionally keep a copy of the most recent backup in a seperate directory.
# Keep a one day retention on the drive to avoid tape retrievel ?
LATEST=yes

# Command to run before backups (uncomment to use)
#PREBACKUP="/etc/postgresql-backup-pre"

# Command run after backups (uncomment to use)
#POSTBACKUP="/etc/postgresql-backup-post"


#=====================================================================
# Should not need to be modified from here down!!
#=====================================================================

PATH=/usr/bin:/bin 

DATE=`date +%m-%d-%Y`					# Datestamp e.g 2002-09-21
ODA=`date -d "-1 days" +%m-%d-%Y`			# 1 days ago
TDA=`date -d "-2 days" +%m-%d-%Y`			# 2 days ago
#MONTH=`date +%B`					# Current Month
#PREVIOUS_MONTH=`date -d "-1 Month" +%b`		# Previous Month

LOGFILE=$BACKUPDIR/$DBHOST-`date +%N`.log		# Logfile Name
LOGERR=$BACKUPDIR/ERRORS_$DBHOST-`date +%N`.log		# Logfile Name
BACKUPFILES=""


##########################################
# Check existance of required directories 
# and create them if needed
##########################################

if [ ! -e "$BACKUPDIR" ]	
	then
	mkdir -p "$BACKUPDIR"
fi

if [ "$LATEST" = "yes" ]
then
	if [ ! -e "$BACKUPDIR/last" ]	
	then
		mkdir -p "$BACKUPDIR/last"
	fi
fi

###################################
# IO redirection for logging.
####################################
touch $LOGFILE
exec 6>&1           # Link file descriptor #6 with stdout.
                    # Saves stdout.
exec > $LOGFILE     # stdout replaced with file $LOGFILE.
touch $LOGERR
exec 7>&2           # Link file descriptor #7 with stderr.
                    # Saves stderr.
exec 2> $LOGERR     # stderr replaced with file $LOGERR.



##########################################
# Setting up some of the possible flags
##########################################

if [ "$VACUUM" = "2" ]; then
VACUUM_OPT="--analyze"
elif [ "$VACUUM" = "3" ]; then
VACUUM_OPT="--analyze --full"
fi

if [ "$CREATE_DATABASE" = "yes" ]; then
OPT="$OPT --create"
fi

if [ "$DUMP_OIDS" = "yes" ]; then
OPT="$OPT --oids"
fi

# Hostname for LOG information
if [ "$DBHOST" = "localhost" ]; then
        HOST=`hostname`
else
        HOST=$DBHOST
fi

####################################
# Functions
####################################

# Database data dump function
#
dbdump () {
if [ "$VACUUM" != "0" ]; then
vacuumdb --user=$USERNAME --host=$DBHOST --quiet $VACUUM_OPT $1
fi
pg_dump --user=$USERNAME --host=$DBHOST $OPT $1 > $2
return 0
}

# Database dump globals function
#
dbdumpglobals () {
  if [ -e $BACKUPDIR/global-objects.$ODA ]; then
      cp -fp $BACKUPDIR/global-objects.$ODA  $BACKUPDIR/last/global-objects.$ODA
      rm -f $BACKUPDIR/global-objects.$ODA
      if [ -e $BACKUPDIR/last/global-objects.$TDA ]; then
         rm -f $BACKUPDIR/last/global-objects.$TDA
      fi
  fi

pg_dumpall --user=$USERNAME --host=$DBHOST -g > $1

return 0
}

# Compression function 
#
SUFFIX=""
compression () {
if [ "$COMP" = "gzip" ]; then
	gzip -f "$1"
	echo
	echo Backup Information for "$1"
	gzip -l "$1.gz"
	SUFFIX=".gz"
elif [ "$COMP" = "bzip2" ]; then
	echo Compression information for "$1.bz2"
	bzip2 -f -v $1 2>&1
	SUFFIX=".bz2"
else
	echo "No compression option set, check advanced settings"
fi
return 0
}

####################################
# Run command before we begin
####################################
if [ "$PREBACKUP" ]
	then
	echo ======================================================================
	echo "Prebackup command output."
	echo
	eval $PREBACKUP
	echo
	echo ======================================================================
	echo
fi



####################################
# Start of backup dumps
####################################

echo ======================================================================
echo pgsqlbackup.sh VER 0.4
echo http://www.zeroaccess.org/postgresql
echo 
echo Backup of Database Server - $HOST
echo ======================================================================


if [ "$DBNAMES" != "all" ]; then
echo Backup Start Time `date`
echo ======================================================================

	echo Dumping Global Objects First
	dbdumpglobals "$BACKUPDIR/global-objects.$DATE"

	for DB in $DBNAMES
	do
	# Prepare $DB for using
	DB="`echo $DB | sed 's/%/ /g'`"
	
	echo Daily Backup of Database \( $DB \)
	echo Rotating last Backup...
        
 	if [ $COMP = bzip2 ]; then 
        	if [ -e $BACKUPDIR/$DB-$ODA.sql.bz2 ]; then
		   cp -fp $BACKUPDIR/$DB-$ODA.sql.bz2  $BACKUPDIR/last/$DB-$ODA.sql.bz2
             	   rm -f $BACKUPDIR/$DB-$ODA.sql.bz2
			if [ -e $BACKUPDIR/last/$DB-$TDA.sql.bz2 ]; then
         		   rm -f $BACKUPDIR/last/$DB-$TDA.sql.bz2
        		fi
 		fi
        else
	        if [ -e $BACKUPDIR/$DB-$ODA.sql.gz ]; then
                   cp -fp $BACKUPDIR/$DB-$ODA.sql.gz  $BACKUPDIR/last/$DB-$ODA.sql.gz
                   rm -f $BACKUPDIR/$DB-$ODA.sql.gz
			if [ -e $BACKUPDIR/last/$DB-$TDA.sql.gz ]; then
          	   	   rm -f $BACKUPDIR/last/$DB-$TDA.sql.gz
        		fi
                fi
	fi

	echo
		dbdump "$DB" "$BACKUPDIR/$DB-$DATE.sql"
		compression "$BACKUPDIR/$DB-$DATE.sql"
		BACKUPFILES="$BACKUPFILES $BACKUPDIR/$DB-$DATE.sql$SUFFIX"
	echo ----------------------------------------------------------------------
	
	done
echo Backup End `date`
echo ======================================================================


else 
echo Backup Start `date`
echo ======================================================================

        echo Dumping Global Objects First
        dbdumpglobals "$BACKUPDIR/global-objects.$DATE"

	echo Daily Backup of All Databases
	echo

        DBLIST=`psql --user=$USERNAME --host=$DBHOST -q -c "\l" | sed -n 4,/\eof/p | grep -v rows\) | awk {'print $1'} | grep -v template0`

	for DB in $DBLIST
	do

        echo Backup of Database \( $DB \)
        echo Rotating last Backup...

        if [ $COMP = bzip2 ]; then
                if [ -e $BACKUPDIR/$DB-$ODA.sql.bz2 ]; then
                   cp -fp $BACKUPDIR/$DB-$ODA.sql.bz2  $BACKUPDIR/last/$DB-$ODA.sql.bz2
                   rm -f $BACKUPDIR/$DB-$ODA.sql.bz2
                        if [ -e $BACKUPDIR/last/$DB-$TDA.sql.bz2 ]; then
                           rm -f $BACKUPDIR/last/$DB-$TDA.sql.bz2
                        fi
                fi
        else
                if [ -e $BACKUPDIR/$DB-$ODA.sql.gz ]; then
                   cp -fp $BACKUPDIR/$DB-$ODA.sql.gz  $BACKUPDIR/last/$DB-$ODA.sql.gz
                   rm -f $BACKUPDIR/$DB-$ODA.sql.gz
                        if [ -e $BACKUPDIR/last/$DB-$TDA.sql.gz ]; then
                           rm -f $BACKUPDIR/last/$DB-$TDA.sql.gz
                        fi
                fi
        fi

        echo
                dbdump "$DB" "$BACKUPDIR/$DB-$DATE.sql"
                compression "$BACKUPDIR/$DB-$DATE.sql"
                BACKUPFILES="$BACKUPFILES $BACKUPDIR/$DB-$DATE.sql$SUFFIX"
	echo ----------------------------------------------------------------------

        done
echo Backup End Time `date`
echo ======================================================================

fi

####################################
# Finish of dumps
####################################

echo Total disk space used for backup storage..
echo Size - Location
echo `du -hs "$BACKUPDIR"`
echo
echo ======================================================================

####################################
# Run command when we're done
####################################
if [ "$POSTBACKUP" ]
	then
	echo ======================================================================
	echo "Postbackup command output."
	echo
	eval $POSTBACKUP
	echo
	echo ======================================================================
fi

####################################
#Clean up IO redirection
####################################
exec 1>&6 6>&-      # Restore stdout and close file descriptor #6.
exec 1>&7 7>&-      # Restore stdout and close file descriptor #7.



####################################
# Mail section if enabled
####################################

if [ "$MAILCONTENT" = "files" ]
then
	if [ -s "$LOGERR" ]
	then
		# Include error log if is larger than zero.
		BACKUPFILES="$BACKUPFILES $LOGERR"
		ERRORNOTE="WARNING: Error Reported - "
	fi
	#Get backup size
	ATTSIZE=`du -c $BACKUPFILES | grep "[[:digit:][:space:]]total$" |sed s/\s*total//`
	if [ $MAXATTSIZE -ge $ATTSIZE ]
	then
		#enable multiple attachments
		BACKUPFILES=`echo "$BACKUPFILES" | sed -e "s# # -a #g"`	
		#send via mutt
		mutt -s "$ERRORNOTE PostgreSQL Backup Log and SQL Files for $HOST - $DATE" $BACKUPFILES $MAILADDR < $LOGFILE	
	else
		cat "$LOGFILE" | mail -s "WARNING! - PostgreSQL Backup exceeds set maximum attachment size on $HOST - $DATE" $MAILADDR
	fi

elif [ "$MAILCONTENT" = "log" ]
then
	cat "$LOGFILE" | mail -s "PostgreSQL Backup Log for $HOST - $DATE" $MAILADDR
	if [ -s "$LOGERR" ]
		then
			cat "$LOGERR" | mail -s "ERRORS REPORTED: PostgreSQL Backup error Log for $HOST - $DATE" $MAILADDR
	fi
	
elif [ "$MAILCONTENT" = "quiet" ]
then
	if [ -s "$LOGERR" ]
		then
			cat "$LOGERR" | mail -s "ERRORS REPORTED: PostgreSQL Backup error Log for $HOST - $DATE" $MAILADDR
			cat "$LOGFILE" | mail -s "PostgreSQL Backup Log for $HOST - $DATE" $MAILADDR
	fi
else
	if [ -s "$LOGERR" ]
		then
			cat "$LOGFILE"
			echo
			echo "###### WARNING ######"
			echo "Errors reported during AutoPostgreSQLBackup execution.. Backup failed"
			echo "Error log below.."
			cat "$LOGERR"
	else
		cat "$LOGFILE"
	fi	
fi

if [ -s "$LOGERR" ]
	then
		STATUS=1
	else
		STATUS=0
fi

# Clean up Logfile
eval rm -f "$LOGFILE"
eval rm -f "$LOGERR"

exit $STATUS
