# Debugging

Lepton publishes itself via mdns. This means if the adb server is started with mdns auto connect enabled you can find the lepton instance on your host via:

```
adb devices
```

without doing anything special. But in order for this to work you need to ensure that your adb server on your host was started with mdns auto connect enabled:

```
adb kill-server
ADB_MDNS_AUTO_CONNECT=adb adb start-server
```

Or on windows:

```
adb kill-server
set ADB_MDNS_AUTO_CONNECT=adb
adb start-server
```

On Arch Linux the package https://aur.archlinux.org/packages/android-sdk-platform-tools provides an adb server with the auto connect functionality built in.
But remember to specify the full path to adb, or add it to your PATH:

```
/opt/android-sdk/platform-tools/adb
```

## Debugging lepton

If your game is not starting properly and it seems to be an issue with lepton, you can turn on lepton debugging via the LEPTON_DEBUG environment variable, e.g.:

LEPTON_DEBUG=true lepton start instance_or_application_name

## gdb

Launch a game (from UI or commandline) and run:
```
lepton gdb_attach instance_or_application_name
```

Then debug.

If you need to debug an early application startup issue you can launch the container via:

```
LEPTON_DEBUG_LAUNCH=true lepton start application_name
```

And then attach from another shell:
```
lepton gdb_attach instance_or_application_name
```

Then set breakpoints etc.

If the default gdb port (1337 or higher, depending on the instance) conflicts with something, you can specify an arbitrary port via the ```LEPTON_GDB_PORT``` environment variable, e.g.:

```
LEPTON_GDB_PORT=12345 lepton start application_name
```

And attaching:
```
lepton gdb_attach instance_or_application_name
```

NOTE: Specifying the port when attaching is optional since lepton stores the port, however it can be useful if gdbserver was started manually through ```lepton attach```.

## strace

lepton has builtin strace functionality:

```
LEPTON_STRACE=true lepton start application_name
```

Will record a strace and as soon as the game is stopped or cancelled, the above command will print the location of the strace capture.
NOTE: This will automatically strace from the beginning of the application start, similarly as LEPTON_DEBUG_LAUNCH=true for gdb.

# Backtraces from crashes

To obtain human readable backtraces debuginfod can be used.
If the device is put into developer mode, debuginfos will be fetched from DEBUGINFOD_URLS.
For applications that have debuginfo packages available (e.g. renderdoc, install renderdoc-android-apks-debug), this will automatically show the source lines within the backtrace in the logcat crash buffer.
For other applications, if symbols and sources are available, debuginfos can be placed into a folder (e.g. foo) and the sources into .debuginfod_client_cache/BUILDID/source##filename.txt with "/" replaced by ## then debuginfo can be launched like this:

```
debuginfod -F -p 8181 -R /path/to/foo
```

An example layout would be this:
```
foo/libart.so
```

```
~/.debuginfod_client_cache/0e343b04f5ac382f24bde7aacff6007d/source##art##runtime##art_method.cc
```

The buildid can be obtained via:

```
eu-readelf -n foo/libart.so
```

And make sure to launch lepton like so:

```
DEBUGINFOD_URLS="http://host.containers.internal:8181 ${DEBUGINFOD_URLS}" lepton start dev
```

Or set the environment variable in the launch options.

## VSCode

For information on how to debug via vscode, check the [vscode](vscode.md) section.

