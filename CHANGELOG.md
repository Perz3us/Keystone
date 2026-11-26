# Changelog

## 1.1.1

- Cell guard, a new add-on: when you lock a cell, it removes the lock if the modem can't connect, the cell is much worse than the one before, or it stops working later, so a lock never leaves the router offline
- Locking a cell starts from the cells your modem can see, and warns before locking to one it can't see
- Locking or unlocking a cell retries when the modem is busy, and a newer lock or unlock always wins over an older one still running
- Locking and unlocking a cell no longer freezes when the modem is busy; the change finishes in the background
- The modem screen says when the modem stops answering instead of showing an old reading as connected
- A request that times out is no longer sent to the router twice
- Add-ons install in fewer steps, which is quicker over Tailscale and other remote connections
- The firmware's three example towers in Preferred towers are marked as examples and can be removed in one tap
- When adding a cell, EARFCN comes before PCI
- The More tab highlight is centred, and the update dot and device count show on wide screens

## 1.1.0

- Home-screen widgets in three sizes: Status, Data (used, allowance and days until reset) and Overview (signal and data together)
- Set a data plan, including unlimited and fair-use plans, and see how much is left and when it resets
- Alerts for outages, new devices, signal drops and data warnings. Choose which ones notify, which are only logged, and their limits. Keystone catches up on what happened when your phone gets back to the router's Wi-Fi
- "Why is it slow?" checks the connection and explains the cause in plain words, with a fix where there is one
- See how much data each device uses
- Check channels: find the quietest Wi-Fi channel from the networks the router hears nearby
- Restart Wi-Fi, the internet or the router on a schedule
- Smooth connection now finds the internet link on 5G/LTE modems and PPPoE, and never picks a VPN by mistake
- Speed test no longer stops with a garbled message when the router prints a warning
- Dynamic DNS saves the connection or device you choose and offers the router's real connections, including modems
- Pause, schedules, parental controls and guest Wi-Fi work when the router's internet zone isn't called "wan"
- Devices that left no longer show as online or wired
- Changing the address of the router you're using reconnects straight away
- The sign-in screen only says "On this Wi-Fi" when it's true

## 1.0.2

- Updates now download and install from inside the app: Keystone picks the APK for your phone, checks it against the release checksum and hands it to Android to install
- If the download fails, it opens the release page like before

## 1.0.1

- Pause now cuts a device off completely, including connections it already had open, and also works when the router runs a proxy such as Passwall
- Changing Wi-Fi security no longer fails with "Failed to update wireless section in UCI"
- Switching a network from WPA3 back to WPA2 or mixed mode no longer locks out older phones
- Saving settings keeps working after the router session expires

## 1.0.0

First public release.

- Home, Devices and Wi-Fi redesigned, with a light and dark theme
- Screens only show for features the router has, and appear once a package is installed
- Modem: signal, towers, bands, cell lock, network mode, SIM and APN, restart, and Check and fix
- Cell lock shows right away and Unlock is always there, even when the locked cell has no internet
- Preferred towers, for routers with `auto-pci-cell`
- Signal on Home: bars, readings beside the router and a details section, all chosen under Customise
- Aim the antenna: live signal with a tone that rises as it improves
- History: signal, line ping and data over time
- Add-ons: install and update Keystone's router packages from the app, with beta versions if you want them
- Phone line: calls, texts, SIP phones, quiet hours, forwarding and recordings
- Passwall 1 support next to Passwall2
- Resuming a paused device no longer lifts its ban, and the other way round
- Backups, partition dumps and the older QModem page now use the same HTTPS certificate check as the rest of the app
