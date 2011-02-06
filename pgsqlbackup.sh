#!/bin/bash
#
# PostgreSQL Backup Script Ver 1.0.1
# Based from the autopostgresbackup script
# 
#=========================== 
# Author: Marcelo Martins
# Date: 2008-08-07
#
#==========================================
# TODO
#==========================================
# - Check to make sure there are no backup files older then 7 days
#   and if there is remove them 
# - Check that the files have been uploaded to the cloud
# - Add S3 support to the cloud push
# - Look for some more possible error checking
# - Check disk space before Backing up databases
# - Create a mail log format that fits on an iPhone screen 
#
# Visit http://www.zeroaccess.org/postgresql-backup for more info
# or https://github.com/btorch/pgsqlbackup.sh
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
# PLEASE NOTE
#=====================================================================
#
# I take no resposibility for any data loss or corruption when using
# this script. This script will not help in the event of a hard drive 
# failure. A copy of the PG dumps should always be kept on some
# type of offsite storage. You should copy your backups offsite 
# regularly for best protection.
#
#=====================================================================
#
#==========================================
# MAIN CONFIGURATION PARAMETERS BELOW
#==========================================

# Admin superuser for PostgreSQL 
USERNAME="postgres"

# Connection type  
# Can be localhost (TCP/IP)  or socket directory (default)
CONN_TYPE="/tmp"

# List of DBNAMES for Backup 
# The keyword "all" will backup everything
# e.g : DBNAMES="database1 database2 database3"
DBNAMES="all"

# Backup directory location e.g /backups
BACKUPDIR="/var/lib/pgsql/backups"

# Setting PATH variable so that it can find 
# PostgreSQL binaries. 
PATH=/usr/bin:/bin:/usr/local/bin

# Hostname for LOG information
HOST=`hostname -f`


#================
# MAIL SETUP 
#================
# What would you like to be mailed to you?
# - maillogs : send only log file(s)
# - files : send log file and backed up files as attachments 
# - stdout : will simply output the log to the screen if run manually
# - quiet : Only send logs if an error occurs
MAILCONTENT="stdout"

# Set the maximum allowed email size in k. (4000 = approx 5MB email)
MAXATTSIZE="4000"

# Email Address to send mail to? (user@domain.com)
MAILADDR="admin@domain.com"


#==================
# ADVANCED OPTIONS
#==================

# Options to Vacuum before running the backup
# 0 : Do not perform any Vacuum functions (default)
# 1 : Vacuum only 
# 2 : Vacuum and Analyze
# 3 : Do a Full Vacuum and Analyze 
VACUUM=0

# Include CREATE DATABASE commands in backup
CREATE_DATABASE="yes"

# Include OIDS in the dump (if you don't know what this is say no)
DUMP_OIDS="no"

# Choose Compression type. (gzip or default = bzip2)
COMP="bzip2"

# Dump Format Output (custom = Fc , Custom tar = Ft , SQL plain text = Fp)
DUMP_OPT="-Fc"

# Additionally keep a copy of the most recent backup in a seperate directory.
# Keep a one day retention on the drive to avoid tape retrievel 
RETENTION="yes"

# Any other extra options that you might want to pass to pg_dump 
# should go below. Please test it first before making it permmanent.
EXTRA_OPTS=""

# Command to run before backups (uncomment to use)
#PREBACKUP="/etc/postgresql-backup-pre"

# Command run after backups (uncomment to use)
#POSTBACKUP="/etc/postgresql-backup-post"


#====================
# CLOUDFILES SETUP 
#===================
# You MUST DOWNLOAD cloudfiles.sh from https://github.com/btorch/cloudfiles.sh
# and copy it to /usr/local/bin with permissions set to 755 and owned by postgres user 
CF_BACKUP="disabled"                        # enabled or disabled for allowing cloud backup push                                 
CF_UTIL="/usr/local/bin/cloudfiles.sh"      # location of the cloudfiles.sh utility
CF_PUSH="all"                               # set to either "all" or "nologs"
CF_CONTAINER="pgbackups"                    # cloud container to push files 
CF_USER="USERNAME"                          # cloud username
CF_KEY="API KEY"                            # cloud api key
CF_REG="REGION"                             # region where the cloud is located (US or UK)


