#!/bin/bash

export DIR="/data/entitlements"
export SERVER="ldap-server.fake"

begin_fold() {
  local tag="$1"
  echo "%%%FOLD {${tag}}%%%" 1>&2
  set -x
}

end_fold() {
  set +x
  echo "%%%END FOLD%%%" 1>&2
}

ping_ldap_server() {
  ping -c 1 -w 1 "$SERVER" 1>&2 && rc=$? || rc=$?
  return $rc
}

set -e

begin_fold "Bootstrapping"
cd "$DIR"
mkdir -p .git/hooks # So bootstrap doesn't fail to create symlinks
script/bootstrap 1>&2
end_fold

begin_fold "Verifying network connectivity to the LDAP container"
COUNTER=0
SUCCESS=0
while [ $COUNTER -lt 3 ]; do
  let COUNTER=COUNTER+1
  if ping_ldap_server; then
    SUCCESS=1
    break
  fi
  sleep 1
done
end_fold

if [ "$SUCCESS" -eq 0 ]; then
  echo "" 1>&2
  echo "%%%HIGHLIGHT {danger}%%%" 1>&2
  echo "*** Error: Unable to ping host '$SERVER'" 1>&2
  echo "%%%END HIGHLIGHT%%%" 1>&2
  exit 255 1>&2
fi

begin_fold "Network details"
cat /etc/hosts 1>&2 || true
cat /etc/resolv.conf 1>&2 || true
getent hosts "$SERVER" 1>&2 || true
server_ip=$((getent hosts "$SERVER" || true) | awk '{ print $1 }')
getent hosts "$server_ip" 1>&2 || true
end_fold

begin_fold "Installing SSL CA certificate"
cp /acceptance/ca/intermediate/certs/ca-chain.cert.pem /etc/ssl/certs/
cert_hash=$(openssl x509 -hash -in /acceptance/ca/intermediate/certs/ca-chain.cert.pem -noout)
ln -s /etc/ssl/certs/ca-chain.cert.pem "/etc/ssl/certs/${cert_hash}.0"
cat /etc/ssl/certs/ca-chain.cert.pem >> /etc/ssl/certs/ca-certificates.crt
end_fold

begin_fold "Waiting for openldap server to become available"
COUNTER=0
SUCCESS=0
DN="uid=emmy,ou=Service_Accounts,dc=kittens,dc=net"
while [ $COUNTER -lt 3 ]; do
  let COUNTER=COUNTER+1
  if ldapsearch -H ldaps://ldap-server.fake:636 -D "$DN" -w kittens -b "$DN" -d-1 > /tmp/ldapsearch.out 2>&1; then
    echo "Success connecting to LDAP server!" 1>&2
    SUCCESS=1
    break
  fi

  echo "Failed to bind to LDAP on try ${COUNTER} of 30" 1>&2

  # Make sure server has not died
  if ping_ldap_server; then
    sleep 1
    continue
  fi

  echo "LDAP server is no longer pingable. Aborting" 1>&2
  SUCCESS="0"
  break
done
end_fold

if [ "$SUCCESS" -eq 0 ]; then
  echo "" 1>&2
  echo "%%%HIGHLIGHT {danger}%%%" 1>&2
  echo "*** Error: Unable to connect to host '$SERVER' on port 636/tcp" 1>&2
  cat /tmp/ldapsearch.out 1>&2
  echo "%%%END HIGHLIGHT%%%" 1>&2
  exit 255
fi

export PATH="/usr/share/rbenv/shims:$PATH"
cd "/data/entitlements"
FAILED_TEST=0
for test in spec/acceptance/tests/*_spec.rb; do
  test_name=$(basename "$test" | sed -s 's/_spec\.rb$//')

  if [ $FAILED_TEST -eq 1 ]; then
    echo "Test: ${test_name} - Skipped because previous test failed" 1>&2
    continue
  fi

  bundle exec rspec "$test" > /tmp/rspec.out 2>&1 && rc=$? || rc=$?

  if [ "$rc" -eq 0 ]; then
    begin_fold "Test: ${test_name} - Passed"
    cat /tmp/rspec.out 1>&2
    end_fold
  else
    echo "%%%HIGHLIGHT {danger}%%%" 1>&2
    echo "Test: ${test_name} - Failed (exitcode = $rc)" 1>&2
    echo "%%%END HIGHLIGHT%%%" 1>&2
    cat /tmp/rspec.out 1>&2
    FAILED_TEST=1
  fi
done

exit $FAILED_TEST
