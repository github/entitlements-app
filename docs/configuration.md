# Configuration

Entitlements supports 3 file formats, which are identified by the extension in the filename.

| Extension | Description |
| --------- | ----------- |
| `.txt`    | ["Simplified" plain text format](#Text) |
| `.yaml`   | [YAML format](#YAML) |
| `.rb`     | [Ruby code](#Ruby) |

If you use an extension other than the ones listed above, or do not include an extension at all, an error will occur.

## Text

### Format

The plain text format is handled as follows:

- `key = value` lines use [methods](/docs/methods.md) and top level parameters to define properties of a group
- Lines starting with `#` are treated as comments, and ignored
- Blank lines are ignored
- `#` in the middle of a line is a comment, e.g. `key = value # Hello` is treated as `key = value` internally

The following `key = value` top level parameters may be used to define properties and behavior of the group.

- `description = <some text description>` defines the description for the group

Any remaining `key = value` pairs must use [methods](/docs/methods.md). If multiple pairs are specified, the membership of the group is the `OR` of all of the pairs.

### Operators

The following operators are supported:

| Operator | Description |
| -------- | ----------- |
| `=`      | Include people for which statement is true. Multiple `=` in a group definition are generally treated with "OR" logic. |
| `!=`     | Exclude people for which statement is true. Multiple `!=` in a group definition will exclude anyone for whom ANY of the statements is true. |
| `&=`     | Filter results to keep only those people for whom the statement is true. Multiple `&=` in a group definition will keep people for whom *any* of the `&=` statements is true (i.e., `&=` statements are treated with "OR" logic with respect to each other).

### Expiration

It is possible to declare an expiration date for a whole file or for an individual entitlement within a file. The date format is `YYYY-MM-DD` and is interpreted as UTC. Any expired entitlements are automatically removed upon the next deploy after expiration.

To declare an expiration for an entire file, add the text `expiration = YYYY-MM-DD` on a separate line from any entitlements in the file. See the [example](#Example-Entitlements-File-with-Expiration).

To declare an expiration for an individual entitlement, add the text `; expiration = YYYY-MM-DD` to the end of a filter (e.g. `contractors = all ; expiration = YYYY-MM-DD`) or a rule (e.g. `group = pizza_teams/something ; expiration = YYYY-MM-DD`). If the expiration is for the only entitlment in the file, you will need to use the expiration for the full file instead of the individual entitlement version. If you don't it will cause CI to fail because it would later create an empty entitlement when it expired. See the [example](#Example-Individual-Entitlements-with-Expiration).

### Examples

#### Example: Simple Text File

```text
# This is a comment line that is ignored

description = A group of awesome octocats

group = pizza_teams/awesome-octocats
username = bob
username = jane
```

The above file defines a group whose description is "A group of awesome octocats". The membership consists of all members of the `pizza_teams/awesome-octocats` entitlement, plus the users `bob` and `jane`.

:bulb: **TIP**: The `group` and `username` methods are most commonly used to define team membership, but there are other methods available as well. See [Methods](/docs/methods.md) for details.

#### Example: Complex Text File

```text
description = Individuals so long as they are on the team
username = bob
username = jane
username = mary
group != pizza_teams/users-with-no-privileges
group &= pizza_teams/senior-code-reviewers
```

The above file determines membership as follows:

- Consider `bob`, `jane`, and `mary` for membership
- Exclude any of them who are in `pizza_teams/users-with-no-privileges`
- Exclude any of them who are not in `pizza_teams/senior-code-reviewers`

Let's assume, by way of example, that `pizza_teams/users-with-no-privileges` contains `bob` and `pizza_teams/senior-code-reviewers` contains `bob`, `jane` and `alice`. Then the group described by the text file above contains only `jane` (because `bob` is excluded due to `!=` and `mary` is not part of `senior-code-reviewers`). Note in particular what `alice` is *not* a member of the group, even though she appears in `senior-code-reviewers`, because `senior-code-reviewers` is being used as a filter and not an affirmative condition.

#### Example: Entitlements File with Expiration

```text
description = Demonstrates expiring entitlements file
username = bob
username = jane
expiration = 2019-01-01
```

In January 2019 all entries in the file will expire.

#### Example: Individual Entitlements with Expiration

```text
description = Demonstrates expiring entitlements
username = bob
username = jane; expiration = 2019-01-01
```

In the file above, in September 2018 the group membership will be `bob` and `jane`.

In January 2019 the membership will just be `bob` because  `jane`'s entitlement has expired.

## YAML

### Format

The YAML file format uses [YAML Ain't Markup Language](http://yaml.org/) to create a data structure that helps define group properties and membership. The expected data structure will contain:

| Key | Data Type | Status | Description |
| --- | --------- | ------ | ----------- |
| `description` | String | Optional | Description for the group (default equal to filename without extension) |
| `filter` | Hash | Optional | Hash of Strings, or Hash of Array of Strings, to configure filters for the group  |
| `metadata` | Hash | Optional | Hash of Strings to define metadata for the group |
| `rules` | Hash | Required | Rule to define group membership (see below) |

The `rules` must be declared as a hash, which contains one key and corresponding value. The key can either be a [method](/docs/methods.md) or a boolean logic operator.

### Operators

These are the supported boolean logic operators:

| Key | Data Type | Description |
| --- | --------- | ----------- |
| `or` | Array of Hashes | If one is true, it's true |
| `and` | Array of Hashes | If all are true, it's true |
| `not` | Hash | Negate the rule in the hash |

It is also possible to nest boolean logic operators.

### Expiration

Expiration dates can be set on `filter` and `rules` entries. As with text entitlements, the expiration date is formatted as `YYYY-MM-DD` and is interpreted in UTC.

To declare an expiration, follow the example below.

### Examples

#### Example: YAML file with a simple rule

```yaml
---
description: Everyone who reports to or through awesomeboss
rules:
  management: awesomeboss
```

This defines the group membership using the [`management` method](/docs/methods.md#management), which is most commonly used to define a team by its manager.

#### Example: YAML file with straightforward boolean "or" logic

```yaml
---
description: A cross functional team
rules:
  or:
    - group: pizza_teams/security-ops
    - group: pizza_teams/sre-lifecycle
```

This defines the group membership to be everyone who is either a member of `pizza_teams/security-ops` or `pizza_teams/sre-lifecycle`, which are groups that are defined elsewhere by the Entitlements application.

#### Example: YAML file with straightforward boolean "and" logic

```yaml
---
description: Select members of an external LDAP group
rules:
  and:
    - group: cn=security,ou=Staff_Account,ou=Groups,dc=github,dc=net
    - direct_report: awesomeboss
```

This defines the group membership to be everyone who is both a member of the LDAP group `cn=security,ou=Staff_Account,ou=Groups,dc=github,dc=net` (which is not managed by Entitlements) AND who is a direct report of `awesomeboss`.

#### Example: YAML file with nested booleans

```yaml
---
description: Nested boolean example
rules:
  or:
    - and:
      - management: awesomeboss
      - not:
          username: awesomeboss
    - and:
      - group: pizza_teams/sre-lifecycle
      - not:
          username: bob
      - not:
          username: jane
```

This one is admittedly a bit contrived... membership here consists of everyone in `awesomeboss`'s reporting structure (but excluding `awesomeboss`), PLUS anyone who is in `pizza_teams/sre-lifecycle` but excluding `bob` and `jane`.

#### Example: YAML file with expiration dates

```yaml
---
description: Expiration example
rules:
  or:
    - username: bob
    - username: jane
      expiration: "2019-01-01"
```

In the file above, in September 2018 the group membership will be `bob` and `jane`.

In January 2019 the membership will just be `bob` because `jane`'s entitlement has expired.

:bulb: Be sure to quote the `YYYY-MM-DD` in the YAML file. Otherwise, the YAML parser might try to construct a ruby date object and cause an error.

## Ruby

For the ultimate flexibility, you can write ruby code that defines group membership. We recommend that you don't, however. Please use [Text](#text) or [YAML](#yaml) whenever possible.

The code must be structured as follows:

```ruby
# frozen_string_literal: true

module Entitlements
  class Rule
    class PizzaTeams
      class SecurityOps < Entitlements::Rule::Base
        description "Some Text"

        def members
          # Set(String)
        end
      end
    end
  end
end
```

The `members` method must return a [Set](https://ruby-doc.org/stdlib-3.1.0/libdoc/set/rdoc/Set.html) of strings containing the distinguished names of the members. How you construct this Set will likely require some working knowledge of the [entitlements-app](https://github.com/github/entitlements-app) itself.

:bulb: **TIP**: This functionality exists so that we can respond to unanticipated situations without significant updates to the app itself. Please use [Text](#text) or [YAML](#yaml) whenever possible.

:bulb: **TIP**: For examples, see `.rb` files in [acceptance test fixtures for entitlements-app](https://github.com/github/entitlements-app/tree/master/spec/acceptance/fixtures).
