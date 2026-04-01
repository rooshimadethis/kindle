# Kindle Remote Control & Debugging Guide

This document summarizes the technical knowledge and commands used to automate Kindle Paperwhite development and debugging via SSH.

## 1. Establishing the Connection

Kindle Paperwhite devices (especially PW5) often use legacy SSH algorithms that modern `ssh` clients disable by default.

### The "Magic" Connection Command
```bash
ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -p 2222 root@<KINDLE_IP>
```
*   **Port 2222**: Standard for KOReader's SSH server.
*   **Legacy Algorithms**: Required to negotiate the connection with the Kindle's SSH/Dropbear version.

## 2. Automating Interactions (Bypassing Passwords)

Since the Kindle SSH server often requests a password (even when set to "no password" in the UI), we use `expect` to automate the login.

### Template for Automated Command
```bash
expect -c 'spawn ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -p 2222 root@<IP> "<COMMAND>" ; expect "password:" ; send "\r" ; expect eof'
```

## 3. Remote Development Workflow

### Syncing Files (SCP)
To push plugin updates instantly without unplugging the device:
```bash
expect -c 'spawn scp -P 2222 -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa <LOCAL_FILE> root@<IP>:<REMOTE_PATH> ; expect "password:" ; send "\r" ; expect eof'
```

### Restarting KOReader
To apply changes, you must kill the existing process and relaunch it.
1.  **Kill**: `killall luajit`
2.  **Relaunch (Official)**: `lipc-set-prop com.lab126.appmgrd start app://koreader`
3.  **Relaunch (Script)**: `cd /mnt/us/koreader && nohup ./koreader.sh > /dev/null 2>&1 &`

**Full Automated Restart Command (Reliable)**:
```bash
expect -c 'spawn ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -p 2222 root@<IP> "killall luajit; killall koreader.sh; cd /mnt/us/koreader && nohup ./koreader.sh > /dev/null 2>&1 &" ; expect "password:" ; send "\r" ; expect eof'
```

## 4. Advanced Debugging

### Real-time Log Tailing
The most valuable tool for Kindle development:
```bash
ssh -p 2222 ... root@<IP> "tail -f /mnt/us/koreader/crash.log"
```

### On-Device Syntax Checking
To verify Lua code before starting the GUI (prevents "Could not start" errors):
```bash
cd /mnt/us/koreader
./luajit -b plugins/my_plugin.koplugin/main.lua /dev/null
```
*   If this returns an error, the plugin has a syntax mistake.
*   If it returns nothing (Exit 0), the syntax is perfect.

## 5. Directory Reference
*   **KOReader Root**: `/mnt/us/koreader/`
*   **Plugins**: `/mnt/us/koreader/plugins/`
*   **Crash Log**: `/mnt/us/koreader/crash.log`
*   **System Logs**: `/var/log/messages` (requires root)
