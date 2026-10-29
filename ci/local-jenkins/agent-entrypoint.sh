#!/bin/sh
set -eu
# Make non-interactive SSH build shells use the same build tools as docker exec.
printf '%s\n' \
  'JAVA_HOME=/opt/java/build-jdk17' \
  'MAVEN_HOME=/usr/share/maven' \
  'PATH=/opt/java/build-jdk17/bin:/usr/share/maven/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
  > /etc/environment
exec /usr/local/bin/setup-sshd "$@"
