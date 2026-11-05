# marcellovictorino/homebrew-tap

Homebrew formulae for my open-source tools. Each formula builds from the tagged source of its own project, on your Mac.

```sh
brew tap marcellovictorino/tap
brew install marcellovictorino/tap/<formula>
```

| Formula | Project |
| --- | --- |
| `desk-undo` | [desk-undo](https://github.com/marcellovictorino/desk-undo): menu bar posture coach that says how to move your screen and desk |
| `pill` | [pill](https://github.com/marcellovictorino/pill): run the Pi coding agent with local llama.cpp models |

## How releases reach the tap

Each project publishes a GitHub release from its own repository. The `update` workflow in this tap checks every 6 hours (and on demand from the Actions tab, with the Run workflow button) for a newer release of each formula that opts in, rebuilds it from source as a check, and commits the new URL, checksum and commit. It uses only the workflow's built-in permission; there is no secret.

To list a project, give its formula a first line `# updater: OWNER/REPO`, a `url` of the form `https://github.com/OWNER/REPO/archive/refs/tags/vX.Y.Z.tar.gz` and a `sha256` line. A `COMMIT = "<sha>"` line, if present, is kept at the release's commit for stamping into the build.

A formula whose checksum is all zeros is a placeholder: the next update run fills it in once the release exists.
