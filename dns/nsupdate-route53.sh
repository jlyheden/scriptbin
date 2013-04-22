#!/bin/sh

# This script will perform a DynDNS-like function for Amazon's Route 53
#
# Original Author: Johan Lindh <johan@linkdata.se>
# http://www.linkdata.se/
#
# Modified by: Johan Lyheden <johan@lyheden.com>
#
# Script requirements:
#
#  wget
#  grep
#  sed
#  dig
#  cut
#  openssl
#  base64
#
# Most if not all of these come standard on *nix distros.
#
# This script should be installed as a dhclient-exit-hook
# On Ubuntu this means: /etc/dhcp3/dhclient-exit-hooks.d
# Make sure to chmod so that only root can read and execute
#

# Only run on BOUND operation
if [ "$reason" != "BOUND" ]; then
  exit 0
fi

# The domain and host name to update
# and the desired TTL of the record
Domain=SET_THIS
Hostname=$(hostname)
PublicDnsName="${Hostname}.${Domain}"
NewTTL=600
RecordType=A

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

# Retrieve the current IP (dhclient hook)
CurrentIP=$new_ip_address

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
  CurrentDate=$(wget -q -S https://route53.amazonaws.com/date -O /dev/null 2>&1 | grep Date | sed 's/.*Date: //')

  # Calculate the SHA1 hash and required headers
  Signature=$(echo -n $CurrentDate | openssl dgst -binary -sha1 -hmac $SecretKey | base64)
  DateHeader="Date: "$CurrentDate
  AuthHeader="X-Amzn-Authorization: AWS3-HTTPS AWSAccessKeyId=$AmazonID,Algorithm=HmacSHA1,Signature=$Signature"

  # Submit request
  Result=$(wget -nv --header="$DateHeader" --header="$AuthHeader" --header="Content-Type: text/xml; charset=UTF-8" --post-data="$Changeset" -O /dev/stdout -o /dev/stdout https://route53.amazonaws.com/2010-10-01/hostedzone/$ZoneID/rrset)
  if [ "$?" -ne "0" ]; then
    echo "Failed to update $Hostname.$Domain: "$Result
  fi
fi
