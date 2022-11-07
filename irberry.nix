{ pkgs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/installer/sd-card/sd-image-aarch64.nix>
  ];

  networking = {
    hostName = "irberry";
    wireless = {
      enable = true;
      networks = {
        # Set Wifi SSID and password with env vars "WIFI_SSID" and "WIFI_PSK"
        "${(builtins.getEnv "WIFI_SSID")}" = {
          psk = builtins.getEnv "WIFI_PSK";
        };
      };
    };
  };

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

  services.sshd.enable = true;

  services.lirc = {
    enable = true;
    options = "";
    configs = [
      ''
        begin remote

          name  DENON_RC1120_2
          bits           24
          flags SPACE_ENC
          eps            30
          aeps          100

          header       3444  1602
          one           491  1196
          zero          491   356
          ptrail        481
          pre_data_bits   24
          pre_data       0x2A4C02
          gap          74554
          min_repeat      4
          toggle_bit_mask 0x0

              begin codes
                  BTN_QUICK1               0x8248C8
                  BTN_QUICK2               0x8A48C0
                  BTN_QUICK3               0x8648CC
                  BTN_SPEAKERS             0x88840E
                  BTN_SLEEP                0x822CAC
                  SRC_IPOD                 0x8B34BD
                  SRC_SELECT               0x8AD45C
                  BTN_DYNEQ                0x8C44CA
                  BTN_DYNVOL               0x8844CE
                  BTN_MENU                 0x8C40CE
                  BTN_SEARCH               0x8EBC30
                  BTN_RETURN               0x8440C6
                  BTN_DST                  0x88C842
                  BTN_RESTORER             0x8244C4
              end codes

        end remote
      ''
    ];
  };

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
