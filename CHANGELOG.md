# Changelog

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
