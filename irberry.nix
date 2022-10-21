{ pkgs, ... }:

{
  networking.hostName = "irberry";

  sdImage = {
    compressImage = false;
    imageName = "nixos-sd-image-irberry.img";
  };

  users.users.matt = {
    isNormalUser = true;
    home = "/home/matt";
    extraGroups = [ "wheel" ];
    initialPassword = "changeme";
  };

  services = {
    sshd.enable = true;
  };

  # TODO set up lirc
  boot.loader.raspberryPi.firmwareConfig = ''
    dtoverlay=gpio-ir-tx,gpio_pin=24
  '';

  environment.systemPackages = with pkgs; [
    mosquitto
    netcat
  ];

  systemd.user.services.irberry = {
    description = "Subscribes to a MQTT topic and runs lirc commands on publish";
    preStart = ''
      /run/current-system/sw/bin/bash -c '(while ! /run/current-system/sw/bin/nc -z -v -w1 192.168.1.2 1883 2>/dev/null; do echo "Waiting for MQTT broker to be available..."; sleep 2; done); sleep 2'
    '';
    script = ''
      #!/bin/bash

      onPublish() {
        COMMAND="$1"

        if [[ "$COMMAND" = "BTN_QUICK1" ]]; then
          echo "1"
        elif [[ "$COMMAND" = "BTN_QUICK2" ]]; then
          echo "2"
        else
          echo "what"
        fi
      }

      export -f onPublish

      mosquitto_sub -h 192.168.1.2 -t irberry/button | xargs -L1 bash -c 'onPublish "$@"' _
    '';
    wantedBy = [ "multi-user.target" ];
  };

  system.copySystemConfiguration = true;

  # Periodically clean up old nix generations
  nix.gc.automatic = true;
  nix.gc.options = "--delete-older-than 90d";

  system.stateVersion = "22.05";
}
