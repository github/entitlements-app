# Contributing

[fork]: https://github.com/github/entitlements-app/fork
[pr]: https://github.com/github/entitlements-app/compare
[style]: https://github.com/styleguide/ruby
[code-of-conduct]: CODE_OF_CONDUCT.md

Hi there! We're thrilled that you'd like to contribute to this project. Your help is essential for keeping it great.

Contributions to this project are [released](https://help.github.com/articles/github-terms-of-service/#6-contributions-under-repository-license) to the public under the [project's open source license](LICENSE.md).

Please note that this project is released with a [Contributor Code of Conduct][code-of-conduct]. By participating in this project you agree to abide by its terms.

## Basics

- It follows the [GitHub style guide](https://github.com/github/rubocop-github/blob/master/STYLEGUIDE.md) (enforced by Rubocop).

    Following a consistent style allows other developers to hop in and contribute with clearly defined patterns.

- It uses the [contracts gem](https://github.com/egonSchiele/contracts.ruby) to enforce method input and output.

    It's easy to introduce bugs by passing or returning inconsistent data types, and tracking down those `Undefined method for nil:NilClass` errors can be painful. Ruby contracts help to avoid these problems proactively, freeing us from writing tons of boilerplate, defensive code. (There is a performance penalty, but the nature of Entitlements does not require it to be high performance.)

- 100% [unit test](#unit-tests) coverage is required.

    A complete set of unit tests ensures that our code works as expected and forces us to provide coverage for both happy and sad paths. The `# :nocov:` control comment can be used to avoid writing test coverage for small portions of code where it is not reasonable to do so.

- Unit tests must not connect to external services, ever.

    Unit tests should stub/mock any calls to external services, which allows those tests to run quickly and easily in both local development environments and CI.

- [Acceptance test](#acceptance-tests) coverage is required for new and interesting functionality.

    Acceptance tests provide end-to-end coverage of the functionality of the application from a user perspective. By testing against realistic network services (e.g. an LDAP server running in a Docker container) we can increase our confidence that the application will work in production.

- Acceptance tests do not connect to external services, ever.

    Acceptance tests should be backed by services running in Docker containers, which can be actual services (e.g. an OpenLDAP server) or fake services (e.g. a simple Sinatra application that simulates certain GitHub.com APIs). Acceptance tests should never contact or depend on actual network services.

## Submitting a pull request

0. [Fork][fork] and clone the repository
0. Configure and install the dependencies: `script/bootstrap`
0. Make sure the tests pass on your machine: `rake`
0. Create a new branch: `git checkout -b my-branch-name`
0. Make your change, add tests, and make sure the tests still pass
0. Push to your fork and [submit a pull request][pr]
0. In the pull request description: communicate the goal of your PR with as much detail as possible.

## Resources

- [Entitlements design](docs/design.md)
- [Entitlements tests](docs/tests.md)

## Resources - General

- [How to Contribute to Open Source](https://opensource.guide/how-to-contribute/)
- [Using Pull Requests](https://help.github.com/articles/about-pull-requests/)
- [GitHub Help](https://help.github.com)
