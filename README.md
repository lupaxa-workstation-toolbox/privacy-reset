<p align="center">
    <a href="https://github.com/lupaxa-workstation-toolbox">
        <img src="https://raw.githubusercontent.com/the-lupaxa-project/brand-assets/master/logos/organisations/workstation-toolbox/readme-logo.png" alt="Organisation Logo" />
    </a>
</p>

<h1 align="center">Privacy Reset</h1>

Interactive menu for resetting macOS privacy grants. The usual case is folder
access for the terminal you are in: Downloads, Desktop, Documents, and Full
Disk Access. You can reset one service, another app, or every app for the
current user.

The reset clears the grant. macOS asks again the next time that app needs the
permission. This tool does not quit or relaunch the target, and it does not
use `sudo`.

## Requirements

- macOS with `tccutil` and `sqlite3` (both ship with macOS)
- Bash (macOS `/bin/bash` 3.2 or newer is fine)
- A terminal (the menu clears the screen and pauses after each reset)

Listing apps reads `~/Library/Application Support/com.apple.TCC/TCC.db`. That
read needs Full Disk Access. A reset itself uses `tccutil` and does not read
the database.

## Quick Start

With Homebrew, from the public tap:

```bash
brew tap the-lupaxa-project/tap
brew trust the-lupaxa-project/tap
brew install privacy-reset
```

Or clone the repository and run the script:

```bash
git clone git@github.com:lupaxa-workstation-toolbox/privacy-reset.git
cd privacy-reset
./src/privacy-reset
```

To run a checkout from anywhere on `PATH`, copy or symlink into your personal `bin`:

```bash
cp /path/to/privacy-reset/src/privacy-reset ~/bin/privacy-reset
chmod +x ~/bin/privacy-reset
```

With no arguments the interactive menu opens. Press `Q` to quit.

```bash
./src/privacy-reset --help
```

`--help` prints the flags and exits 0. It does not require `tccutil` on
`PATH`. Any other invocation does: if `tccutil` is missing, the script prints
`Error: tccutil was not found in PATH.` and exits 1 before showing the menu.

## Modes

**Menu mode** is the default (no arguments). The screen clears, you pick a
number, and after a reset you press Enter to return. Actions for the detected
terminal do not ask first. Resetting every app asks `[y/N]` first. The default
answer is no. Only `y`, `Y`, `yes`, or `YES` accepts.

**Flag mode** is one action flag per run. There is no menu, no pause, and no
confirmation prompt. `--all` exits 2 unless you also pass `-y` or `--yes`.

## Typical Workflow

1. Run the menu in the terminal that lost folder access.
2. Choose `1` to reset Downloads, Desktop, Documents, and Full Disk Access for that terminal.
3. Quit and reopen it, then approve the permission prompts.

The same reset from the shell, aimed at Terminal:

```bash
./src/privacy-reset --folder-access --bundle-id com.apple.Terminal
```

With no `--bundle-id` and no `--all`, the script targets the terminal it is running in.

## Interactive Menu

```text
macOS Privacy Reset
===================
Target: Terminal (com.apple.Terminal)

  1) Reset folder access (Downloads, Desktop, Documents, Full Disk)
  2) Reset Downloads
  3) Reset Desktop
  4) Reset Documents
  5) Reset Full Disk Access
  6) Reset Accessibility
  7) Reset Automation
  8) Reset Developer Tools
  9) Reset Screen Recording
 10) Other app…
 11) All apps…

  Q) quit

Select an option:
```

`Q`, `q`, or `quit` prints `Goodbye.` and exits 0. End of file on the menu,
on a confirm, or on the Enter pause prints `EOF; exiting.` and exits 0. Any
other text prints `Invalid option:` and returns to the menu.

Options `1`–`9` apply to the target in the header. They do not confirm. After
the reset the menu prints:

```text
Done.
Quit and reopen Terminal, then approve any permission prompts.
Press Enter to continue...
```

The name is the detected app. If detection fails, the header says
`Target: unknown` and options `1`–`9` ask for a bundle id first.

A single service that fails prints `Command exited with status N.` The folder
set does not. Each failed service in that set prints
`Failed: SERVICE (status N).` and the remaining services still run. The menu
then prints `Done.` and stays open.

### Menu Reference

| Option | What it resets   | Notes                                                          |
| :----- | :--------------- | :------------------------------------------------------------- |
| `1`    | Folder access    | Downloads, then Desktop, then Documents, then Full Disk Access |
| `2`    | Downloads        | `SystemPolicyDownloadsFolder`                                  |
| `3`    | Desktop          | `SystemPolicyDesktopFolder`                                    |
| `4`    | Documents        | `SystemPolicyDocumentsFolder`                                  |
| `5`    | Full Disk Access | `SystemPolicyAllFiles`                                         |
| `6`    | Accessibility    | `Accessibility`                                                |
| `7`    | Automation       | `AppleEvents`                                                  |
| `8`    | Developer Tools  | `DeveloperTool`                                                |
| `9`    | Screen Recording | `ScreenCapture`                                                |
| `10`   | Another app      | Opens the other-app list                                       |
| `11`   | Every app        | Same nine actions, each one confirms                           |
| `Q`    | —                | Quit                                                           |

### Other App

Option `10` lists bundle ids that already have a folder grant (allowed or
limited) for Downloads, Desktop, Documents, or Full Disk Access. When
Spotlight can resolve the id, the row shows the app name as well:

```text
Other app

  1) Terminal (com.apple.Terminal)
  2) iTerm (com.googlecode.iterm2)
  T) type a bundle id
  B) back

  Q) quit

Select an option:
```

