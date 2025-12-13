#!/bin/sh
set -e

# Fix nginx bigbluebutton config before nginx starts
if [ -f /etc/nginx/bigbluebutton ]; then
  echo "Fixing bigbluebutton nginx config..."
  sed -i 's/listen 10\.7\.7\.1:8185;/listen 0.0.0.0:8185;/g' /etc/nginx/bigbluebutton
  sed -i 's/listen 127\.0\.0\.1:8185;/listen 0.0.0.0:8185;/g' /etc/nginx/bigbluebutton
  echo "Fixed bigbluebutton config"
fi

# Execute original entrypoint
exec "$@"

