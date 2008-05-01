#!/bin/bash

# Info: 
# 
#    This script basically creates dumps of all PostgreSQL databases and 
#    saves the dumps into the "backup_dir" location. The script has also been
#    written to keep two days of dump files. Therefore you will see the dump files
#    from the day-of-backup and the day before.  
#
#    I do also setup a logrotate for the log file created byt the dumps.
#
#    Please also keep an eye ono the dumps created to make sure only a 2 day dump 
#    retantion occurs. the script is not smart enough to capture leap years and all.
#    So you may find more the two days of dumps for a database at some point.
#
#    Please use at your own risk and anyone is welcome to make any changes to it
#
# Todo:
#    Add an email function to send the log out
#
# Ver 0.3


# Location of the backup logfile.
LOGFILE="/var/lib/pgsql/backups/logfile.log"
touch $LOGFILE

# Location to place backups.
BACKUP_DIR="/var/lib/pgsql/backups"

# Month's variables
MONTH=`date +%B`
PREVIOUS_MONTH=`date -d "-1 Month" +%b`

# Current Date
TIMESLOT=`date +%m-%d-%Y`

# Two Days Ago
TWO_DAYS_AGO=`date -d "-2 days" +%m-%d-%Y`

# Command below gets a list of the databases
# and it excludes the template databases
DBNAMES=`psql -U postgres -q -c "\l" | sed -n 4,/\eof/p | grep -v rows\) | awk {'print $1'} | grep -v template0`

# If files from two days ago exist they will be deleted from the file system
for i in $DBNAMES; do
	if [ -e $BACKUP_DIR/$i-$TWO_DAYS_AGO.gz ]; then
	     rm -f $BACKUP_DIR/$i-$TWO_DAYS_AGO.gz
	fi
done

# cleanup any files left from previous month
for d in `ls -al $BACKUP_DIR/*.gz | grep $PREVIOUS_MONTH | awk '{print $9}'`; do
    rm -f $d
done

# Backup Global Objects
  if [ ! -e $BACKUP_DIR/globals-only-$TIMESLOT.gz ]; then
            echo "Backing up Global Objects at `date '+%T %x'` for time slot $TIMESLOT " >> $LOGFILE
            /usr/bin/pg_dumpall -g -U postgres | gzip > "$BACKUP_DIR/globals-only-$TIMESLOT.gz"
  fi

# Backup Schemas Only
  if [ ! -e $BACKUP_DIR/schemas-only-$TIMESLOT.gz ]; then
            echo "Backing up Schemas at `date '+%T %x'` for time slot $TIMESLOT " >> $LOGFILE
            /usr/bin/pg_dumpall -g -U postgres | gzip > "$BACKUP_DIR/schemas-only-$TIMESLOT.gz"
  fi

# Backup all databases found in the DBNAMES variable

for i in $DBNAMES; do
        TIMEINFO=`date '+%T %x'`
        if [ ! -e $BACKUP_DIR/$i-$TIMESLOT.gz ]; then 
            echo "Backup and Vacuum complete at $TIMEINFO for time slot $TIMESLOT on database: $i " >> $LOGFILE
	    /usr/bin/vacuumdb -z -U postgres $i >/dev/null 2>&1
	    /usr/bin/pg_dump -U postgres $i  | gzip > "$BACKUP_DIR/$i-$TIMESLOT.gz"
	fi 
done
