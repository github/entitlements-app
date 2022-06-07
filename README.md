# entitlements-app

[![acceptance](https://github.com/github/entitlements-app/actions/workflows/acceptance.yml/badge.svg)](https://github.com/github/entitlements-app/actions/workflows/acceptance.yml) [![test](https://github.com/github/entitlements-app/actions/workflows/test.yml/badge.svg)](https://github.com/github/entitlements-app/actions/workflows/test.yml) [![lint](https://github.com/github/entitlements-app/actions/workflows/lint.yml/badge.svg)](https://github.com/github/entitlements-app/actions/workflows/lint.yml) [![coverage](https://img.shields.io/badge/coverage-100%25-success)](https://img.shields.io/badge/coverage-100%25-success) [![style](https://img.shields.io/badge/code%20style-rubocop--github-blue)](https://github.com/github/rubocop-github)

`entitlements-app` is a Ruby gem which provides git-managed LDAP group configuration and access provisioning to your declared resources. It powers Entitlements, GitHub's internal Identity and Access Management (IAM) system. Entitlements is a pluggable system designed to alleviate IAM pain points.

## Quick Start

See [getting started](docs/getting-started.md)

# Inputs

Entitlements currently supports a single input option of configuration files in the form of `.txt`, `.rb` and `.yaml`.

## Git-managed config

Entitlements receives input from configuration files. By using git to back the config files, every file has a complete and visible audit trail.

See [configuration](docs/configuration.md) for a complete guide on entitlements configuration.

### Populating config from a source of truth

Entitlements requires an initial Org Chart configuration to define all of the valid users available to the system.

See [orgchart](docs/orgchart.md) for a complete guide to configuring your org chart data.

To take advantage of the full entitlements re-organization functionality, your org chart data should be automatically updated as changes happen to your organization.

See [reorgs](docs/reorgs.md) for examples of how Entitlements helps with re-orgs.

## Configuration

### Metadata

Entitlements allows for metadata tags which can be used to indicate attributes of the entitlements config other than membership. These metadata tags can be used to build additional automation on top of the Entitlements system.

For examples of ways to leverage metadata tags, see [metadata](docs/metadata.md)

### Expirations

Entitlements allows for expirations at the file level and the user/group level.

See [expirations](docs/configuration.md#expiration) for more on expirations.

### Filters

Entitlements supports a concept of filters. This allows you to group employees defined in your org chart by classifications, and require explicit access definitions for those employee classifications.

For examples on filters, see [filters](docs/filters.md)

# Outputs

## LDAP

Out of the box, Entitlements will output your sets to LDAP.

See [LDAP](docs/ldap.md) for more on LDAP.

# Plugins

Entitlements is a pluggable system. Plugins can be built for additional inputs and outputs.

For more on building plugins, see [plugins](docs/plugins.md)

## Contributing

Please see [CONTRIBUTING](CONTRIBUTING.md) for details.

## Security

We take security very seriously. Please see [SECURITY](SECURITY.md) for details on how to proceed if you find a security issue.
