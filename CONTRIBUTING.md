# Contributing

This document describes how to contribute to this project.

## Branches

The `main` branch contains only work that is tested, documented, and usable.

Do not commit to `main`. Merge every change through a pull request.

Create a branch from `main` for each change you make. Name the branch after the
change, for example `add-hello` or `fix-empty-input`.

## Issues

Create an issue before you start working. 
Describe the feature that is missing or the bug that needs to be fixed.
Add a suitable issue type from the side panel.

## Implementation

Create your branch from an up-to-date `main`:

```bash
git checkout main
git pull
git checkout -b add-hello
```

Make your changes and run the tests (and build and check the documentation).

Then commit and push it:

```bash
git add <file>
git commit -m "Add hello"
git push -u origin add-hello
```

## Pull requests

Open a pull request to merge your branch into `main`. Describe what the change
does, and link the issue it addresses, e.g. by writing `Closes #12` in the
description if the pull request fixes issue #12.

The tests and the documentation build run automatically on every pull request.
Both must pass.

If a check fails, fix the problem on your branch and push again: the checks run
again on the new commit, and the pull request updates itself. Leave the pull
request open while you do this.

If both checks pass, you may want to request a review from another contributor.

## Review

Read and review the changes in the **Files changed** tab of the pull request, then approve or request changes.

## Merge

Merge a pull request using the **Merge pull request** button at the bottom of the pull request.

If GitHub reports a conflict, bring your branch up to date, resolve the conflict, and push again:

```bash
git checkout main
git pull
git checkout add-hello
git merge main
```

Branches dedicated to a single pull request can be deleted after merging.

