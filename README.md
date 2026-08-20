# Plugin Folders for Omarchy

Declutter a busy Omarchy top bar without disabling the plugins you use. Each
folder is a compact, customizable bar icon that opens a launcher containing the
real native widgets assigned to it.

## Highlights

- Create as many folders as you need.
- Choose from 12 icons and 10 accent colors.
- Search the eligible plugins currently on your bar.
- Preserve each plugin's native click behavior, panel, service, and settings.
- Restore the exact saved section, nearby position, and complete bar entry when
  a plugin leaves a folder.
- Delete a folder safely: every member returns to the bar automatically.
- Keep structural Omarchy widgets protected from accidental hiding.
- Store everything locally with no account, network service, or telemetry.

## Install

```bash
omarchy plugin add https://github.com/dlpwaters/omarchy-plugin-folders.git --enable --yes
~/.config/omarchy/plugins/io.github.dlpwaters.plugin-folders/folderctl bootstrap
omarchy restart shell
```

Click the new **Plugins** folder beside the workspace switcher, open **Manage**,
and choose the plugins you want to move inside it. Use **New folder** to add
another independently styled folder to the bar. Right-click any folder icon to
jump directly into its organizer.

## How it works

Assigning a plugin removes only its standalone bar entry. Plugin Folders keeps
the plugin enabled and mounts its real `BarWidget.qml` component inside the
folder, including its original inline settings. The saved state also records
its section, index, and neighboring widgets for reliable restoration even if
the rest of the bar changes later.

State lives at:

```text
${XDG_STATE_HOME:-~/.local/state}/omarchy-plugin-folders/state.json
```

The helper keeps a last-operation safety copy beside `shell.json` as
`shell.json.plugin-folders.bak`.

## Safe removal

Restore all assigned plugins before uninstalling:

```bash
~/.config/omarchy/plugins/io.github.dlpwaters.plugin-folders/folderctl restore-all
omarchy plugin remove io.github.dlpwaters.plugin-folders --yes
```

`restore-all` removes the folder widgets and returns every member to the bar.

## Diagnostics and testing

```bash
~/.config/omarchy/plugins/io.github.dlpwaters.plugin-folders/folderctl doctor
omarchy plugin validate ~/.config/omarchy/plugins/io.github.dlpwaters.plugin-folders
qmllint -I /usr/share/omarchy/shell \
  ~/.config/omarchy/plugins/io.github.dlpwaters.plugin-folders/BarWidget.qml \
  ~/.config/omarchy/plugins/io.github.dlpwaters.plugin-folders/Panel.qml \
  ~/.config/omarchy/plugins/io.github.dlpwaters.plugin-folders/Service.qml
python -m unittest discover \
  ~/.config/omarchy/plugins/io.github.dlpwaters.plugin-folders/tests -v
```

## Compatibility

Built and tested on Omarchy `4.0.0-1`. Plugin Folders intentionally protects
first-party `omarchy.*` and structural bar widgets. Third-party widgets with a
standard Omarchy `bar-widget` entry point are eligible.

## License

[MIT](LICENSE)
