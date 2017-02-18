#!/usr/bin/env bash
#
# nord-chan
# version 1.0
#
# / we'll be fine... i hope... /
#
# set -x

# list mount points (e.g. "u01=u02 u02=u03")
MOUNT=""

# usage
USAGE="\n\tNewname Or Rename Database - generate 'set newname' or 'alter database rename' for a database.\n\n \
\tnord.sh [-hnrs] -o <SOURCE_SID> [-t <TARGET_SID>]\n\n \
\t-h - print this message\n \
\t-n - generate file containing 'set newname' commands (rman)\n \
\t-o - source database name\n \
\t-r - generate file containing 'alter database rename' commands (sqlplus)\n \
\t-s - get database structure (no files are generated)\n \
\t-t - target database name (optional)\n\n \
\tNotes:\n\n \
\t- file(s) will be generated alongside this script.\n\n \
\tExample:\n\n \
\t- generate 'set newname' file for database orcl:\n\n \
\t  nord.sh -n -s orcl\n"

# options
while getopts 'hnrso:t:' opt
do
  case $opt in
  h) echo -e "${USAGE}"
     exit 0
     ;;
  n) SNN=1
     ;;
  r) ADR=1
     ;;
  s) STR=1
     ;;
  o) OLDSID=${OPTARG}
     ;;
  t) NEWSID=${OPTARG}
     ;;
  :) echo "option -$opt requires an argument"
     ;;
  *) echo -e "${USAGE}"
     exit 1
     ;;
  esac
done
shift $(($OPTIND - 1))

# os dependent
case $(uname) in
  "SunOS") ORATAB=/var/opt/oracle/oratab
           ;;
  "Linux") ORATAB=/etc/oratab
           ;;
  "AIX")   ORATAB=/etc/oratab
           ;;
  "HP-UX") ORATAB=/etc/oratab
           ;;
  *)       printf "Unknown OS.\n" && exit 13
           ;;
esac

# error handling
function errck () {
  printf "\n\n*** $(date +%Y.%m.%d\ %H:%M:%S)\n${ERRMSG} Stop.\n"
  exit 1
}

# check
if [[ -z ${OLDSID} ]]; then
  printf "<SOURCE_SID> is mandatory. Use -h.\n"
  exit 1
fi
if [[ ! ${STR} ]]; then
  if [[ ! ${SNN} ]] && [[ ! ${ADR} ]]; then
    printf "At least one option (-n or -r) must be specified. Exiting.\n"
    exit 1
  fi
fi

# check if zero
function check () {
  if [[ $? != 0 ]]; then
    printf "\n\n*** $(date +%Y.%m.%d\ %H:%M:%S)\n${ERRMSG} Stop.\n"
    exit 1
  fi
}

# set oracle environment
function setora () {
  ERRMSG="SID ${1} not found in ${ORATAB}."
  if [[ $(cat ${ORATAB} | grep "^$1:") ]]; then
    unset ORACLE_SID ORACLE_HOME ORACLE_BASE
    export ORACLE_BASE=/u01/app/oracle
    export ORACLE_SID=${1}
    export ORACLE_HOME=$(cat ${ORATAB} | grep "^${ORACLE_SID}:" | cut -d: -f2)
    export PATH=${ORACLE_HOME}/bin:${PATH}
  else
    errck
  fi
}

