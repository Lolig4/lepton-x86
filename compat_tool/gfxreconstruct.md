# GFXReconstruct

Install gfxreconstruct-android-aarch64 via pacman or obtain `libVkLayer_gfxreconstruct.so` from the [gfxreconstruct](https://github.com/LunarG/gfxreconstruct/)
nightly builds or releases, then copy it to Lepton's Vulkan layers directory:

```
/usr/share/guestos/android/vendor/vulkan_layers/libVkLayer_gfxreconstruct.so
```

## GFXReconstruct with the dev container

Launch the APK with the gfxreconstruct layer enabled:

```
ENABLE_VULKAN_GFXRECONSTRUCT_LAYER=1 \
LEPTON_GFXRECON_CAPTURE_FILE='/sdcard/Download/gfxrecon_capture.gfxr' \
lepton start foo.apk
```

`LEPTON_GFXRECON_<OPTION>` is translated to the corresponding
`debug.gfxrecon.<option>` Android system property. Unprefixed `GFXRECON_*`
variables are not forwarded.

# GFXReconstruct for a game launched via steam:

Either navigate to the game and press the gear icon, choose "Properties" and edit
the launch options to contain

```
ENABLE_VULKAN_GFXRECONSTRUCT_LAYER=1 EnableFrameEndMarkers=1 %command%
```

Additional capture options such as `LEPTON_GFXRECON_CAPTURE_FRAMES=100-200` can
be added to the same launch-options line.

After the application exits, the `.gfxr` file can be found at
`~/.local/share/Steam/steamapps/compatdata/%appid%/external/`

Alternatively you can edit `localconfig.vdf`, see [renderdoc](renderdoc.md).
