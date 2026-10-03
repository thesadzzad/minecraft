# Minecraft Server Sync & Launcher

A Cloudflare R2-powered synchronization setup allowing you and your friends to take turns hosting a Minecraft server without manual file transfers.

## 🚀 How It Works

1. **Host A** finishes playing, stops the server, and runs `push.bat` to sync the world & files to Cloudflare R2.
2. **Host B** runs `pull.bat` to download the latest world & server state.
3. **Host B** runs `start.bat` to host the server with automatic Discord status notifications.

---

## 🛠️ Setup for a New Host / Friend

If you are setting this up on a friend's PC for the first time:

1. Clone or download this repository into your server folder (or copy `setup.ps1` into the folder).
2. Right-click PowerShell and choose **Run as Administrator** (or run standard PowerShell), then execute:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\setup.ps1
   ```
3. Enter your Cloudflare R2 credentials when prompted:
   - Account ID
   - Access Key ID
   - Secret Access Key
   - Bucket Name
4. The script will automatically install **Rclone** (via winget if needed) and generate `pull.bat` and `push.bat`.

---

## 🎮 Daily Usage

### 1. Before Hosting
Run `pull.bat` to download the latest world and player data:
```cmd
pull.bat
```

### 2. Launching the Server
Run `start.bat`:
```cmd
start.bat
```
- Automatically locates Java 21+ or prompts to install it.
- Starts `playit.gg` tunnel (if installed) for port forwarding-free multiplayer.
- Posts **Server Online** embed to Discord.
- When you type `stop` in the console, posts **Server Offline** embed to Discord and asks if you want to push to R2 immediately.

### 3. After Closing the Server
Run `push.bat` to sync everything back up so your friends can host next:
```cmd
push.bat
```
