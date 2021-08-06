
# Contributing

To start contributing to SumUp Open Source projects, please accept our [Contributor License Agreement](https://opensource.sumup.com/cla). Should you have any questions or concerns, please get in touch with [opensource@sumup.com](mailto:opensource@sumup.com).

## Code of Conduct (CoC)

We want to foster an inclusive and friendly community around our Open Source efforts. Like all SumUp Open Source projects, this project follows the Contributor Covenant Code of Conduct. Please, [read it and follow it](CODE_OF_CONDUCT.md).

If you feel another member of the community violated our CoC or you are experiencing problems participating in our community because of another individual's behavior, please get in touch with our [maintainers](README.md#maintainers). We will enforce the CoC.

## Prerequisites

* **Signed and verified CLA**
* Elixir 1.9+

## Common commands

### Running the linter

```shell
> mix format
```
### Running the tests

```shell
> mix test
```

### Running the tests and display coverage report

```shell
> mix test --cover
```

## Workflows

### Submitting an issue

1. Check existing issues and verify that your issue is not already submitted.
 If it is, it's highly recommended to add  to that issue with your reports.

2. Open issue

3. Be as detailed as possible - `elixir` version, what did you do,
what did you expect to happen, what actually happened.

### Submitting a PR

1. Find an existing issue to work on or follow `Submitting an issue` to create one
 that you're also going to fix.
 Make sure to notify that you're working on a fix for the issue you picked.
1. Branch out from latest `main`.
1. Code, add tests, run the formatter.
1. Make sure that tests pass locally for you.
1. Commit and push your changes in your branch.
1. Submit a PR.
1. Collaborate with the codeowners/reviewers to merge this in `main`.

### Releasing

#### Rules

1. Releases are only created from the `main` branch.
1. `main` is meant to be stable, so before tagging a new release, make sure that the CI checks pass for `main`.
1. Releases are GitHub releases.
1. Release tags are following *semantic versioning*.
1. Releases and tags are to be named in pattern of `vX.Y.Z`.
1. Release descriptions must include a summary of all changes in the release

#### Flow

1. Merge the (approved) changes into `main`
1. Create a new GitHub Release from `main` with proper name (`vX.Y.Z`), tag (`vX.Y.Z`) and description (summary of changes)