#=================
# POST Commands
#================

# Command to run before backups (uncomment to use)
#PREBACKUP="/etc/postgresql-backup-pre"

# Command run after backups (uncomment to use)
#POSTBACKUP="/etc/postgresql-backup-post"



#=====================================================================
# DO NOT MODIFY ANYTHING FROM DOWN HERE 
#=====================================================================

DATE=`date +%m-%d-%Y`                       # Datestamp e.g 2002-09-21
ODA=`date -d "-1 days" +%m-%d-%Y`           # 1 day ago
TDA=`date -d "-2 days" +%m-%d-%Y`           # 2 days ago

LOGFILE=$BACKUPDIR/$HOST-$DATE.log              # Backup Logfile Name
LOGERR=$BACKUPDIR/ERRORS_$HOST-$DATE.log        # Backup Error Logfile Name
VDB_LOGFILE=$BACKUPDIR/VDB_$HOST-$DATE.log  	# Vacuum error Logfile Name

BACKUPFILES=""


##########################################
# Check existance of required directories 
# and create them if needed
##########################################

if [ ! -e "$BACKUPDIR" ]; then
    mkdir -p "$BACKUPDIR"
fi

if [ "$RETENTION" = "yes" ]; then
    if [ ! -e "$BACKUPDIR/last" ]; then
        mkdir -p "$BACKUPDIR/last"
    fi
fi


##########################################
# Create log files
##########################################
touch $LOGFILE
touch $LOGERR
touch $VDB_LOGFILE
echo 0>$VDB_LOGFILE


###################################
# IO redirection for logging.
####################################
exec 6>&1           # Link file descriptor #6 with stdout. Saves stdout.
exec > $LOGFILE     # stdout replaced with file $LOGFILE.

exec 7>&2           # Link file descriptor #7 with stderr. Saves stderr
exec 2> $LOGERR     # stderr replaced with file $LOGERR.



##########################################
# Setting up some of the possible flags
##########################################

if [ "$VACUUM" = "1" ]; then
    VACUUM_OPT=""
elif [ "$VACUUM" = "2" ]; then
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

if [ "$DUMP_OPT" = "-Fp" ]; then
    DUMP_SUFFIX="sql"
elif [ "$DUMP_OPT" = "-Fp" ]; then 
    DUMP_SUFFIX="sql.tar"  	
else
    DUMP_SUFFIX="dump"
fi
  



####################################
# Start of Functions
####################################


# CHECK AUTHENTICATION 
    check_auth () {
    CORE=`psql -l --user=$USERNAME --host=$CONN_TYPE &> /dev/null`	
    if [[ $CODE -ne 0 ]]; then 
        echo -e " FATAL:  Ident authentication failed for $USERNAME on connection $CONN_TYPE \n"
        xit 1  	  
    fi
}



# DATABASE VACUUM FUNCTION
dbvacuum () {

    echo =========================
    echo "Performing Vacuum of DB $1"
    echo =========================
    echo Start Time: `date +%m-%d-%Y_%r`

    vacuumdb --user=$USERNAME --host=$CONN_TYPE --quiet $VACUUM_OPT $1 2>> $VDB_LOGFILE

    echo End Time: `date +%m-%d-%Y_%r`

    if [ -s $VDB_LOGFILE ]; then
        echo "Status: warnings/errors detected"
        echo "See file $VDB_LOGFILE"
        echo 
    else
        echo "Status: Vaccum performed successfully "
        echo
    fi

}



# DATABASE DUMP FUNCTION
dbdump () {

    if [ "$VACUUM" != "0" ]; then
        dbvacuum $1
    fi

    echo 
    echo =========================
    echo Creating PGSQL dump file
    echo =========================
    echo Start Time: `date +%m-%d-%Y_%r`
    echo Filename: $2

    pg_dump -f $2 --user=$USERNAME --host=$CONN_TYPE $DUMP_OPT $OPT $EXTRA_OPTS $1 

    echo End Time: `date +%m-%d-%Y_%r`
    echo

}



