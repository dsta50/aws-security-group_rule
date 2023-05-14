#!/bin/bash
# Usage: 
#   aws-security_group_rule.sh <add|del> <in|out> <rule_list(csv)> [-y]
#     add/del:        Specify "add" to add rules or "del" to delete rules.
#     in/out:         Inboud or Outbound
#     rule_list(csv): The path to the CSV file containing the list of rules to add or delete.
#     -y:             Actually run with AWS CLI
# Description:
#  This script can add or delete rules for existing security groups using the AWS CLI.
#  The CSV file should include the security group ID for the target security group.
#    <group-id>,<protocol>,<from-port>,<to-port>,<Destination|Source(CIDR/SGID)>,<DESCRIPTION>
#

LOG_DIR=$(cd $(dirname ${0}); pwd)/log
LOGFILE=${LOG_DIR}/$(basename $0)_$(date '+%Y%m%d').log

AWSCLI_CMD='aws ec2'
USAGE="$0 <add|del> <in|out> <listfile(csv)> [-y]"

# Argument
ACTION=$1
DIRECTION=$2
RULE_LIST=$3
EX_OPTIN=$4

# Argument Count Check
if [ $# -ne 3 -a $# -ne 4 ]; then
    echo -e "Error: Invalid number of arguments"
    echo -e "Usage: ${USAGE}"
    exit 1
fi

# Existence of list file check
if [ ! -f "${RULE_LIST}" ]; then
    echo "${RULE_LIST} does not exist."
    exit 1
fi

# Set subcommand for inbaund/outband rule 
case "${DIRECTION}" in
    in )
        SUBCOM_TMP="ingress"
        ;;
    out )
        SUBCOM_TMP="egress"
        ;;
    * )
        echo -e "Error: Invalid argument: ${DIRECTION}"
        echo -e "Usage: ${USAGE}"
        exit 2
        ;;
esac

# Set subcommand for delet/add rule
case ${ACTION} in
    add )
        SUBCMD="authorize-security-group-${SUBCOM_TMP}"
        ;;
    del )
        SUBCMD="revoke-security-group-${SUBCOM_TMP}"
        ;;
    * )
        echo -e "Error: Invalid argument: ${ACTION}"
        echo -e "Usage: ${USAGE}"
        exit 2
        ;;
esac

# Check logfile directory and make
test ! -d ${LOG_DIR} && mkdir ${LOG_DIR}
echo -e "" >> ${LOGFILE}
echo -e "# Running scripts. $(uname -n)@$(whoami) Time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a ${LOGFILE}

# function: AWS-CLI commnd create
function func_create_cmd() {
    SG_ID=$1
    PROTOCOL=$2
    FROM_PORT=$3
    TO_PORT=$4
    DEST_SRC=$5
    DESCRIPTION=$6
    
    # Set subcommand parameter: Source/destination
    if [[ ${DEST_SRC} =~ sg-[[:alnum:]]+ ]]; then
        # SG-ID
        SUBCMD_PRM1='UserIdGroupPairs'
        SUBCMD_PRM2='GroupId'
    elif [[ ${DEST_SRC} =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+ ]]; then
        # IPv4 CIDER
        SUBCMD_PRM1='IpRanges'
        SUBCMD_PRM2='CidrIp'
    elif [[ ${DEST_SRC} =~ [0-9a-fA-F:]+/[0-9]+ ]]; then
        # IPv6 CIDER
        SUBCMD_PRM1='Ipv6Ranges'
        SUBCMD_PRM2='CidrIpv6'
    fi
    
    # Set subcommand parameter: Description
    if [[ ${DESCRIPTION} == "" ]]; then
        SUBCMD_PRM3=''
    else
        SUBCMD_PRM3=",Description="${DESCRIPTION}""
    fi
    
    # '-1' for protocol means all traffic, no need to specify port
    if [[ ${PROTOCOL} =~ -1 ]]; then
        SUBCOMD_TMP="${SUBCMD} --group-id ${SG_ID} --ip-permissions IpProtocol=${PROTOCOL},${SUBCMD_PRM1}='[{${SUBCMD_PRM2}=${DEST_SRC}"${SUBCMD_PRM3}"}]'"
    else
        SUBCOMD_TMP="${SUBCMD} --group-id ${SG_ID} --ip-permissions IpProtocol=${PROTOCOL},FromPort=${FROM_PORT},ToPort=${TO_PORT},${SUBCMD_PRM1}='[{${SUBCMD_PRM2}=${DEST_SRC}"${SUBCMD_PRM3}"}]'"
    fi
    
    # Assembling commands
    CMD="${AWSCLI_CMD} ${SUBCOMD_TMP}"
    
    return 0
}

# Main
# Read and process rules from list file
while IFS=',' read -r SG_ID PROTOCOL FROM_PORT TO_PORT DEST_SRC DESCRIPTION TEMP
do
    # Remove "(Double quotation) from field
    SG_ID=$(echo "${SG_ID}" | sed 's/"//g')
    PROTOCOL=$(echo "${PROTOCOL}" | sed 's/"//g')
    FROM_PORT=$(echo "${FROM_PORT}" | sed 's/"//g')
    TO_PORT=$(echo "${TO_PORT}" | sed 's/"//g')
    DEST_SRC=$(echo "${DEST_SRC}" | sed 's/"//g')

    # Check field sg-id
    if [[ ! ${SG_ID} =~ sg-[[:alnum:]]+ ]]; then
        echo "Skip: "${SG_ID}", "${PROTOCOL}", "${FROM_PORT}", "${TO_PORT}", "${DEST_SRC}""
        continue
    fi
    
    if [[ ${DESCRIPTION} =~ \# ]]; then
        DESCRIPTION=''
    fi

    case "${EX_OPTIN}" in
        "-y" )
            if [[ ${ACTION} == "add" ]]; then
                func_create_cmd "${SG_ID}" "${PROTOCOL}" "${FROM_PORT}" "${TO_PORT}" "${DEST_SRC}" "${DESCRIPTION}"
                echo -e "Add command: ${CMD}" 2>&1 | tee -a ${LOGFILE}
            elif [[ ${ACTION} == "del" ]]; then
                func_create_cmd "${SG_ID}" "${PROTOCOL}" "${FROM_PORT}" "${TO_PORT}" "${DEST_SRC}"
                echo -e "Delete command: ${CMD}" 2>&1 | tee -a ${LOGFILE}
            fi
            eval ${CMD} 2>&1 | tee ${LOGFILE}.tmp
            # Remove prefix when running debug mode
            grep -v '^++' ${LOGFILE}.tmp >> ${LOGFILE}
            rm -f ${LOGFILE}.tmp
            ;;
        * )
            if [[ ${ACTION} == "add" ]]; then
                func_create_cmd "${SG_ID}" "${PROTOCOL}" "${FROM_PORT}" "${TO_PORT}" "${DEST_SRC}" "${DESCRIPTION}"
            elif [[ ${ACTION} == "del" ]]; then
                func_create_cmd "${SG_ID}" "${PROTOCOL}" "${FROM_PORT}" "${TO_PORT}" "${DEST_SRC}"
            fi
            echo ${CMD} 2>&1 | tee -a ${LOGFILE}
            ;;
    esac
done < <(awk -F',' '{ if($1~"^[^#]") print $0}' "${RULE_LIST}" | tr -d '\r')
exit 0
