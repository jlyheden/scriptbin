#!/usr/bin/env python2.7
#
# Copyright 2018 Johan Lyheden
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

import smtplib
import os
import sys
import io
import yaml
import logging

from email.utils import formatdate
from email.mime.text import MIMEText
from jinja2 import Template

logging.basicConfig()
LOGGER = logging.getLogger(__name__)


class FileNotFoundException(Exception):

    def __init__(self, message, default_config):
        super(FileNotFoundException, self).__init__(message)
        self.default_config = default_config


class MailerConfiguration(object):

    def __init__(self, path):
        if not os.path.exists(path):
            raise FileNotFoundException("File not found: {}".format(path), default_config=self.default_config_as_str())
        with io.open(path, 'r', encoding='utf-8') as f:
            yml_config = yaml.load(f.read())
        self.smtp_server = yml_config['server']['host']
        self.smtp_server_port = yml_config['server']['port']
        self.smtp_auth = yml_config['server']['auth']
        self.smtp_ssl = yml_config['server']['ssl']
        self.smtp_start_tls = yml_config['server']['start_tls']
        self.smtp_timeout = yml_config['server']['timeout']
        if self.smtp_auth:
            self.smtp_username = yml_config['server']['username']
            self.smtp_password = yml_config['server']['password']
        self.message_template = yml_config['message']['message_template']
        self.message_subject_template = yml_config['message']['subject_template']
        self.message_from_address = yml_config['message']['from']
        self.message_to_address = yml_config['message']['to']

    @staticmethod
    def default_config_as_str():
        return """
Example standard configuration structure

---
server:
    host: localhost
    port: 587
    username: smtp-user
    password: smtp-password
    auth: true
    start_tls: true
    ssl: false
    timeout: 30

message:
    subject_template: 'Hi from {{ os.getenv("USER") }}'
    from: John <john@doe.com>
    to: Jane <jane@doe.com>
    message_template: |
        Hi Jane!
        
        Thanks for all the fish!
        
        Best regards
        {{ os.getenv("USER") }}
"""


def main(config_file_path):
    # read the config
    try:
        mailer_config = MailerConfiguration(config_file_path)
    except FileNotFoundException as e:
        LOGGER.exception("Config file doesn't exist")
        LOGGER.warning("""Here's an example configuration

{}
""".format(e.default_config))
        sys.exit(1)

    # format the message
    message_template = Template(mailer_config.message_template)
    subject_template = Template(mailer_config.message_subject_template)
    msg = MIMEText(message_template.render(os=os).encode('utf-8'))
    msg['Subject'] = subject_template.render(os=os).encode('utf-8')
    msg['From'] = mailer_config.message_from_address
    msg['To'] = mailer_config.message_to_address
    msg['Date'] = formatdate(localtime=True)

    # setup the mailer and ship it
    if mailer_config.smtp_ssl:
        mailer = smtplib.SMTP_SSL(mailer_config.smtp_server, mailer_config.smtp_server_port,
                                  timeout=mailer_config.smtp_timeout)
    else:
        mailer = smtplib.SMTP(mailer_config.smtp_server, mailer_config.smtp_server_port,
                              timeout=mailer_config.smtp_timeout)
    if mailer_config.smtp_start_tls:
        mailer.starttls()
    if mailer_config.smtp_auth:
        mailer.login(mailer_config.smtp_username, mailer_config.smtp_password)
    mailer.sendmail(msg['From'], [msg['To']], msg.as_string())
    mailer.quit()


if __name__ == '__main__':
    main(sys.argv[1])
