# General usage information

* Most options support tab completion.

## Starting an application installed from steam (use tab completion):

```
lepton start application_or_container_name
```

* ```application_name``` is the application name as shown in steam.

* ```container_name``` can be ```dev```, which will launch a development instance.

* ```start``` can also be replaced with ```waitforexitandrun``` (which is a steam verb)

## Starting an application installed from steam that has multiple ```*.apk```'s:

```
lepton start application_name subapk.apk
```

If subapk.apk is not specified, the first one will be picked automatically.

## Starting and application based on filename:

```
lepton start app.apk
```

## Starting a debug container (internal debug option):

```
lepton start_early_debug
```

## Preparing a sysbake (in case the rootfs changed, mostly an internal option):

lepton sysbake

## Attaching to an instance (use tab completion):

```
lepton shell instance_or_application_name

lepton attach instance_or_application_name
```

## Run a command in an instance (use tab completion):

```
lepton exec instance_or_application_name command

lepton run instance_or_application_name command
```

* ```instance_or_application_name``` is typically ```steamlaunch-APPID```, the ```application_name``` or the ```*.apk``` filename.

## Stopping an instance:

```
lepton kill instance_or_application_name

lepton stop instance_or_application_name
```

## Stopping all instances:

```
lepton kill_all
```

## Cleaning an instance:

```
lepton cleanup instance_or_application_name
```

## Grabbing logs (logcat) from an instance:

```
lepton logcat instance_or_application_name
```

by default this will only print application specific logs unless there is no app running in which case everything is printed.
To always print everything use:

```
lepton logcat instance_or_application_name --full
```

Further arguments can be passed to androids logcat binary like so:

```
lepton logcat instance_or_application_name --full --arg1 --arg2 ...
```

## Installing an application in an instance:

```
lepton install_app instance_or_application_name /path/to/apk
```

* For example:

```
lepton install_app dev /path/to/apk
```

## Launching gdbserver in an instance:

```
lepton gdb_server instance_or_application_name
```

* NOTE: You can use lepton gdb_attach directly, it will execute gdbserver automatically.

## Launching lldbserver in an instance:

Make sure lldbserver is installed:
```
pacman -S lldb-server-android
```

```
lepton lldb_server instance_or_application_name
```

## Attaching to an application via lldb:

```
lepton lldb_attach instance_or_application_name
```

NOTE: After forwarding the lldb port, as listed by ```lepton ps```, to your host
machine, you can also debug from ```lldb``` there by executing:

```
lldb --one-line "gdb-remote localhost:PORT"
```

## Attaching to an application via gdb:

```
lepton gdb_attach instance_or_application_name
```

* NOTE: If the container was launched like this:

```
LEPTON_DEBUG_LAUNCH=true lepton start instance_or_application_name
```

Then lepton to wait until gdb is attached before launching the application which allows to debug early startup failures.

## Killing the gdbserver:

```
lepton kill_gdb_server instance_or_application_name
```

## Killing the lldbserver:

```
lepton kill_lldb_server instance_or_application_name
```

## Install tab completions (usually done automatically):

```
lepton install_completions
```

## Listing instances:

```
lepton ps

lepton list_containers
```

* Example output:

```
$ lepton ps

steamlaunch-APPID (INTERNAL_IP, adb on ADB_PORT, gdb on GDB_PORT, lldb on LLDB_PORT, packages: PACKAGE_NAME)
```

## Generating a bootchart

```
lepton bootchart
```

The command will print where the bootchart has been stored.
The bootchart can be visualized using the pybootchartgui instructions from:
[boot-times](https://source.android.com/docs/core/perf/boot-times)

## Starting Unreal VR Test 🐸 (test application):

```
lepton unreal_vr_test
```

## Extracting a file from an instance:

```
lepton extract instance_or_application_name /path/to/file
```

* Example:

```
$ lepton attach Unreal\ VR\ Test\ 🐸
$ echo foo > /data/test.txt
$ exit
$ lepton extract Unreal\ VR\ Test\ 🐸 /data/test.txt
$ cat /data/text.txt
foo
```

## Capture a perfetto trace (also see main perfetto section later):

* Launch the container

```
lepton start application_or_container_name
```

* To capture a trace:

```
lepton perfetto instance_or_application_name
```

## Grabbing various lepton related logs and details:

```
lepton collect_logs
```

* This will create a tarball containing some version info and various lepton related log files.

## Print details about an apk

```
lepton apk_info apkfilename.apk
```

This will print information like the name of the apk and the minimum sdk version etc.
