# Contributing to fl_pi_llm

Bug reports, fixes and new provider support are welcome.

## Before opening a pull request

- **Small fixes:** just open the pull request.
- **Anything that changes the API or the protocol between Dart and JS:** open
  an issue first. Both apps depend on it.
- **Bumping pi:** pin the exact versions in `js/package.json`, rebuild the
  bundle, and run both test suites — pi's API is still moving.

## Contributor License Agreement

Every contributor signs the [CLA](CLA.md) once
([中文译本](CLA_zh.md)). An automated check posts the instructions on your first
pull request, and you sign by leaving one comment:

```
I have read the CLA Document and I hereby sign the CLA
```

fl_pi_llm is AGPLv3, and the apps it is built into are also distributed through
the App Store, whose terms cannot all be satisfied alongside every AGPLv3
condition. The agreement grants the maintainer the right to ship your work in
those builds. You keep the copyright to what you wrote, and you can reuse it
anywhere else however you like. Read [CLA.md](CLA.md) for the terms that
actually bind — the paragraph above is a summary and nothing more.

Two things that trip the check up:

- **Commits authored by an email address not attached to your GitHub account.**
  The check then cannot tell who wrote them. Add the address at
  <https://github.com/settings/emails> (it can stay private) and comment
  `recheck`.
- **Co-authored commits.** Everyone who authored a commit in the pull request
  signs, not only whoever opened it.

## Development

See [README.md](README.md#develop). In short: `npm run build` in `js/` after a
JS change, `flutter_rust_bridge_codegen generate` after changing
`rust/src/api`, then `cargo test` in `rust/` and `dart test` at the root.

`node scripts/cla_workflow_test.js` tests `.github/workflows/cla.yml` against a
fake GitHub API. Run it after editing that workflow.
