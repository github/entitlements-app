#!/bin/sh

set -e

# Create our fake git repo into the /git-server/repos directory.
rm -rf /git-server/repos
mkdir -p /git-server/repos/entitlements-audit
cd /git-server/repos/entitlements-audit
git config --global user.email "entitlements-acceptance-test@github.com"
git config --global user.name "Hubot"
git init --shared=true
echo "# entitlements-audit Sample Repo" > README.md
git add .
git commit -m "initialize repo"
cd /git-server/repos
git clone --bare entitlements-audit entitlements-audit.git

# Invoke git-server's entrypoint.
cd /git-server
sh start.sh
