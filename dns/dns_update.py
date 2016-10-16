#!/usr/bin/env python
#
# Copyright 2016 Johan Lyheden
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ---------------------------------------------------------------------------
#
# The script depends on config.json to be in the pwd
#
# Example config:
#
# {
#   "zone": "example.com",
#   "record": "host.example.com",
#   "u": "https://api.cloudflare.com/client/v4",
#   "headers": {
#       "X-Auth-Key": "your-cloudflare-api-key",
#       "X-Auth-Email": "your-cloudflare-email",
#       "Content-Type": "application/json"
#   }
# }
#

from requests import get, post, put
import json
import os
import hashlib
import subprocess


def cached_file_name():
    return os.path.join('/tmp', hashlib.md5(CF_CFG["record"]).hexdigest())


def is_ip_same(ip_address):
    try:
        return open(cached_file_name(), 'r').read().rstrip() == ip_address
    except:
        return False


def write_to_cache(ip_address):
    open(cached_file_name(), 'w').write(ip_address)


def my_ip_v4():
    p = subprocess.Popen(['dig', '+short', 'myip.opendns.com', '@resolver1.opendns.com'], stdout=subprocess.PIPE,
                         shell=False)
    o = p.communicate()
    if p.returncode != 0:
        response = get('https://api.ipify.org')
        if response.ok:
            return response.text
        else:
            raise Exception("Failed to lookup IP")
    else:
        return o[0].rstrip()


def get_zone(name):
    response = get("%s/zones?name=%s" % (CF_CFG['u'], name), headers=CF_CFG['headers']).text
    return json.loads(response)["result"][0]


def get_record(zone_id, record_name):
    response = get("%s/zones/%s/dns_records?type=A&name=%s" % (CF_CFG['u'], zone_id, record_name),
                   headers=CF_CFG['headers']).text
    return json.loads(response)["result"]


def create_record(zone_id, record_name, ip_address):
    payload = {
        "type": "A",
        "name": record_name,
        "content": ip_address,
        "ttl": 120
    }
    response = post("%s/zones/%s/dns_records" % (CF_CFG['u'], zone_id), headers=CF_CFG['headers'],
                    data=json.dumps(payload))
    if not response.ok:
        raise Exception("Failed to create dns record")
    print response.status_code
    print response.text


def update_record(zone_id, record_id, record_name, ip_address):
    payload = {
        "id": record_id,
        "type": "A",
        "name": record_name,
        "content": ip_address,
        "ttl": 120
    }
    response = put("%s/zones/%s/dns_records/%s" % (CF_CFG['u'], zone_id, record_id), headers=CF_CFG['headers'],
                   data=json.dumps(payload))
    if not response.ok:
        raise Exception("Failed to update dns record")
    print response.status_code
    print response.text


def run():

    # lookup my public ip
    ip_address = my_ip_v4()

    # verify ip with cache file if it is still the same as last time to avoid hitting the cloudflare api
    if is_ip_same(ip_address):
        print "IP for %s is still the same" % CF_CFG['record']
    else:
        zone = get_zone(CF_CFG["zone"])
        record = get_record(zone["id"], CF_CFG["record"])
        if len(record) == 0:
            print "Record doesnt exist, creating it"
            create_record(zone["id"], CF_CFG["record"], ip_address)
        else:
            if record[0]["content"] != ip_address:
                print "Record doesnt exist but %s match doesnt match %s, updating it" % (record[0]["content"],
                                                                                         ip_address)
                update_record(zone["id"], record[0]["id"], CF_CFG["record"], ip_address)
            else:
                print "Nothing needs to be done"
        write_to_cache(ip_address)
    print "Finished"


if __name__ == '__main__':
    CF_CFG = json.loads(open('config.json', 'r').read())
    run()

