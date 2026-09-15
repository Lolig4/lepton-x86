# Introduction

**Lepton** is a tool for use with the Steam client which allows games which are exclusive to Android to run on the Linux operating system.  **Most users should use Lepton provided by the Steam Client itself.**

**Lepton** has made some design decisions that set it apart from other Android containerization projects:
  * **Lepton** runs as a non-root user without requiring any rootful setup or helpers.
  * Every process inside **Lepton** is running as the same non-root user.  There is no enforced isolation between apps, each app instead should run within its own Android container.
  * **Lepton** disables various Android services that are not required to run games possibly breaking compatibility with some applications.
  * **Lepton** is not designed for general Android use, instead opting to keep the bare minimum functionality required to launch into games.
  * **Lepton** caches various pieces of state to accelerate Android userspace boot time.
  * **Lepton** is intended to help game developers bring their VR Android games to the Steam Frame.  Other usecases are possible, but were not the focus of development and may lack polish.

**Lepton** also includes a variety of features designed to help game developers bring their VR Android games to **Steam**:
  * **Lepton** mounts various libraries from the host OS:
    * Graphics drivers (mesa, zink, etc...)
    * Steam/Steamworks libraries
    * Vulkan layers (foveated rendering injector, renderpass optimizer)
  * **Lepton** supports integration with various debuggers (`strace`, `gdb`, `lldb`, `renderdoc`, etc...) and profilers (`perfetto`).
  * **Lepton** hides the flatscreen window by default, but can show it if necessary for development

**Lepton** incorporates patches and components from the Waydroid, Anbox, Halium and Hybris projects in the building of the Android container root filesystem.
The Android root filesystem is therefore released under a GPL-3.0 license (see [LICENSE.AOSP.image](LICENSE.AOSP.image), while the compatibility tool itself is released under the MIT license, (see [LICENSE.lepton](LICENSE.lepton)).

# Repository layout

This repository is split between two pieces:

* `image`: This builds an Android root filesystem.  This root filesystem is the container image within which games are launched.

* `compat_tool`: This is the containerization tool that Steam invokes to launch a game within the image built previously. You can find more information about it in it's [readme](compat_tool/README.md)


