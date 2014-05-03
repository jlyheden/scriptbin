#!/bin/bash
#
# Dovecot compress maildir script
#

if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/maildir"
  exit 0
fi

tmp_dir="/tmp/maildir_compress/$1"

c_logger() {
  echo "$(date): $1" >> $tmp_dir/compress.log
}

# Create tmp dir
if [ -d "$tmp_dir" ]; then
  rm -rf "$tmp_dir"
fi
mkdir -p "$tmp_dir"
chmod 0700 "$tmp_dir"

c_logger "Scanning $1 for non-gzipped files"
tocompress=$(find $1 -name "*,S=*" -printf "file -b '%p' |grep -qs ^gzip || echo '%p'\n" | sh)

# Iterate on newline, not whitespace
IFS='
'

for mail_file_path in $tocompress; do

  # Get file name of mail
  mail_file_name=$(basename "$mail_file_path")
  tmp_file_path="$tmp_dir/$mail_file_name"
  maildir_path=$(dirname "$(dirname \"$mail_file_path\")")
  
  c_logger "Processing file: $mail_file_path"
  c_logger "mail_file_name: $mail_file_name"
  c_logger "tmp_file_path: $tmp_file_path"
  c_logger "maildir_path: $maildir_path"

  # Die if tmp file already exists
  if [ -f "$tmp_file_path" ]; then
    c_logger "The tmp file $tmp_file_path already exists!"
    exit 1
  fi

  # Gzip to tmp location
  gzip -9 "$mail_file_path" -c > "$tmp_file_path"

  # Preserve attributes
  chown --reference="$mail_file_path" "$tmp_file_path"
  chmod --reference="$mail_file_path" "$tmp_file_path"
  touch --reference="$mail_file_path" "$tmp_file_path"

  # Lock maildir
  if [ -f "$mail_file_path" ]; then
    PID=$(/usr/lib/dovecot/maildirlock "$maildir_path" 20)
    mv "$tmp_file_path" "$mail_file_path"
    kill -TERM $PID
  else
    c_logger "File: $mail_file_path doesnt exist anymore"
  fi

done