Pick a number to open the same nine actions for that app. `T` asks for a
bundle id. `B` returns to the main menu.

If the privacy database cannot be read, the screen says
`Could not read the privacy database. Full Disk Access is required to list apps.`
and asks for a bundle id. An empty id returns to the main menu. A bundle id
with a space, a tab, a single quote, or a leading `-` prints
`Error: invalid bundle id.` and asks again.

### All Apps

Option `11` uses the same nine actions. Each one asks first, for example:

```text
Reset folder access for every app? [y/N]:
```

Enter, or any answer other than `y`, `Y`, `yes`, or `YES`, returns to that
menu without calling `tccutil`. `B` returns to the main menu.

After an accepted reset the menu prints:

```text
Done.
Quit and reopen the affected apps, then approve any permission prompts.
```

## CLI Flags

One action flag per invocation. `--bundle-id`, `--all`, and `-y` / `--yes`
may accompany that action. A second action flag, an unknown flag, or `--yes`
with no action prints an error and exits 2.

| Flag                 | Menu | Notes                                              |
| :------------------- | :--- | :------------------------------------------------- |
| `-h`, `--help`       | —    | Print usage and exit 0. Does not require `tccutil` |
| `--folder-access`    | 1    | Four folder services, in menu order                |
| `--downloads`        | 2    |                                                    |
| `--desktop`          | 3    |                                                    |
| `--documents`        | 4    |                                                    |
| `--full-disk`        | 5    |                                                    |
| `--accessibility`    | 6    |                                                    |
| `--automation`       | 7    |                                                    |
| `--developer-tools`  | 8    |                                                    |
| `--screen-recording` | 9    |                                                    |
| `--list-apps`        | 10   | Print granted bundle ids. Takes no target          |
| `--bundle-id ID`     | —    | Target app. Default is this terminal               |
| `--all`              | 11   | Every app for the current user. Requires `--yes`   |
| `-y`, `--yes`        | —    | Required with `--all`. Flag mode never prompts     |

Flag mode prints each call before it runs:

```text
==> tccutil reset SystemPolicyDownloadsFolder com.apple.Terminal
```

`--all` omits the bundle id, which is how `tccutil` resets every app for the
current user:

```text
==> tccutil reset SystemPolicyDownloadsFolder
```

There is no `Done.` line and no Enter pause in flag mode. A single service
that fails prints `Command exited with status N.` and that status is the
process exit status. A folder-set failure prints `Failed: SERVICE (status N).`
for each failure, still runs the rest, and exits with the last non-zero
status.

### Exit Status

| Status | When                                                                                                                                                |
| :----- | :-------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0`    | Help, quit, end of file, or the action finished without a reported failure                                                                          |
| `1`    | `tccutil` is not on `PATH`, the privacy database could not be read, or no bundle id could be detected                                               |
| `2`    | Unknown flag, a second action, no action, an invalid bundle id, `--all` without `--yes`, `--all` with `--bundle-id`, or `--list-apps` with a target |
| other  | The last non-zero `tccutil` status, in flag mode                                                                                                    |

## Examples

**Reset folder access for the terminal you are in:**

```bash
./src/privacy-reset
# menu option 1
```

```bash
./src/privacy-reset --folder-access
```

**Reset one service for that same terminal:**

```bash
./src/privacy-reset --downloads
./src/privacy-reset --desktop
./src/privacy-reset --accessibility
```

**Reset a named app:**

```bash
./src/privacy-reset --list-apps
./src/privacy-reset --folder-access --bundle-id com.apple.Safari
./src/privacy-reset --screen-recording --bundle-id com.apple.Safari
```

`--list-apps` prints one bundle id per line. Use one of those ids with
`--bundle-id`. If the database cannot be read, that command prints
`Error: could not read the privacy database.` and exits 1. Pass `--bundle-id`
yourself in that case. A reset does not need the database.

**Reset every app** (current user only):

```bash
./src/privacy-reset --downloads --all --yes
./src/privacy-reset --folder-access --all --yes
```

`./src/privacy-reset --downloads --all` without `--yes` prints
`Error: resetting every app requires --yes` and exits 2.

**When the terminal cannot be detected:**

```bash
./src/privacy-reset --downloads --bundle-id com.apple.Terminal
```

Without a bundle id the script prints
`Error: could not detect a bundle id. Pass --bundle-id.` and exits 1.
Detection walks parent processes for an `.app` bundle. If that finds nothing,
`TERM_PROGRAM` is used for Terminal (`Apple_Terminal`), iTerm (`iTerm.app`),
Ghostty (`ghostty`), and Warp (`WarpTerminal`). `TERM_PROGRAM=vscode` is not
mapped, because Visual Studio Code and Cursor both set it. Pass `--bundle-id`
for those.

**Refused invocations** (each exits 2):

```bash
./src/privacy-reset --downloads --desktop
./src/privacy-reset --yes
./src/privacy-reset --all --yes --bundle-id com.apple.Terminal
./src/privacy-reset --list-apps --bundle-id com.apple.Terminal
./src/privacy-reset --downloads --bundle-id '-not-an-id'
```

Only one action flag is accepted. `--yes` on its own is not an action.
`--all` and `--bundle-id` cannot be combined. `--list-apps` cannot take a
target. A bundle id must not contain a space, a tab, or a single quote, and
must not start with `-`.

<a href="https://github.com/the-lupaxa-project">
    <img src="https://raw.githubusercontent.com/the-lupaxa-project/brand-assets/master/logos/components/footer-for-child-orgs.svg" alt="The Lupaxa Project Footer" width="100%" />
</a>
