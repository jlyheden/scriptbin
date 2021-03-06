#!/bin/bash
#
# Dovecot compress maildir script
#
# Kind of based on recommendations from
# http://wiki2.dovecot.org/Plugins/Zlib
#
# Script supports nested maildirs and does
# not care about file naming (Z in the file name)
# which is useful in cases where you enable
# compression in the LDA before compressing
# existing messages
#
# Caveats
# * script will lock the maildir for each file it compresses
# * probably not particulary efficient
#

if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/maildir [--dry-run]"
  exit 0
fi

if [ "$2" == "--dry-run" ]; then
  echo "Running in dry-run mode, will only scan for files to compress and list them"
fi

tmp_dir="/tmp/maildir_compress/$1"

c_logger() {
  echo "$(date): $1" >> $tmp_dir/compress.log
}

# Create tmp dir
if [ -d "$tmp_dir" ]; then
  echo "Temp dir $tmp_dir exists, rm -rf it"
  rm -rf "$tmp_dir"
fi
echo "Creating temp dir $tmp_dir"
mkdir -p "$tmp_dir"
chmod 0700 "$tmp_dir"

echo "Scanning $1 for non-gzipped files"
tocompress=$(find $1 -name "*,S=*" -printf "head -c 2 '%p' | file -b - |grep -qs ^gzip || echo '%p'\n" | sh)

# Iterate on newline, not whitespace
IFS='
'

# Dry run
if [ "$2" == "--dry-run" ]; then
  if [ -z "$tocompress" ]; then
    echo "No files found to be compressed"
  else
    echo "Files to be compressed:"
    for mail_file_path in $tocompress; do
      echo "$mail_file_path"
    done
  fi
  exit 0
fi

for mail_file_path in $tocompress; do

  # Get file name of mail
  mail_file_name=$(basename "$mail_file_path")
  tmp_file_path="$tmp_dir/$mail_file_name"
  maildir_path_1=$(dirname "$mail_file_path")
  maildir_path=$(dirname "$maildir_path_1")
  
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
    c_logger "lock command: /usr/lib/dovecot/maildirlock \"$maildir_path\" 20"
    if LOCK=$(/usr/lib/dovecot/maildirlock "$maildir_path" 20); then
      mv "$tmp_file_path" "$mail_file_path"
      kill -TERM $LOCK
    else
      c_logger "Failed to lock $maildir_path"
      rm -f "$tmp_file_path"
    fi
  else
    c_logger "File: $mail_file_path doesnt exist anymore"
  fi

done

c_logger "Done"
