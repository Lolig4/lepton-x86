## perfetto

Find more information about perfetto on its homepage here: [perfetto](https://perfetto.dev)

After installing perfetto:

```
pacman -S perfetto perfetto-android
```

You can capture a perfetto trace via:

```
lepton perfetto instance_or_application_name
```

And you can open this trace file by copying the file printed by the last command to your machine and navigating your browser to:

[perfetto steamos cloud](https://deckard.pages.steamos.cloud/perfetto)

You can also specify a configuration via:

```
lepton perfetto --config=cfg instance_or_application_name
```

Currently supported values for ```cfg``` are ```system``` and ```gpu_only```.

### Capturing a trace via the perfetto webui

In order to use the perfetto webui we need to start and establish a connection to traced.
This can be acchieved using the following steps:

On the device:

Install the relevant packages:

```
pacman -S perfetto perfetto-android
```

Then start the container:

```
lepton start application_or_container_name
```

NOTE: If you use the dev container, make sure to install an application to trace.

And finally on your host execute:

```
ssh -L8037:localhost:8037 steamos@frame.local -N
```

or alternatively

```
adb forward tcpip:8037 tcpip:8037
```

but not both.

You can use these steps for containers other than ```dev``` as well.

Then nagivate to the perfetto WebUI as mentioned above and select or perform:
1) Record a trace
2) Linux
3) Steam Frame
You should NOT need to execute the instructions it suggests since we already
started the websocket and forwarded its port.
4) Select your device
5) Start tracing


