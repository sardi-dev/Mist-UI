# Artwork

This repository holds code only. The texture files the addon draws with are
game artwork owned by the game's publisher. They are not covered by this
project's MIT License, so they are not stored here.

The addon looks for its textures in two folders that git ignores:

- `MistUI/Textures/`
- `MistUI_Options/Textures/`

Without them the addon still loads, but its frames show as plain green boxes.

## Getting the artwork

Mist-UI uses the same texture files as [DragonUI](https://github.com/NeticSoul/DragonUI),
the project it is based on. `tools/art-manifest.json` lists which of its
texture folders are used and the exact upstream commit they come from.

### Players (Windows)

Double-click `MistUI/Install-Artwork.cmd` in `Interface/AddOns`. It runs
`MistUI/install-artwork.ps1` with Windows PowerShell, which downloads the
source archive of the pinned DragonUI commit from GitHub into a temporary
folder, copies the listed folders into place and deletes the temporary folder.
Nothing else on the computer is changed. To use a DragonUI zip or folder you
already have, run it from a command prompt with `-Source <path>`.

### Players (manual)

1. Open `https://github.com/NeticSoul/DragonUI/archive/<commit>.zip`, with the
   commit from `MistUI/art-manifest.json` (in a release zip) or
   `tools/art-manifest.json` (in this repository), and unzip it anywhere.
2. Copy the contents of its `DragonUI/Textures` folder into
   `Interface/AddOns/MistUI/Textures`, and of `DragonUI_Options/Textures` into
   `Interface/AddOns/MistUI_Options/Textures`. Copying the folders the
   manifest excludes does no harm; they are only not used.

### Developers

1. Clone DragonUI next to this repository and check out the commit named in
   the manifest:

       git clone https://github.com/NeticSoul/DragonUI.git ../DragonUI-upstream
       git -C ../DragonUI-upstream checkout <commit from the manifest>

2. Copy the listed folders into place:

       npm run art

   Pass `-- --from <path>` if the checkout lives somewhere else.

The copied files stay on your machine. Do not commit them.

## Adding or removing artwork

Edit `tools/art-manifest.json`. Each rule copies one upstream folder and can
exclude subfolders or single files that Mist-UI does not use. An `include`
list brings back single files or folders from inside an excluded folder.
