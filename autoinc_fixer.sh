#!/bin/bash
#####################################################################################
# autoinc_fixer.sh
# rev 0.1.0
# John D. Scott <jscott@johnscott.net>
# 
# PURPOSE: 
#
# IN situations where a database is being transformed.
#
# - if you have taken table definition(s) from another database that might be different
#   and restored on top of it
# - if you have removed recent data from a table
#
# Prior to "starting slave" or "starting normal activity, this script can be used
# to detect differences between auto_increment values and max table values
#
# This script detects auto_increment columns in your database for you.
# This script must be run by a user with sufficient privileges.
#
# USAGE:
# </path/to>/autoinc_fixer.sh -d <database> -u <user> -h <hostname>"
# -R (optional for 'report only' - dont fix auto_increment diffs, just report them)"
#
# Static Variables:
# THRESHOLD: detection threshold.  If auto_increment is above
#            max_value by THRESHOLD, then take action
#
THRESHOLD=10000
#
# NEW_OFFSET: when taking action, we set the new auto_increment to NEW_OFFSET
#             IDs above the table max value
NEW_OFFSET=10
#

# Setting 1 default value:
REPORT_ONLY=0

usage () {
	echo "USAGE:"
	echo "$0 -d <database> -u <user> -h <hostname>"
	echo " -R (optional for 'report only' - dont fix auto_increment diffs, just report them)"
}

while getopts ":d:u:h:R" MYOPT
do
  case $MYOPT in
  d)
	DBSCHEMA=${OPTARG}
	;;
  u)
	DBUSER=${OPTARG}
	;;
  h)
	DBHOST=${OPTARG}
	;;
  R)
	REPORT_ONLY=1
	;;
  *)
	usage
	exit 1
	;;
   esac
done

if [ "$DBSCHEMA" == "" ]; then
  usage
  exit 1
fi

if [ "$DBUSER" == "" ]; then
  DBUSER=`whoami`
  echo "WARN: no -u <user> specified, using $DBUSER"
fi

if [ "$DBHOST" == "" ]; then
  DBHOST="localhost"
  echo "WARN: no -h <hostname> specified, using $DBHOST"
fi

echo -n "enter your database password -> "
stty -echo
read DBPASS
stty echo
echo ""

CAN_CONNECT=`mysql --batch -N -h $DBHOST -u $DBUSER -p${DBPASS} -e "select 1;" 2>> /dev/null`

if [ "${CAN_CONNECT}" == "1" ]; then
	echo "database connection OK"
else
	echo "could not connect to DB.... quitting"
	exit 1;
fi

if [ "$REPORT_ONLY" == "0" ]; then
	echo ""
	echo "Are you sure you didn't mean -R for report only?"
	echo "This action could change your database"
	echo -n "Enter to continue, ctrl-c to exit ->"
	read BLANK
	echo ""
fi

echo "------------------------"
echo "schema,table,column,diff"
echo "------------------------"

for MYROW in `mysql -h ${DBHOST} -u ${DBUSER} -p${DBPASS} --batch -N -e "select concat(t.table_name,',',c.column_name,',',ifnull(t.auto_increment,0)) from information_schema.tables t inner join information_schema.columns c on t.table_schema = c.table_schema and t.table_name = c.table_name and c.extra like '%auto_increment%' where c.table_schema = '${DBSCHEMA}';" 2>> /dev/null`
do
	MYTBL=`echo ${MYROW} | cut -d , -f1`
	MYCOL=`echo ${MYROW} | cut -d , -f2`
	MYAI=`echo ${MYROW} | cut -d , -f3`
	MYMAX=`mysql -h ${DBHOST} -u ${DBUSER} -p${DBPASS} --batch -N ${DBSCHEMA} -e "select ${MYCOL} from ${MYTBL} order by ${MYCOL} desc limit 1;" 2>> /dev/null`
	if [ "${MYMAX}" == "" ]; then
		MYMAX=0
	fi
	MYDIFF=`expr ${MYAI} - ${MYMAX}`
	if [ "$REPORT_ONLY" -eq "1" ]; then
		if [ $MYDIFF -gt $THRESHOLD ]; then
			echo "${DBSCHEMA},${MYTBL},${MYCOL},${MYDIFF}*"
		else
			echo "${DBSCHEMA},${MYTBL},${MYCOL},${MYDIFF}"
		fi
	else
		if [ $MYDIFF -gt $THRESHOLD ]; then
			NEWAI=`expr ${MYMAX} + $NEW_OFFSET`
			mysql -h ${DBHOST} -u ${DBUSER} -p${DBPASS} ${DBSCHEMA} -e "ALTER TABLE ${MYTBL} AUTO_INCREMENT=${NEWAI};" 2>> /dev/null
			if [ $? -eq 0 ]; then
				echo "${DBSCHEMA},${MYTBL},${MYCOL},${MYDIFF} -CHANGED: OLD_AI: ${MYAI},MAX_VAL: ${MYMAX}, NEW_AI: ${NEWAI}"
			else
				echo "${DBSCHEMA},${MYTBL},${MYCOL},${MYDIFF} *FAILED UPDATE OF AI*"
			fi
		else
			echo "${DBSCHEMA},${MYTBL},${MYCOL},${MYDIFF}"
		fi
	fi

done
