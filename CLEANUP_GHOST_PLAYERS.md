# Cleaning Up Ghost "Music Assistant Mobile" Players

## The Problem

Early versions of Amass registered the mobile device as a local playback player with Music Assistant. This created "Music Assistant Mobile" player entities on your server. Multiple app restarts/logins created multiple ghost players that persist on the server.

## Current Status

The Amass app now:
- ✅ No longer registers as a player (acts as remote control only)
- ✅ Filters out these ghost players automatically
- ✅ Won't create new ghost players

However, the old players still exist on your Music Assistant server.

## How to Clean Up (Music Assistant Web UI)

### Option 1: Via Web UI Settings

1. Open your Music Assistant web UI (e.g., `http://ma.serverscloud.org:8097`)
2. Navigate to **Settings** → **Players**
3. Look for players named "Music Assistant Mobile" or similar
4. For each ghost player:
   - Click the **⋮** (three dots) menu
   - Select **Remove Player** or **Delete**
5. Confirm deletion for each one

### Option 2: Via Players Tab

1. Open Music Assistant web UI
2. Click the **Players** tab
3. Find all "Music Assistant Mobile" entries
4. Right-click or use the context menu to remove each one

## How to Clean Up (Home Assistant)

If Music Assistant is integrated with Home Assistant:

1. Open Home Assistant
2. Go to **Settings** → **Devices & Services**
3. Click **Music Assistant**
4. Look for "Music Assistant Mobile" devices/entities
5. For each one:
   - Click on the entity
   - Click **⋮** → **Delete**

## How to Clean Up (Command Line / SSH)

If you have SSH access to your Music Assistant server:

```bash
# Connect to your server
ssh user@ma.serverscloud.org

# Access Music Assistant container (if dockerized)
docker exec -it music_assistant bash

# Or if running as an add-on, use Home Assistant CLI
ha addons exec music_assistant

# Navigate to data directory (location varies by installation)
cd /data  # or wherever your config is stored

# Backup first!
cp mass.json mass.json.backup

# Edit the config file
nano mass.json  # or vi, etc.

# Look for player entries with names like "Music Assistant Mobile"
# Remove those entries (be careful with JSON syntax!)
# Save and exit

# Restart Music Assistant
# (from outside container if dockerized)
docker restart music_assistant
```

⚠️ **Warning**: Manual JSON editing is risky. Use web UI method if possible.

## Verifying Cleanup

After cleanup, check the Amass app logs. You should see:
- No more "Filtering out leftover player" messages
- "Loaded X players" with a reasonable count (not 30+)

## Prevention

The current version of Amass (v1.0.0+) will not create new ghost players. If you see new ones appearing:
1. Make sure you're using the latest version
2. Uninstall any old versions of the app
3. Clear app data before reinstalling

## Questions?

If ghost players keep appearing after cleanup, there may be another app or integration registering them. Check:
- Other Music Assistant mobile apps
- Home Assistant automations
- Music Assistant player announcements
