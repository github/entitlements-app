## Design

`entitlements-app` is organized into a main controller class that runs as a CLI ([`lib/entitlements/cli.rb`](/lib/entitlements/cli.rb)) which calculates memberships in all of the defined entitlements, and then calls various back ends to implement those changes. The backends which are available by default are [`dummy`](/lib/entitlements/backend/dummy) (does nothing) and [`ldap`](/lib/entitlements/backend/ldap) (manipulates LDAP groups). 

The Entitlements system is meant to be pluggable. Plugins exist for these additional backends as well:

- [entitlements-github-plugin](https://github.com/github/entitlements-github-plugin) - [`github_team`](/lib/entitlements/backend/github_team) (adds and removes members of a GitHub team). 

### Backends

If you'd like to create a new plugin for an Entitlements backend, you'll effectively need to teach Entitlements how to create, read, update, and delete entries in that backend. 

[`lib/entitlements/backend/<yourbackend>`](/lib/entitlements/backend) is where you will create file(s) for your backend. If you're just getting started, consider copying the [`dummy` controller](/lib/entitlements/backend/dummy/controller.rb) which has all of the methods stubbed with no actual code.

In this directory you will create:

- **`controller.rb`**

  Your controller inherits from `Entitlements::Cli::BaseController` class. It contains specifically named methods that the CLI controller will call during the deployment process. Please see the comments in [`base_controller.rb`](/lib/entitlements/backend/base_controller.rb) for a list of the method signatures required (or more practically, look at one of the existing controllers). You will be overriding some or all of the following methods:

    - `self.prefetch(cache)` - (optional) Do something before all processing. If your backend supports a concept of "fetch everything at once so you don't have to fetch one by one later" this is a good place to fetch things and cache that result. 

    - `self.validate(cache)` - (optional) Validate data in the cache. This should raise an error if something is wrong.

    - `self.calculate(cache)` - (required) This calculates differences between what's in the backend now and what should be there. The result is a list of [actions](/lib/entitlements/cli/action.rb) which are later acted upon. This is typically delegated to [`lib/entitlements/data/groups/<yourbackend>.rb`](/lib/entitlements/data/groups).

    - NOTE: If no-op mode is engaged, this is the point at which things stop.

    - `self.preapply(cache)` - (optional) Run any "pre-apply" steps. Example: in the LDAP provider this creates any missing OUs.

    - `self.apply(cache, action)` - (required) This applies a given action, so this is where you teach Entitlements to create, update, and delete entries in your backend. This method is called once per action and often delegates work to service classes in [`lib/entitlements/service`](/lib/entitlements/service).

- **`provider.rb`**

  It may be helpful to treat each unique instance of your backend as a separate object (for example, the backend managing GitHub teams has one instance of the backend for each organization, since each organization might require unique credentials). Whether to use this, and how to structure it if you do, is not specified.

- **`service.rb`**

  It may be helpful to put common methods associated with accessing an external service into a separate class. Whether to use this, and how to structure it if you do, is not specified.
