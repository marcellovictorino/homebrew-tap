# marcellovictorino/homebrew-tap

Homebrew formulae for my open-source tools. Each formula builds from the tagged source of its own project, on your Mac.

```sh
brew tap marcellovictorino/tap
brew install marcellovictorino/tap/<formula>
```

| Formula | Project |
| --- | --- |
| `desk-check` | [desk-check](https://github.com/marcellovictorino/desk-check): menu bar posture coach that says how to move your screen and desk |
| `pill` | [pill](https://github.com/marcellovictorino/pill): run the Pi coding agent with local llama.cpp models |

## How releases reach the tap

Each project publishes a GitHub release from its own repository. The `update` workflow in this tap checks every 6 hours (and on demand from the Actions tab, with the Run workflow button) for a newer release of each formula that opts in. Each formula is handled on its own: it is rebuilt from source as a check, and its new URL, checksum and commit land as a commit of their own. A formula whose release lookup or build fails is left as it was and the run is marked failed, while the other formulas still update. It uses only the workflow's built-in permission; there is no secret.

To list a project, give its formula a first line `# updater: OWNER/REPO`, a `url` of the form `https://github.com/OWNER/REPO/archive/refs/tags/vX.Y.Z.tar.gz` and a `sha256` line. A `COMMIT = "<sha>"` line, if present, is kept at the release's commit for stamping into the build. A `revision N` line, which makes `brew upgrade` reinstall a formula changed on the same release, is removed when the formula moves to a new release.

A formula may also have a second first-line comment, `# template: PATH`, naming a formula file in the project's own repository (desk-check does: `Formula/desk-check.rb`). The updater then copies that file as it is at the release tag, keeping this tap's `url`, `sha256`, `COMMIT` and `revision` and the two comments, so the install and test steps are changed in the project, never here. The copy is also repaired on a run where the formula is already on the latest release. A template that cannot be read fails that formula's update and leaves it as it was.

Tag the project's release before adding its formula, and point the formula at that tag with its real checksum. A formula whose checksum is all zeros (a placeholder for a release not yet tagged) fails the tap's checks.