# DUMP OF GLOBAL OBJECTS 
# Also rotates its own global-objects files
#
dbdumpglobals () {

    if [ "$RETENTION" = "yes" ]; then  
        if [ -e $BACKUPDIR/global-objects.$ODA.sql ]; then
            cp -fp $BACKUPDIR/global-objects.$ODA.sql  $BACKUPDIR/last/global-objects.$ODA.sql
            rm -f $BACKUPDIR/global-objects.$ODA.sql

            if [ -e $BACKUPDIR/last/global-objects.$TDA.sql ]; then
                rm -f $BACKUPDIR/last/global-objects.$TDA.sql
            fi
        fi
    else
        if [ -e $BACKUPDIR/global-objects.$ODA.sql ]; then
            rm -f $BACKUPDIR/global-objects.$ODA.sql
        fi
    fi
            
    pg_dumpall --user=$USERNAME --host=$CONN_TYPE -g > $1

}



# RETRIVAL OF DATABASE LIST 
#
get_dblist () {

    if [ "$DBNAMES" == "all" ]; then
        LIST=`psql --user=$USERNAME --host=$CONN_TYPE -ltx | grep Name | tr -d " " | cut -d "|" -f2 | grep -v template0`
        DBLIST=$LIST
    else
        DBLIST=$DBNAMES
    fi

}



# DATABASE DUMP FILES ROTATION
# deletes  two days old files and place the
# previous day dumps into the folder named last
#
rotate_dumps () {

    if [ "$COMP" = "bzip2" ]; then
        COMP_SUFFIX="bz2"
    else
        COMP_SUFFIX="gz"
    fi

    echo =========================
    echo Rotating Backup dumps ...
    echo =========================

    if [ "$RETENTION" = "yes" ]; then

        if [ -e $BACKUPDIR/$DB-$ODA.$DUMP_SUFFIX.$COMP_SUFFIX ]; then

            echo Moving yesterday $DB backup file into $BACKUPDIR/last folder   
            cp -fp $BACKUPDIR/$DB-$ODA.$DUMP_SUFFIX.$COMP_SUFFIX  $BACKUPDIR/last/$DB-$ODA.$DUMP_SUFFIX.$COMP_SUFFIX
            rm -f $BACKUPDIR/$DB-$ODA.$DUMP_SUFFIX.$COMP_SUFFIX

            if [ -e $BACKUPDIR/last/$DB-$TDA.$DUMP_SUFFIX.$COMP_SUFFIX ]; then
                echo Deleting old $DB backup file from $BACKUPDIR/last folder
                 rm -f $BACKUPDIR/last/$DB-$TDA.$DUMP_SUFFIX.$COMP_SUFFIX
            fi
        fi
    else
        if [ -e $BACKUPDIR/$DB-$ODA.$DUMP_SUFFIX.$COMP_SUFFIX ]; then
            echo Deleting yesterday $DB backup file 
            rm -f $BACKUPDIR/$DB-$ODA.$DUMP_SUFFIX.$COMP_SUFFIX
        fi
    fi

}



# CLOUD BACKUP FUNCTION
cloud_push () {

    if [ "$CF_BACKUP" = "enabled" ]; then 

        echo =========================
        echo "Performing Cloud Push  "
        echo =========================
        echo Start Time: `date +%m-%d-%Y_%r`
        echo

        if [ ! -e "$CF_UTIL" ]; then 
            echo " No $CF_UTIL found. Cloud push has failed "
        else
            
            if [ "$CF_PUSH" = "all" ]; then 
                CF_FILES=`find $BACKUPDIR  -maxdepth 1 -type f`
            elif [ "$CF_PUSH" = "nologs" ]; then 
                CF_FILES=`find $BACKUPDIR  -maxdepth 1 -type f | grep -v "*.log"`    
            fi

            CODE=`$CF_UTIL $CF_REG:$CF_USER $CF_KEY INFO $CF_CONTAINER &>/dev/null; echo $?`
            if [ "$CODE" = "1" ]; then 
                echo "Creating container $CF_CONTAINER "
                RESULT=`$CF_UTIL $CF_REG:$CF_USER $CF_KEY MKDIR /$CF_CONTAINER ; echo $?`

                if [ "$RESULT" = "1" ]; then 
                    echo "Problems creating container .. exiting"
                    exit 1
                fi
            fi

            for filename in $CF_FILES 
            do  
                echo "Pushing file : $filename "
                $CF_UTIL $CF_REG:$CF_USER $CF_KEY PUT $CF_CONTAINER $filename
            done
        
        fi

        echo
        echo =========================
        echo End Time: `date +%m-%d-%Y_%r`
        echo
    fi        
}    


