# CC Packager Drain

ComputerCraft program that empties Create 6 packager output chests into a Create Connected item silo, about 1–2 ticks after items arrive.

## Install

On the computer:

```
wget https://raw.githubusercontent.com/levisnakes/cc-packager-drain/main/packager_drain.lua startup.lua
```

## Setup

1. Put a wired modem on each packager output chest and on the item silo, and right-click each one so it turns red.
2. Connect them all to the computer with networking cable.
3. Reboot the computer.

It empties every chest or barrel on that network. Put any chest you want to keep in the `exclude` list at the top of the file. If you have more than one silo, set `silo` to the one it should fill.
