#!/bin/bash
# Usage: 
#   security_group_rule.sh <add|del> <in|out> <rule_list(csv)> [dryrun]
#     add/del: Specify "add" to add rules or "del" to delete rules.
#     in/out: Inboud or Outbound
#     rule_list.csv: The path to the CSV file containing the list of rules to add or delete.
#     dryrun: Not required.
# Description:
#  This script can add or delete rules for existing security groups using the AWS CLI.
#  The CSV file should include the security group ID for the target security group.
#    <group-id>,<protocol>,<from-port>,<to-port>,<CIDR/SGID>,<DESCRIPTION>
#

LOG_DIR=$(cd $(dirname ${0}); pwd)/log
LOGFILE=${LOG_DIR}/aws-sg_rule_`date '+%Y%m%d-%H%M%S'`.log

AWSCLI_CMD='aws ec2'
USAGE="$0 <add|del|addshow|delshow> <in|out> <listfile(csv)> [dryrun]"

ACTION=$1
DIRECTION=$2
RULE_LIST=$3
DRYRUN_FLG=$4

# Argument Count Check
if [ $# -ne 3 -a $# -ne 4 ]; then
    echo -e "Error: Invalid number of arguments"
    echo -e "Usage: ${USAGE}"
    exit 1
fi

if [[ "${DRYRUN_FLG}" == "dryrun" ]]; then
    CMD_SUFFIX='--dry-run'
elif [[ -n "${DRYRUN_FLG}" ]]; then
    echo -e "Error: Invalid argument: ${DRYRUN_FLG}"
    echo -e "Usage: ${USAGE}"
    exit 1
fi

# Existence of list file check
if [ ! -f "$RULE_LIST" ]; then
    echo "$3 does not exist."
    exit 1
fi

# Set subcommand for inbaund/outband rule 
case "${DIRECTION}" in
    in)
        SUBCOM_TMP="ingress" ;;
    out)
        SUBCOM_TMP="egress" ;;
    *)
        echo -e "Error: Invalid argument: ${DIRECTION}"
        echo -e "Usage: ${USAGE}"
        exit 1 ;;
esac

# Set subcommand for delet/add rule
case ${ACTION} in
    add|addshow ) SUBCMD="authorize-security-group-${SUBCOM_TMP}" ;;
    del|delshow ) SUBCMD="revoke-security-group-${SUBCOM_TMP}" ;;
    *)
      echo -e "Error: Invalid argument: ${ACTION}"
      echo -e "Usage: ${USAGE}"
      exit 10
      ;;
esac

# Check logfile directory and make
test ! -d ${LOG_DIR} && mkdir ${LOG_DIR}

# function: AWS-CLI commnd create
function func_create_cmd() {
    SECURITY_GROUP_ID=$1
    PROTOCOL=$2
    FROM_PORT=$3
    TO_PORT=$4
    CIDER_SGID=$5
    DESCRIPTION=$6
    
    # Set subcommand parameter: Source/destination
    if [[ ${CIDER_SGID} =~ .*sg-* ]]; then
        SUBCMD_PRM1='UserIdGroupPairs'
        SUBCMD_PRM2='GroupId'
    elif [[ ${CIDER_SGID} =~ .*[1-9]*\.[0-9]*\.[0-9]*\.[0-9]*[0-9] ]]; then
        SUBCMD_PRM1='IpRanges'
        SUBCMD_PRM2='CidrIp'
    fi
    
    # Set subcommand parameter: Description
    if [[ ${DESCRIPTION} == "" ]]; then
        SUBCMD_PRM3=''
    else
        SUBCMD_PRM3=",Description="${DESCRIPTION}""
    fi
    
    # '-1' for protocol means all traffic, no need to specify port
    if [[ ${PROTOCOL} =~ .*-1 ]]; then
        SUBCOMD_TMP="${SUBCMD} --group-id ${SECURITY_GROUP_ID} --ip-permissions IpProtocol=${PROTOCOL},${SUBCMD_PRM1}='[{${SUBCMD_PRM2}=${CIDER_SGID}"${SUBCMD_PRM3}"}]'"
    else
        SUBCOMD_TMP="${SUBCMD} --group-id ${SECURITY_GROUP_ID} --ip-permissions IpProtocol=${PROTOCOL},FromPort=${FROM_PORT},ToPort=${TO_PORT},${SUBCMD_PRM1}='[{${SUBCMD_PRM2}=${CIDER_SGID}"${SUBCMD_PRM3}"}]'"
    fi
    
    # Assembling commands
    CMD="${AWSCLI_CMD} ${SUBCOMD_TMP} ${CMD_SUFFIX}"
}

# Main
# Read and process rules from list file
while IFS=',' read -r SECURITY_GROUP_ID PROTOCOL FROM_PORT TO_PORT CIDR DESCRIPTION
do
    case "${ACTION}" in
        "add" )
          func_create_cmd "${SECURITY_GROUP_ID}" "${PROTOCOL}" "${FROM_PORT}" "${TO_PORT}" "${CIDER_SGID}" "${DESCRIPTION}"
          echo -e "Add command: ${CMD}" 2>&1 | tee -a ${LOGFILE}
          eval ${CMD} 2>&1 | tee -a ${LOGFILE}
          ;;
        "del" )
          func_create_cmd "${SECURITY_GROUP_ID}" "${PROTOCOL}" "${FROM_PORT}" "${TO_PORT}" "${CIDER_SGID}"
          echo -e "Delete command: ${CMD}" 2>&1 | tee -a ${LOGFILE}
          eval ${CMD} 2>&1 | tee -a ${LOGFILE}
          ;;
        "addshow" )
          func_create_cmd "${SECURITY_GROUP_ID}" "${PROTOCOL}" "${FROM_PORT}" "${TO_PORT}" "${CIDER_SGID}" "${DESCRIPTION}"
          echo -e "${CMD}" 2>&1 | tee -a ${LOGFILE}
          ;;
        "delshow" )
          func_create_cmd "${SECURITY_GROUP_ID}" "${PROTOCOL}" "${FROM_PORT}" "${TO_PORT}" "${CIDER_SGID}"
          echo -e "${CMD}" 2>&1 | tee -a ${LOGFILE}
          ;;
        * )
          echo -e "Error: Invalid argument: ${ACTION}"
          echo -e "Usage: ${USAGE}"
          exit 20
          ;;
    esac
done < <(awk -F',' '{ if($1~"^[^#]") print $0}' "$3" | tr -d '\r')
exit 0