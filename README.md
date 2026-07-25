# Runestone Tracker

A small World of Warcraft addon that displays the currently active Eversong Woods runestone in a movable on-screen panel.

It reads the same Area POI and widget data used by the Eversong Woods world map and shows:

- The active runestone location
- The current runestone state, such as needing Latent Arcana or being defended
- Charging progress when Blizzard exposes a progress value
- Your current Latent Arcana count

The tracker refreshes automatically. If the map temporarily has no runestone POI, it displays **Not detected** until the next marker appears.

## Quick installation on Windows

1. Download or clone this repository.
2. Open PowerShell in the repository folder.
3. Run:

   ```powershell
   .\Install.ps1
   ```

The script searches the common World of Warcraft install locations and copies the addon files into:

`World of Warcraft\_retail_\Interface\AddOns\RunestoneTracker\`

For a custom installation location, provide the main World of Warcraft folder or the `_retail_` folder:

```powershell
.\Install.ps1 -WowPath "D:\Games\World of Warcraft"
```

You may need to allow the script for the current PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install.ps1
```

## Manual installation

1. Exit World of Warcraft.
2. Download or clone this repository.
3. Put the addon folder in:

   `World of Warcraft\_retail_\Interface\AddOns\RunestoneTracker\`

4. Make sure the folder contains:

   - `RunestoneTracker.toc`
   - `RunestoneTracker.lua`

5. Start WoW and enable **Runestone Tracker** on the AddOns screen.

## Commands

- `/rst show` — shows the tracker
- `/rst hide` — hides the tracker
- `/rst toggle` — toggles the tracker
- `/rst lock` — prevents dragging
- `/rst unlock` — allows dragging
- `/rst reset` — resets the tracker position
- `/rst scan` — refreshes immediately
- `/rst debug` — prints the detected POI and widget text to chat for troubleshooting

Drag the tracker with the left mouse button while it is unlocked.

## Notes

- The addon checks Eversong Woods map ID `2395` every two seconds and listens for POI and UI-widget updates.
- The runestone tooltip state is supplied through Blizzard's UI widget data, so the exact wording can change with the live event.
- `/rst debug` is useful if Blizzard changes the widget format and the displayed state needs adjustment.
