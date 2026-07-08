# x86-memory-editor

A minimal Windows process memory read/write tool written in raw
**x86 NASM assembly**, every call goes straight to
the Windows API (`kernel32.dll`).

This was built purely for learning and personal development.

## What it does

Given a process ID, a memory address, and a value, it:

1. Opens the target process with `OpenProcess`
2. Writes a 4-byte value to the given address with `WriteProcessMemory`
3. Reads the same address back with `ReadProcessMemory` to verify the
   write actually landed
4. Prints the read-back value to the console

## Usage

```
x86-memory-editor.exe <PID> <hex_address> <value>
```

Example (writing 2400 to two related addresses)
These addresses modify health in the Resident Evil 4 (2005 UHD Steam) 1.0.6 executable
```
x86-memory-editor.exe 23424 0xC5BE94 2400
x86-memory-editor.exe 23424 0xC5BE96 2400
```
![image1](https://i.imgur.com/5kODdIZ.jpeg)


**Run as Administrator** — most processes will refuse `OpenProcess`
otherwise.

## Building

Requires [NASM](https://www.nasm.us/) and the MSVC linker (`link.exe`,
from the "Desktop development with C++" workload in Visual Studio).

## How it works

- **No CRT**: the entry point is `main`, called directly by the linker
  via `/entry:main` - there's no `_start`/CRT startup code, so no
  `printf`, `malloc`, etc. Console I/O uses `WriteConsoleA` directly.
- **Command-line parsing**: `GetCommandLineA` returns the raw command
  line as a string; the code manually skips the program name (handling
  the case where it's quoted) and then parses PID, address, and value
  by hand, including a small hand-written hex parser for the address.
- **stdcall name decoration**: 32-bit Windows import libraries export
  functions with decorated names like `_OpenProcess@12`, where the
  number is the total size (in bytes) of the arguments pushed on the
  stack. This is why `extern` declarations look like `_WriteProcessMemory@20`
  instead of the plain WinAPI name.
- **Verification step**: since `WriteProcessMemory` can succeed at the
  API level without necessarily reflecting a meaningful in-game change
  (wrong address, value cached elsewhere, anti-cheat interference,
  etc.), the program reads the address back immediately after writing
  and prints the result, so you can confirm the write actually took
  effect at that memory location.

## Disclaimer

This project is for educational purposes, learning WinAPI process
memory access and x86 assembly. Only use it on your own processes /
single-player games you own, on your own machine.
