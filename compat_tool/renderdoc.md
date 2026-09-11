# renderdoc

## Renderdoc with the dev container

In order to debug via renderdoc, launch a container with renderdoc debugging
enabled:

```
ENABLE_VULKAN_RENDERDOC_CAPTURE=1 EnableFrameEndMarkers=1 lepton start dev
```

Install an app on the device:

```
lepton install_app dev foo.apk
```

RDP to the device, e.g.:

```
rdesktop deviceip -g 1920x1080
```

Launch renderdoc in the RDP window (Launch button in the bottom left corner,
then type renderdoc).
On the renderdoc window, select the Lepton context in the bottom left corner,
select the app by navigating to "Launch Application" -> "Executable Path"
(three dots) and choose the app that was installed earlier, then launch it and
capture frames etc.

# Renderdoc for a game launched via steam:

Either navigate to the game and press the gear icon, choose "Properties" and edit
the launch options to contain

```
ENABLE_VULKAN_RENDERDOC_CAPTURE=1 EnableFrameEndMarkers=1 %command%
```

Alternatively you can perform these steps on the commandline

Stop steamvr:

```
steamvr stop
```

Open localconfig.vdf in an editor:

```
vim .local/share/Steam/userdata/*/config/localconfig.vdf
````

Edit the LaunchOptions for your game (look for it's id) to contain:

```
ENABLE_VULKAN_RENDERDOC_CAPTURE=1 EnableFrameEndMarkers=1 %command%
```

Then restart steamvr:

````
steamvr start
```