# set newname
function mnewname () {
  if [[ ${MOUNT} ]]; then
    PREFROM="/${1}"
    PRETO="/${2}"
    PFWHERE="where name like '/${1}%%'"
    PLWHERE="member like '/${1}%%' and"
  fi
  printf "
  set head off verify off trimspool on feed off line 2000 pagesize 100 newpage none
  set numformat 9999999999999999999
  set pages 0
  col names word_wrapped
  select 'set newname for datafile '
         ||file#||' to '''
         ||replace(name,'${PREFROM}/oradata/${OLDSID}','${PRETO}/oradata/${NEWSID}')||''';'
         names from v\$datafile ${PFWHERE};
  select 'set newname for tempfile '
         ||file#||' to '''
         ||replace(name,'${PREFROM}/oradata/${OLDSID}','${PRETO}/oradata/${NEWSID}')||''';'
         names from v\$tempfile ${PFWHERE};
  select 'sql \"alter database rename file '''''
         ||member||''''' to '''''
         ||replace(member,'${PREFROM}/oradata/${OLDSID}','${PRETO}/oradata/${NEWSID}')||''''' \";'
         from v\$logfile where ${PLWHERE} type = 'ONLINE' order by member;
  exit
  " | sqlplus -s / as sysdba
}

# rename
function mrename () {
  if [[ ${MOUNT} ]]; then
    PREFROM="/${1}"
    PRETO="/${2}"
    PFWHERE="where name like '/${1}%%'"
    PLWHERE="member like '/${1}%%' and"
  fi
  printf "
  set head off verify off trimspool on feed off line 2000 pagesize 100 newpage none
  set numformat 9999999999999999999
  set pages 0
  col names word_wrapped
  select 'alter database rename file '''
         ||name||''' to '''
         ||replace(name,'${PREFROM}/oradata/${OLDSID}','${PRETO}/oradata/${NEWSID}')||''';'
         names from v\$datafile ${PFWHERE};
  select 'alter database rename file '''
         ||name||''' to '''
         ||replace(name,'${PREFROM}/oradata/${OLDSID}','${PRETO}/oradata/${NEWSID}')||''';'
         names from v\$tempfile ${PFWHERE};
  select 'alter database rename file '''
         ||member||''' to '''
         ||replace(member,'${PREFROM}/oradata/${OLDSID}','${PRETO}/oradata/${NEWSID}')||''';'
         from v\$logfile where ${PLWHERE} type = 'ONLINE' order by member;
  exit
  " | sqlplus -s / as sysdba
}

# structure
function getstr () {
  printf "
  set head off verify off trimspool on feed off line 2000 pagesize 100 newpage none
  set numformat 9999999999999999999
  set pages 0
  col names word_wrapped
  select distinct substr(name,2,3) from v\$datafile;
  select distinct substr(name,2,3) from v\$tempfile;
  select distinct substr(member,2,3) from v\$logfile;
  exit
  " | sqlplus -s / as sysdba | sort -n | uniq
}

# how many
howmany () { echo $#; }

# main
setora $OLDSID
if [[ ${STR} ]]; then
  MP=$(getstr | xargs)
  echo "Database ${OLDSID} has these mount points: $MP."
  exit 1
fi
if [[ ${MOUNT} ]]; then
  MP=$(getstr)
  NOMP=$(howmany ${MP})
  NOSMP=$(tr -dc '=' <<< ${MOUNT} | awk '{print length;}')
  if [[ $NOMP != $NOSMP ]]; then
    ERRMSG="Number of distinct mount points does not match up. Database has ${NOMP}, you supplied ${NOSMP}. Check MOUNT variable."
    errck
  fi
fi
if [[ ! ${NEWSID} ]]; then
  NEWSID=$OLDSID
fi
STATUS=$(printf "
  set head off verify off trimspool on feed off line 2000 pagesize 100 newpage none
  set numformat 9999999999999999999
  set pages 0
  select status from v\$instance;
  exit
  " | sqlplus -s / as sysdba | grep .)
check
if [[ ${STATUS} == "STARTED" ]]; then
  ERRMSG="Database ${OLDSID} should be at minimum in MOUNTED state. Current status: STARTED."
  errck
else
  if [[ ${MOUNT} ]]; then
    while IFS=' ' read -ra U; do
      for i in "${U[@]}"; do
        if [[ ! ${i} =~ "=" ]]; then
          ERRMSG="Wrong mount points mapping format. Should be: MOUNT_POINT=MOUNT_POINT."
          errck
        fi
      done
    done <<< "$MOUNT"
    if [[ ${SNN} ]]; then
      if [[ -f setnewname.sql ]]; then
        ERRMSG="Cannot remove old setnewname.sql file."
        rm setnewname.sql
        check
      fi
      while IFS=' ' read -ra U; do
        for i in "${U[@]}"; do
          OLDU="$(echo $i | cut -d= -f1)"
          NEWU="$(echo $i | cut -d= -f2)"
          ERRMSG="Could not create setnewname.sql file. Maybe access is denied?"
          printf "$(mnewname $OLDU $NEWU)" >> setnewname.sql
          check
          echo "" >> setnewname.sql
        done
      done <<< "$MOUNT"
      printf "Generated setnewname.sql file for mounts: $MOUNT.\n"
    fi
    if [[ ${ADR} ]]; then
      if [[ -f rename.sql ]]; then
        ERRMSG="Cannot remove old rename.sql file."
        rm rename.sql
        check
      fi
      while IFS=' ' read -ra U; do
        for i in "${U[@]}"; do
          OLDU="$(echo $i | cut -d= -f1)"
          NEWU="$(echo $i | cut -d= -f2)"
          ERRMSG="Could not create rename.sql file. Maybe access is denied?"
          printf "$(mrename $OLDU $NEWU)" >> rename.sql
          check
          echo "" >> rename.sql
        done
      done <<< "$MOUNT"
      printf "Generated rename.sql file for mounts: $MOUNT.\n"
    fi
  else
    if [[ ${SNN} ]]; then
      if [[ -f setnewname.sql ]]; then
        ERRMSG="Cannot remove old setnewname.sql file."
        rm setnewname.sql
        check
      fi
      ERRMSG="Could not create setnewname.sql file. Maybe access is denied?"
      printf "$(mnewname)" >> setnewname.sql
      check
      echo "" >> setnewname.sql
      printf "Generated a new setnewname.sql file.\n"
    fi
    if [[ ${ADR} ]]; then
      if [[ -f rename.sql ]]; then
        ERRMSG="Cannot remove old rename.sql file."
        rm rename.sql
        check
      fi
      ERRMSG="Could not create rename.sql file. Maybe access is denied?"
      printf "$(mrename)" >> rename.sql
      check
      echo "" >> rename.sql
      printf "Generated a new rename.sql file.\n"
    fi
  fi
fi

# exit
exit 0
