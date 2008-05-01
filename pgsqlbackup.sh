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


# Location of the backup logfile.
logfile="/var/lib/pgsql/backups/logfile.log"
touch $logfile

# Location to place backups.
backup_dir="/var/lib/pgsql/backups"

# Current Date
timeslot=`date +%m-%d-%y`

# Two Days Ago
two_days_ago=`date -d "-2 days" +%m-%d-%y`

databases=`psql -U postgres -q -c "\l" | sed -n 4,/\eof/p | grep -v rows\) | awk {'print $1'} | grep -v template0`

# If files from two days ago exist they will be delete from the file system
# In order to save space

for i in $databases; do
        if [ -e $backup_dir/postgresql-$i-$two_days_ago-database.gz ]; then
             rm $backup_dir/postgresql-$i-$two_days_ago-database.gz
        fi
done

# Backup all databases that are found with psql list command

for i in $databases; do
        timeinfo=`date '+%T %x'`
        if [ ! -e $backup_dir/postgresql-$i-$timeslot-database.gz ]; then
            echo "Backup and Vacuum complete at $timeinfo for time slot $timeslot on database: $i " >> $logfile
            /usr/bin/vacuumdb -z -U postgres $i >/dev/null 2>&1
            /usr/bin/pg_dump -U postgres $i  | gzip > "$backup_dir/postgresql-$i-$timeslot-database.gz"
        fi
done
