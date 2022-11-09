# irberry

NixOS configuration for a Raspberry Pi 3 IR transmitter controllable using MQTT.

## Build

### Prerequisites

The following instructions are specific to NixOS. It might be possible to build it on other platforms (as long as they have `nix` installed) but I haven't tried.

You should emulate aarch64 rather than cross-compiling it. Emulation will allow you to use NixOS's binary cache, which is much faster than compiling everything. Add the following options to your system's `configuration.nix` (and run `nixos-rebuild switch` afterwards):

```nix
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
nix.settings.extra-platforms = [ "aarch64-linux" "arm-linux" ];
```

### Configuration

Wifi credentials are configured using the following environment variables:

* `WIFI_SSID`
* `WIFI_PSK`

The `.envrc` in this repo configures direnv to read `.env`. Add a `.env` file that looks like this:

```shell
WIFI_SSID="..."
WIFI_PSK="..."
```

These credentials will be set as global environment variables in the resulting NixOS installation. The build will fail if they are unset.

### Installation

1. Build the sd card image by running

  ```shell
  make
  ```

2. Install the image on a SD card

  ```shell
  sudo dd if=./result/sd-image/nixos-sd-image-irberry.img of=/dev/sda bs=4096 conv=fsync
  ```

3. Put the SD card into the raspberry pi and start it up!

4. It'll take a minute or two for it to start, but once it's up and running change the password

  ```shell
  # initial password is 'changeme'
  ssh matt@<ip-address>
  passwd
  ```

5. The raspberry pi should now be connected to the MQTT broker and sending IR signals when commands are sent to the topic `irberry/button`!

### Updating an existing installation

1. `ssh` into the raspberry pi

  ```shell
  ssh matt@<ip-address>
  ```

2. Update nix channels

  ```shell
  sudo nix-channel --update
  ```

3. Run `nixos-rebuild switch`, but be sure to open a root shell so the environment variables are set properly

  ```shell
  sudo bash
  nixos-rebuild switch
  ```
