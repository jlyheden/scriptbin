#!/bin/sh

# This script will perform a DynDNS-like function for Amazon's Route 53
# Tailored to be used as a hook for dhcpc-event as described in
# https://github.com/RMerl/asuswrt-merlin/wiki/User-scripts
#
# Original Author: Johan Lindh <johan@linkdata.se>
# http://www.linkdata.se/
#
# Modified by: Johan Lyheden <johan@lyheden.com>
#
# Script requirements:
#
#  curl
#  grep
#  sed
#  dig
#  cut
#  awk
#  openssl
#  base64
#
# This script should be installed into the file path:
# /jffs/scripts/dhcpc-event
#
# Ipkg dependencies:
# * bind
# * coreutils
#

# Only run on BOUND operation
if [ "$1" != "bound" ]; then
  exit 0
fi

# The domain and host name to update
# and the desired TTL of the record
Domain=SET_YOUR_DOMAIN
Hostname=SET_YOUR_HOSTNAME
PublicDnsName="${Hostname}.${Domain}"
NewTTL=600
RecordType=A
CurrentIP=$(nvram get wan_ipaddr)

# The Amazon Route 53 zone ID for the domain
# and the Amazon ID and SecretKey. Remember to
# ensure that this file can't be read by
# unauthorized people!
ZoneID=SET_THIS
AmazonID=SET_THIS
SecretKey=SET_THIS

###############################################################
# You should not need to change anything beyond this point
###############################################################

# Find an authoritative AWS R53 nameserver so we get a clean TTL
AuthServer=$(dig NS $Domain | grep -v ';' | grep -m 1 awsdns | grep $Domain | awk -F ' ' '{ print $5 }')
if [ "$AuthServer" = "" ]; then
  echo The domain $Domain has no authoritative Amazon Route 53 name servers
  exit 1
fi

# Get the record and extract its parts
Record=$(dig @$AuthServer $RecordType $Hostname.$Domain | grep -v ";" | grep "$Hostname\.$Domain")
OldType=$( echo $Record | cut -d ' ' -f 4 )
OldTTL=$( echo $Record | cut -d ' ' -f 2 )
OldIP=$( echo $Record | cut -d ' ' -f 5 )

# Make sure it is an A record (could be CNAME)
if [ "$Record" != "" -a "$OldType" != $RecordType ]; then
  echo $Hostname.$Domain has a $OldType record, expected $RecordType
  exit 1
fi

# Changeset preamble
Changeset=""
Changeset=$Changeset"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
Changeset=$Changeset"<ChangeResourceRecordSetsRequest xmlns=\"https://route53.amazonaws.com/doc/2010-10-01/\">"
Changeset=$Changeset"<ChangeBatch><Comment>Update $Hostname.$Domain</Comment><Changes>"

if [ "$OldIP" != "" ]; then
  # Add a DELETE request to the changeset
  Changeset=$Changeset"<Change>"
  Changeset=$Changeset"<Action>DELETE</Action>"
  Changeset=$Changeset"<ResourceRecordSet>"
  Changeset=$Changeset"<Name>$Hostname.$Domain.</Name>"
  Changeset=$Changeset"<Type>$RecordType</Type>"
  Changeset=$Changeset"<TTL>$OldTTL</TTL>"
  Changeset=$Changeset"<ResourceRecords>"
  Changeset=$Changeset"<ResourceRecord>"
  Changeset=$Changeset"<Value>$OldIP</Value>"
  Changeset=$Changeset"</ResourceRecord>"
  Changeset=$Changeset"</ResourceRecords>"
  Changeset=$Changeset"</ResourceRecordSet>"
  Changeset=$Changeset"</Change>"
fi

# Add CREATE request to the changeset
Changeset=$Changeset"<Change>"
Changeset=$Changeset"<Action>CREATE</Action>"
Changeset=$Changeset"<ResourceRecordSet>"
Changeset=$Changeset"<Name>$Hostname.$Domain.</Name>"
Changeset=$Changeset"<Type>$RecordType</Type>"
Changeset=$Changeset"<TTL>$NewTTL</TTL>"
Changeset=$Changeset"<ResourceRecords>"
Changeset=$Changeset"<ResourceRecord>"
Changeset=$Changeset"<Value>$CurrentIP</Value>"
Changeset=$Changeset"</ResourceRecord>"
Changeset=$Changeset"</ResourceRecords>"
Changeset=$Changeset"</ResourceRecordSet>"
Changeset=$Changeset"</Change>"

# Close the changeset
Changeset=$Changeset"</Changes>"
Changeset=$Changeset"</ChangeBatch>"
Changeset=$Changeset"</ChangeResourceRecordSetsRequest>"

if [ "$OldIP" != "$CurrentIP" ]; then
  # Get the date at the Amazon servers
  # curl adds some nasty hidden characters that had to be filtered out
  CurrentDate=$(curl -i -s https://route53.amazonaws.com/date| grep ^Date|sed -e 's/^Date: //'|sed -e 's/[^a-zA-Z0-9\,\: ]//g')

  # Calculate the SHA1 hash and required headers
  Signature=$(echo -n $CurrentDate | openssl dgst -binary -sha1 -hmac $SecretKey | base64)
  AuthHeader="X-Amzn-Authorization: AWS3-HTTPS AWSAccessKeyId=$AmazonID,Algorithm=HmacSHA1,Signature=$Signature"
  DateHeader="Date: ${CurrentDate}"

  # Submit request
  Result=$(curl -XPOST -s -H "$DateHeader" -H "$AuthHeader" -H "Content-Type: text/xml; charset=UTF-8" --data "$Changeset" https://route53.amazonaws.com/2010-10-01/hostedzone/$ZoneID/rrset)
  if [ "$?" -ne "0" ]; then
    echo "Failed to update $Hostname.$Domain: "$Result
  fi
fi
