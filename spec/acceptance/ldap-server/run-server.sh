#!/bin/bash

# This is the script that runs INSIDE the LDAP server container when it first boots up.
# This script should:
#   1) Configure certificates and anything else in the OS
#   2) Load in the schema and data fixtures
#   3) Start the LDAP server process
# Remember: The `spec/acceptance` directory from the repo will be mounted read-only on `/acceptance`
# in this container, so use that to your advantage!

[ -z "$LDAP_DOMAIN_SUFFIX" ] && export LDAP_DOMAIN_SUFFIX="dc=kittens,dc=net"

# Method to wait for LDAP server to become available
wait_for_server() {
  COUNTER=0
  while [ $COUNTER -lt 30 ]; do
    let COUNTER=COUNTER+1
    if /usr/bin/ldapsearch -Y EXTERNAL -H ldapi:/// -b "$LDAP_DOMAIN_SUFFIX" >/dev/null 2>&1; then
      return 0
    fi
    echo "Waiting for openldap to become available... ${COUNTER}/30" 1>&2
    sleep 1
  done
  echo "LDAP server did not become available after 30 seconds. :shrug:" 1>&2
  exit 1
}

# Kill existing data
rm -rf /var/lib/ldap/*
rm -rf /etc/ldap/slapd.d/*

# Pre-install our certificates
rm -f /container/service/slapd/assets/certs/*
cp /acceptance/ca/intermediate/private/ldap-server.fake.key.pem /container/service/slapd/assets/certs/ldap.key
cp /acceptance/ca/intermediate/certs/ldap-server.fake.cert.pem /container/service/slapd/assets/certs/ldap.crt
cp /acceptance/ca/intermediate/certs/ca-chain.cert.pem /container/service/slapd/assets/certs/ca.crt
cp /acceptance/ldap-server/tls/dhparam.pem /container/service/slapd/assets/certs/dhparam.pem
chown -R root:root /container/service/slapd/assets/certs

# Pre-install our configuration environment
rm -f /container/environment/99-default/*.yaml
cp /acceptance/ldap-server/env/*.yaml /container/environment/99-default

# Pre-install our schema (after killing most of the defaults from the container)
rm -f /container/service/slapd/assets/config/bootstrap/ldif/0[345]*.ldif
rm -rf /container/service/slapd/assets/config/bootstrap/schema/mmc
rm -f /etc/ldap/schema/*
cp /acceptance/ldap-server/schema/* /etc/ldap/schema/
cp /acceptance/ldap-server/ldif/bootstrap/*.ldif /container/service/slapd/assets/config/bootstrap/ldif

# Launch openldap
nohup /usr/bin/python -u /container/tool/run -l info &
OPENLDAP_PID=$!

# Wait for the process to be running and connectable
wait_for_server

# Add any schema items that are missing
for file in /etc/ldap/schema/*.ldif; do
  # Loading some of these configs can prompt a server restart. Avoid a race condition
  # by verifying that the server is running before trying to do anything.
  wait_for_server

  SCHEMA=$(basename "$file" | sed -e 's/\.ldif$//')
  if /usr/bin/ldapsearch -Y EXTERNAL -H ldapi:/// -b 'cn=config' 2>/dev/null | grep -q "dn: cn={[0-9]*}${SCHEMA},cn=schema,cn=config"; then
    echo "Schema ${SCHEMA} already loaded"
    echo ""
  else
    echo "Loading schema ${SCHEMA}"
    /usr/bin/ldapadd -Y EXTERNAL -H ldapi:// -f "/etc/ldap/schema/${SCHEMA}.ldif"
  fi
done

# Loading some of the above configs can prompt a server restart. Avoid a race condition
# by verifying that the server is running before trying to do anything.
wait_for_server

# Install our data
cd /acceptance/ldap-server/ldif/data
for dir in *; do
  # Need to skip if there aren't any files in that directory.
  if ls "$dir/"*.ldif >/dev/null 2>&1; then
    :
  else
    continue
  fi

  for ldif in "${dir}"/*.ldif; do
    echo "Starting to import: ${ldif}"
    if /usr/bin/ldapadd -Y EXTERNAL -H ldapi:/// < "$ldif" > "/tmp/result.out" 2>&1; then
      echo "Success: Committed ${ldif}"
    else
      echo "FAILURE: Could not commit ${ldif}"
      cat "/tmp/result.out"
      kill -9 "$OPENLDAP_PID"
      exit 255
    fi
  done
done

echo ""
echo "Hey there, I'm all done setting up! The LDAP server is running on port 636. Test away!"
echo ""

# Wait for openldap
wait $OPENLDAP_PID
