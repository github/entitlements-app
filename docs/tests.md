## Tests

The `entitlements-app` project has two types of tests: unit tests and acceptance tests.

### Unit tests

Basics:

- You broke it, you fix it

  If you make changes to code, fixtures, or tests that result in other tests breaking, it's your responsibility to update existing test fixtures and/or tests so that everything passes again.

- Use the correct directory structure and file naming conventions

  Unit tests go in or under the [`spec/unit`](/spec/unit) directory. The directory structure should mirror that of the [`lib`](/lib) directory; for example if your code is in `lib/entitlements/foo.rb` then the unit test goes in `spec/unit/entitlements/foo_spec.rb`.

- Test fixtures

  Fixtures are files that supply sample data for tests. They go in the [`spec/unit/fixtures`](/spec/unit/fixtures) directory. Generally you should prefer to add new fixtures rather than modify existing ones (unless you are adding something that is backward-incompatible that requires existing fixtures to be updated).

- Spec helper

  Unit tests must include the [`spec_helper.rb`](/spec/unit/spec_helper.rb) which is responsible for setting up rspec and simplecov (coverage analyzer) and loading the code. There are also some handy utility methods in the spec helper.

- No external dependencies

  Requiring an external service, such as a web server, LDAP server, or third party website in order to run your unit tests is an absolute no-no. Your unit tests must be able to stand alone and run in an environment completely isolated from the network. Use mocks and doubles to stub any external functionality.

- Tests must pass standing alone and when run as a suite

  Each unit test must be able to stand alone. No one unit test should depend on the results of any previous unit test. It must always be possible to invoke unit tests via any of the following commands:

    ```shell
    # Run one specific test identified by line number
    bundle exec rspec spec/unit/entitlements/foo/bar_spec.rb:15

    # Run all unit tests in a given file
    bundle exec rspec spec/unit/entitlements/foo/bar_spec.rb

    # Run all the unit tests
    bundle exec rspec spec/unit

    # Run the entire suite the same way that CI does
    ./script/cibuild
    ```

- Test coverage is expected

  Our continuous integration suite expects 100% test coverage from unit tests. Do not ask for review on a PR until tests have been written. Submitting code without corresponding test coverage is not OK (and it's not "ship and iterate").

  When `script/cibuild` runs, a coverage report is output into the `coverage` directory at the top of the project. This includes a HTML output which you can open with your browser to examine color-coded lines indicating coverage status. The `# :nocov` control comment can be used within the code to stop coverage requirements (with another identical comment to restart). The control comment is best used for trivial code or code not expected to be invoked, such as an exception raised for a potential bug condition. Please do not exclude large portions of code from coverage requirements simply to avoid writing tests.

### Acceptance tests

Acceptance tests use real (or mostly real) services, running in Docker containers, to test the functionality of `entitlements-app` against actual LDAP servers, simulated GitHub.com API servers, and the like. Each acceptance test runs a "deploy" of an entitlements "repo" and then checks log output and inquires to the back-end services to confirm that the results are correct.

Basics:

- You broke it, you fix it

  If you make changes to code, fixtures, or tests that result in other tests breaking, it's your responsibility to update existing test fixtures and/or tests so that everything passes again.

- Use the correct directory structure and file naming conventions

  Acceptance tests go in or under the [`spec/acceptance`](/spec/acceptance) directory. Within this directory structure, fixtures (which resemble entitlements repos) go under [`fixtures`](/spec/acceptance/fixtures), the tests themselves go under [`tests`](/spec/acceptance/tests), and files that support the Dockerized back-end files go into clearly named subdirectories. Note that the tests are named starting with a number so that they run in the expected order.

- Test fixtures

  Fixtures for acceptance tests resemble entitlements repo. If you are adding new functionality, you should generally update existing test fixtures (as opposed to creating entirely new fixtures). This allows confirmation that your code plays well with other code under more realistic deployment conditions. The most common fixtures are [`initial_run`](/spec/acceptance/fixtures/initial_run) which initializes back-ends from their initial state, and [`modify_and_delete`](/spec/acceptance/fixtures/modify_and_delete) which makes subsequent changes that build upon the initial run. If you need special purpose tests and fixtures, feel free to create them.

- No external dependencies

  Requiring an external service, such as a web server, LDAP server, or third party website in order to run your acceptance tests is an absolute no-no. Your acceptance tests must interact exclusively with services that run locally in Docker containers, set up in the [`docker-compose.yml`](/spec/acceptance/docker-compose.yml) file. These services can be actual implementations of a back-end service (such as an actual OpenLDAP server or network-accessible git server), or they can be simulations of the relevant APIs. All containers start from a consistent initial state with each test run, eliminating the need to clear out potential relics from prior tests.

- Tests run in order (and in Docker)

  The [acceptance tests](/spec/acceptance/tests) run in order, and each builds upon the previous. Therefore, running individual acceptance tests is not supported. The acceptance test suite can be run locally or in CI provided that Docker and docker-compose are available. Using docker-compose sets up a private internal network so your entitlements-app container can talk to its back-end services.

    ```shell
    ./script/cibuild-entitlements-app-acceptance
    ```

- Test coverage is expected

  Our continuous integration suite does not measure line-by-line test coverage in acceptance tests, so providing necessary coverage here is an art rather than a science. In general all "happy path" functionality should be tested (i.e., successful creates, reads, updates, and deletes should be reflected in acceptance tests, while testing specific error conditions might not be).

  Do not ask for review on a PR until tests have been written. Submitting code without corresponding test coverage is not OK (and it's not "ship and iterate"). This is especially true when adding a new back-end, even though doing so often comes with significant overhead setting up a Docker container that provides or simulates the back-end service.
