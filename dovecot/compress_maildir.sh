#!/bin/bash
#
# Dovecot compress maildir script
#

if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/maildir"
  exit 0
fi

tmp_dir="/tmp/maildir_compress/$1"

if [ -d "$tmp_dir" ]; then
  echo "Clearing temp dir: $tmp_dir"
  rm -rf "$tmp_dir"
fi

echo "Creating temp dir: $tmp_dir"
mkdir -p "$tmp_dir"

echo "Scanning $1 for non-gzipped files"
tocompress=$(find $1 -name "*,S=*" -printf "file -b '%p' |grep -qs ^gzip || echo '%p'\n" | sh)

# Iterate on newline, not whitespace
IFS='
'

for mail_file_path in $tocompress; do

  echo "Processing file: $mail_file_path"

  # Get file name of mail
  mail_file_name=$(basename "$mail_file_path")
  tmp_file_path="$tmp_dir/$mail_file_name"
  maildir_path=$(dirname "$(dirname \"$mail_file_name\")")

  # Die if tmp file already exists
  if [ -f "$tmp_file_path" ]; then
    echo "The tmp file $tmp_file_path already exists!"
    exit 1
  fi

  # Gzip to tmp location
  gzip -9 "$mail_file_path" -c > "$tmp_file_path"

  # Preserve attributes
  chown --reference="$mail_file_path" "$tmp_file_path"
  chmod --reference="$mail_file_path" "$tmp_file_path"
  touch --reference="$mail_file_path" "$tmp_file_path"

  # Lock maildir
  #PID=$(/usr/lib/dovecot/maildirlock "$maildir_path" 20)
  echo mv "$tmp_file_path" "$mail_file_path"
  #kill $PID

done
