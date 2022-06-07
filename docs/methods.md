# Configuration Methods

## `username`

This method returns the specified username. Please note, using methods such as `direct_report`, `group`, and `management` are preferred to naming specific users.

#### Example: Username

Example configuration:

```yaml
---
rules:
  username: bob
```

Result: bob

## `group`

This method constructs membership in one Entitlements group based on the membership of another group managed by entitlements. When referencing a managed group, that group membership is recomputed as part of your deployment. So it's possible to make changes to multiple groups at a time with the same deployment, and it'll all work.

:boom: **NOTE**: If you create a circular dependency (e.g. groupA includes groupB which includes groupA), the CI job and deployment process will error.

To reference a managed group, use this syntax:

`group = <managed_ou_key>/<group_name>`

#### Examples: Managed group

```text
# apps/cross-functional-app.txt
description = Application that's being collaborated upon
group = pizza_teams/sre-lifecycle
group = pizza_teams/security-ops-eng
```

```yaml
# apps/cross-functional-app.yaml
description: Application that's being collaborated upon
rules:
  or:
    - group: pizza_teams/sre-lifecycle
    - group: pizza_teams/security-ops-eng
```

## `ldap_group`

:warning: *You should not do this unless you know exactly what you are doing. Where possible, LDAP groups that are not managed by Entitlements should be added to Entitlements.*

Unmanaged groups are LDAP groups that exist on the LDAP server but are not managed by the Entitlements app. When referencing an unmanaged group, that group membership won't change during your deployment. (You should never reference an LDAP group that is actually managed by Entitlements app using the unmanaged group syntax, because this could lead to inconsistency during deployment.)

To reference a managed group, use this syntax:

`ldap_group = cn=group-name,ou=whatever,ou=Groups,dc=github,dc=net`

#### Example: Unmanaged group

```text
# apps/accessible-to-staff-accounts-security.txt
description = Application that's accessible to externally managed security staff accounts group
ldap_group = cn=security,ou=Staff_Accounts,ou=Groups,dc=github,dc=net
```
