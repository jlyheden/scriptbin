#!/bin/bash
#
# Dovecot compress maildir script
#

if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/maildir"
  exit 0
fi

tocompress=`find $1 -iname '*,S=' -exec file -b "{}" | grep -qs ^gzip \;`

exit 0

for mail in $tocompress; do
        echo "gzipping $1/cur/$mail to $1/tmp/${mail}Z"
        gzip -S Z "$1/cur/$mail" -c > "$1/tmp/${mail}Z"
        echo "setting mtime"
        touch -r "$1/cur/$mail" "$1/tmp/${mail}Z"
done

echo "aquiring maildirlock"
if PID=`/usr/lib/dovecot/maildirlock $1/cur 20`; then
        #locking successfull, moving compressed files
        for mail in $tocompress; do
                mv $1/tmp/${mail}Z $1/cur/
                rm $1/cur/${mail}
        done
        kill $PID
else
        echo "lock failed"
        exit -1
fi
