# Filters

Filters allow for more specific tuning of access to entitlements.

## Example

Let's assume that we have an entitlement, `everybody.txt`. This entitlement is automatically updated to include every person in the company. We reference this entitlement in places like our messaging software and email lists.

In the event that we wanted a version of `everybody.txt` which was Employees-only, we could add a filter for `contractors`. 

With a `contractor` filter defined, all `contractors` will be filtered from entitlements by default. Contractors are only added to an entitlement if there is a corresponding `contractors = <handle>` or `contractors = all` in the same file.

Lets assume we have `bob` who is an employee and `jane` who is a contractor.

```text
username = bob
username = jane
```

Only `bob` will have access here, since there is not an additional filter declaration.

```text
username = bob
username = jane
contractors = jane
```

Both `bob` and `jane` will have access here, since a contractor filter allowing `jane` is defined.

```text
username = bob
username = jane
contractors = all
```

Both `bob` and `jane` will have access here, since a contractor filter allowing `all` is defined.

Filters can also be used for groups, like:

```text
group = pizza_teams/contractor_group
contractors = pizza_teams/contractor_group
```

Everyone inside of `pizza_teams/contractor_group` will be granted access, including `contractors`.


## Filter Config

### Group

This is the group which you are comparing membership against. For the `Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup` class, if the employee is a member of this group then they will automatically be filtered from the entitlement.

### excluded_paths

`excluded_paths` takes a list of paths which are automatically granted `filter = all` and are excluded from the filter process.

### included_paths

`included_paths` takes a list of paths which are automatically granted `filter = none` and are included in the filter process.

### Advanced config

`excluded_paths` and `included_paths` can be used together for advanced configuration. In the event that there is a folder which you want to exclude all but one (or a few) subfolders for a filter, you can set both `excluded_paths` and `included_paths` like so:

```yaml
  my-filter:
    class: Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup
    config:
      group: internal/my/group
      excluded_paths:
        - everything/
      included_paths:
        - everything/this_one_folder
        - everything/this_other_folder
```

`included_paths` takes precedence over `excluded_paths`, so every folder under `everything/` would be excluded except `everything/this_one_folder` and `everything/this_other_folder`.
