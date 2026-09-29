# Export selected MIDI items as individual MIDI files

This REAPER script allows you to export multiple selected MIDI items at once, with each item saved as an individual MIDI file.

Particularly useful for saving collections of **drum grooves, fills, patterns**, etc.

## Features

* One `.mid` file per selected MIDI item
* The beginning of each item becomes the beginning of the MIDI file
* The duration in beats is added at the beginning of the filename
* **The filename is based on the name of the MIDI item**
* A folder browser is used to select the destination folder
* Existing files are never overwritten

## Requirements

* REAPER
* [js_ReaScriptAPI](https://forum.cockos.com/showthread.php?t=212174)

## Installation

Download **`Export selected MIDI items as individual MIDI files.lua`** from this GitHub repository.

Place the `.lua` file in REAPER's **Scripts** folder, then load it into REAPER using:

**Actions → Show action list → ReaScript → Load**

## Platforms

**Windows / macOS / Linux**

Tested on **Windows**.

macOS and Linux should also be supported, but have not yet been tested.
