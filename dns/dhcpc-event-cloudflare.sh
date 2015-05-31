#!/bin/sh
#
# Dhcp client event script updating DNS entry at Cloudflare with the assigned WAN IP
#
# Install this script into /jffs/scripts/dhcpc-event and make it executable
#
# Configuration environment variables (configure in /jffs/scripts/cloudflare.config):
# CF_EMAIL
# CF_API_KEY
# CF_ZONE_NAME
# CF_ZONE_ID - get with curl -X GET "https://api.cloudflare.com/client/v4/zones?name=domain.name
# CF_RECORD_ID - get with curl -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=host_name"
# CF_RECORD_TYPE
# CF_RECORD_NAME
# CF_TTL
#
# CF_ZONE_ID and CF_RECORD_ID could be fetched during run-time but I could not find any way to parse json
# without pulling in heavy dependencies in busybox, so have to pre-configure them
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

# Only run on BOUND operation
if [ "$1" != "bound" ]; then
  exit 0
fi

# Fail if gnu date not installed (required for date %N)
if ! [ -f /opt/bin/date ]; then
  exit 1
fi

# Source external file for config
[ -f /jffs/scripts/cloudflare.config ] && source /jffs/scripts/cloudflare.config

# Get IP
IP_ADDRESS=$(nvram get wan0_ipaddr)

# Check if IP has changed
NS=$(dig ns $CF_ZONE_NAME|grep ^$CF_ZONE_NAME|head -1|awk '{ print $5 }')
OLD_IP=$(dig -t $CF_RECORD_TYPE @$NS $CF_RECORD_NAME|grep ^$CF_RECORD_NAME|awk '{ print $5 }')

if [ "$OLD_IP" = "$IP_ADDRESS" ]; then
  echo "WAN IP $IP_ADDRESS same as DNS entry $OLD_IP type $CF_RECORD_TYPE so quiting.."
  exit 0
fi

# Get Timestamp
NOW=$(/opt/bin/date +'%Y-%m-%dT%T.%5NZ')

# Update record
curl -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID}" -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_API_KEY}" -H "Content-Type: application/json" --data "{\"id\":\"${CF_RECORD_ID}\",\"type\":\"${CF_RECORD_TYPE}\",\"name\":\"${CF_RECORD_NAME}\",\"content\":\"${IP_ADDRESS}\",\"proxiable\":true,\"proxied\":false,\"ttl\":${CF_TTL},\"locked\":false,\"zone_id\":\"${CF_ZONE_ID}\",\"zone_name\":\"${CF_ZONE_NAME}\",\"created_on\":\"${NOW}\",\"modified_on\":\"${NOW}\",\"data\":{}}"
