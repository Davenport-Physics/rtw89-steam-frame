# rtw89-steam-frame

Two small patches to the Linux `rtw89` Wi-Fi driver for the Steam Frame wireless
adapter (USB `28de:2432`, driver `rtw89_8852cu`), and a script that builds and
installs the patched driver.

Tested on one machine: Fedora 44, kernel `7.2.8-200.fc44.x86_64`.

## What it fixes

**The adapter resets every few seconds and never connects.**
The kernel log repeats `rtw89_hw_scan_offload failed ret -110` followed by
`reset SuperSpeed USB device`, and NetworkManager shows "The device could not
be configured". On this machine the adapter's USB 3 link dropped whenever it
transmitted on 2.4 GHz, which every Wi-Fi scan does. The headset link is on
6 GHz, so `disable_2ghz=Y` turns the 2.4 GHz channels off for this driver.
Resets went from about 25 a minute to none. See
[steam-for-linux#13643](https://github.com/ValveSoftware/steam-for-linux/issues/13643).

**The stream stutters and resets even with the headset close by.**
The headset advertises itself as a 6 GHz "very low power" access point and the
driver limits its own transmit power to match (about 2 dBm per chain here).
`reg6_pwr_override=1` makes the driver use the "low power indoor" table
instead. Transmit rate went from HE-MCS 4 on one stream to HE-MCS 5-9 on two.
See [SteamVR-for-Linux#965](https://github.com/ValveSoftware/SteamVR-for-Linux/issues/965).

## Install

```
./install.sh
```

Run it as your normal user. It downloads the rtw89 source matching your running
kernel from [gregkh/linux](https://github.com/gregkh/linux), applies
`patches/`, builds, and asks for sudo to copy the modules into
`/lib/modules/<kernel>/updates/rtw89` and write
`/etc/modprobe.d/rtw89-steam-frame.conf`. It then tells you to unplug the
adapter and prints the commands that load the new driver.

Needs `kernel-devel` for the running kernel, `gcc`, `make`, `patch`, `curl`
and `python3`. Secure Boot must be off; the module is unsigned.

Check that it took:

```
journalctl -k -b | grep -E 'disable_2ghz|reg6_pwr_override'
```

## After a kernel update

The modules are installed per kernel version. Boot the new kernel and run
`./install.sh` again.

## Uninstall

```
./install.sh --uninstall
```

## Options

Both are parameters of `rtw89_core`, set in
`/etc/modprobe.d/rtw89-steam-frame.conf`.

| Parameter | Values | Default |
|---|---|---|
| `disable_2ghz` | `Y` disables all 2.4 GHz channels | `N` |
| `reg6_pwr_override` | `-1` follow the access point, `0` VLP, `1` LPI, `2` SP | `-1` |

They apply to every rtw89 device in the machine, not only the Steam Frame
adapter.

## Disclaimer

This is not from Valve or Realtek. It replaces a kernel driver with one built
on your machine and was only tested on the system named above. It may not
build, load, or help on yours, and it comes with no warranty. A kernel module
can crash or hang the system. `reg6_pwr_override` raises transmit power; make
sure the setting you choose is legal where you are.

## License

GPL-2.0 OR BSD-3-Clause, the same as the rtw89 driver. See [LICENSE](LICENSE)
and [LICENSE.GPL-2.0](LICENSE.GPL-2.0).
