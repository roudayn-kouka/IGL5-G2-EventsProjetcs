#!/bin/sh
case " $* " in
  *sonar-maven-plugin*|*":sonar"*)
    export JAVA_HOME=/opt/java/openjdk
    ;;
  *)
    export JAVA_HOME=/opt/java/build-jdk17
    ;;
esac
exec /usr/share/maven/bin/mvn "$@"