# COMPRESSION FUNCTION 
#
SUFFIX=""
compression () {
    if [ "$COMP" = "gzip" ]; then
        gzip -f "$1"
        echo
        echo Compression information for "$1.gz"
        gzip -l "$1.gz"
        SUFFIX=".gz"
    elif [ "$COMP" = "bzip2" ]; then
        echo Compression information for "$1.bz2"
        bzip2 -f -v $1 2>&1
        SUFFIX=".bz2"
    else
        echo "No compression chosen"
    fi

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

# Does a simple list to vefiry it can auth
check_auth


echo ======================================================================
echo pgsqlbackup.sh VER 1.0.1
echo http://www.zeroaccess.org/postgresql
echo 
echo Backup of Database Server - $HOST
echo ======================================================================
echo
echo ======================================================================
echo Backup Start Time `date`
echo ======================================================================
echo

echo ====================
echo Global Objects Dump 
echo ====================
    
dbdumpglobals "$BACKUPDIR/global-objects.$DATE.sql"

echo Global Objects backed up ...
echo 
echo

get_dblist 

for DB in $DBLIST 
do
	
    echo ==========================================
    echo Daily Backup of Database \( $DB \)
    echo ==========================================
    echo 

    rotate_dumps "$DB" 

    dbdump "$DB" "$BACKUPDIR/$DB-$DATE.$DUMP_SUFFIX"

    echo =========================
    echo Compression Info 
    echo =========================
    echo Start Time: `date +%m-%d-%Y_%r`

    compression "$BACKUPDIR/$DB-$DATE.$DUMP_SUFFIX"

	echo End Time: `date +%m-%d-%Y_%r`

	BACKUPFILES="$BACKUPFILES $BACKUPDIR/$DB-$DATE.$DUMP_SUFFIX$SUFFIX"

	echo 
	echo
	
done

echo
echo ======================================================================
echo Backup End Time `date`
echo ======================================================================
echo


####################################
# Finish of dumps
####################################

echo =========================================
echo Total disk space used for backup storage
echo =========================================
echo Size - Location
echo `du -hs "$BACKUPDIR"`
echo
echo ======================================================================




####################################
# Pushing backups to the cloud
####################################

cloud_push 


####################################
# Run command when we're done
####################################
if [ "$POSTBACKUP" ]; then
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
# Clean up old logs
####################################
rm -f $BACKUPDIR/$HOST-$ODA.log
rm -f $BACKUPDIR/ERRORS_$HOST-$ODA.log
rm -f $BACKUPDIR/VDB_$HOST-$ODA.log


####################################
# Mail section functions
####################################

mail_files () {

    if [ -s "$LOGERR" ]; then
        BACKUPFILES="$BACKUPFILES $LOGERR"
        if [ -s "$VDB_LOGFILE" ]; then
            BACKUPFILES="$BACKUPFILES $VDB_LOGFILE"
            ERRORNOTE="WARNING: Error Reported - "
        else
            ERRORNOTE="WARNING: Error Reported - "
        fi
    fi

    # Calculates the total size of all files to be mailed out as attachment
    ATTSIZE=`du -c $BACKUPFILES | grep "[[:digit:][:space:]]total$" |sed s/\s*total//`

    if [[ $MAXATTSIZE -ge $ATTSIZE ]]; then 
        #enable multiple attachments
        BACKUPFILES=`echo "$BACKUPFILES" | sed -e "s# # -a #g"`

        #send via mutt
        mutt -s "$ERRORNOTE PgSQL Backup Logs and Dumps for $HOST - $DATE" $BACKUPFILES $MAILADDR < $LOGFILE
    else
        cat "$LOGFILE" | mail -s "WARNING! - PgSQL Backup exceeds set maximum attachment size on $HOST - $DATE" $MAILADDR
    fi

    return 0
}


mail_logs () {

    cat "$LOGFILE" | mail -s "PgSQL Backup Log for $HOST - $DATE" $MAILADDR
    if [ -s "$LOGERR" ]; then
        cat "$LOGERR" | mail -s "ERRORS REPORTED: PgSQL Backup error Log for $HOST - $DATE" $MAILADDR
    fi

    if [ -s "$VDB_LOGFILE" ]; then
        cat "$VDB_LOGFILE" | mail -s "VACUUM WARNINGS REPORTED: PgSQL Vacuum  Log for $HOST - $DATE" $MAILADDR
    fi

    return 0
}


mail_quiet () {

    if [ -s "$LOGERR" -a -s "$VDB_LOGFILE" ]; then
        cat "$LOGFILE" | mail -s "PSQL Backup Log for $HOST - $DATE" $MAILADDR
        cat "$LOGERR" | mail -s "ERRORS REPORTED: PgSQL Backup error Log for $HOST - $DATE" $MAILADDR
        cat "$VDB_LOGFILE" | mail -s "VACUUM WARNINGS: PgSQL Backup error Log for $HOST - $DATE" $MAILADDR

    elif [ -s "$LOGERR" -o -s "$VDB_LOGFILE" ]; then
        if [ -s "$LOGERR"  ]; then
            cat "$LOGFILE" | mail -s "PSQL Backup Log for $HOST - $DATE" $MAILADDR
            cat "$LOGERR" | mail -s "ERRORS REPORTED: PgSQL Backup error Log for $HOST - $DATE" $MAILADDR
        fi

        if [ -s "$VDB_LOGFILE" ]; then
            cat "$LOGFILE" | mail -s "PSQL Backup Log for $HOST - $DATE" $MAILADDR
            cat "$VDB_LOGFILE" | mail -s "VACUUM WARNINGS: PgSQL Backup error Log for $HOST - $DATE" $MAILADDR
        fi
    fi

    return 0
}



no_mail () {

    if [ -s "$LOGERR" -a -s "$VDB_LOGFILE" ]; then
        cat "$LOGFILE"

        echo
        echo "###### WARNING ######"
        echo "Some errors reported during backup script execution."
        echo "Please check below."
        echo

        cat "$LOGERR"

        echo
        echo "###### VACUUMDB WARNING ######"
        echo "Some errors or warning notices were reported during the vacuumdb execution."
        echo "Most common vacuum NOTICES are in regards to max_fsm_pages & max_fsm_relations."
        echo "Please check below."
        echo

        cat "$VDB_LOGFILE"

    elif [ -s "$LOGERR" -o -s "$VDB_LOGFILE" ]; then
        cat "$LOGFILE"

        if [ -s "$LOGERR" ]; then
            echo
            echo "###### WARNING ######"
            echo "Some errors reported during backup script execution."
            echo "Please check below."
            echo
            cat "$LOGERR"
        fi

        if [ -s "$VDB_LOGFILE" ]; then
            echo
            echo "###### VACUUMDB WARNING ######"
            echo "Some errors or warning notices were reported during the vacuumdb execution."
            echo "Most common vacuum NOTICES are in regards to max_fsm_pages & max_fsm_relations."
            echo "Please check below."
            echo
            cat "$VDB_LOGFILE"
        fi

    else
        cat "$LOGFILE"
    fi

    return 0
}



####################################
# Main Mail section 
####################################

if [ "$MAILCONTENT" = "files" ]; then
    mail_files 
elif [ "$MAILCONTENT" = "maillogs" ]; then
    mail_logs
elif [ "$MAILCONTENT" = "quiet" ]; then
    mail_quiet
else
    no_mail
fi

if [ -s "$LOGERR" ]; then
    STATUS=1
else
    STATUS=0
fi

exit $STATUS



