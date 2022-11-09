{ pkgs, config, lib, ... }:

let
  requireEnvVar = { name }:
    let envVarValue = builtins.getEnv "${name}"; in
    if envVarValue == "" then
      throw "Environment variable '${name}' is unset"
    else envVarValue;

  wifiSSID = requireEnvVar { name = "WIFI_SSID"; };
  wifiPSK = requireEnvVar { name = "WIFI_PSK"; };

  gpioPin = 24;

  mqttBrokerHost = "192.168.1.2";
  mqttBrokerPort = "1883";
  mqttTopic = "irberry/button";

  # These control what to do with the ACT (green) LED
  # For available options, run `cat /sys/class/leds/ACT/trigger` on the pi
  actTriggerDefault = "none";
  actTriggerActive = "default-on"; # when irsend is active
in
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
        "${wifiSSID}" = {
          psk = wifiPSK;
        };
      };
    };
  };

  # Add network credentials as environment variables so `nixos-rebuild switch` can be run on the pi
  environment.variables = {
    WIFI_SSID = wifiSSID;
    WIFI_PSK = wifiPSK;
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

  # TODO /dev/lirc0 isn't writable by lirc user
  systemd.services.lircd.serviceConfig.User = lib.mkForce "root";
  services.lirc = {
    enable = true;
    options = ''
      [lircd]
      device = /dev/lirc0
    '';
    configs = [
      ''
        # https://lirc.sourceforge.net/remotes/denon/RC-1120
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

  hardware = {
    deviceTree = {
      enable = true;
      overlays = [
        {
          name = "gpio-ir-tx";
          # https://github.com/raspberrypi/linux/blob/rpi-5.10.y/arch/arm/boot/dts/overlays/gpio-ir-tx-overlay.dts
          # ... but with 18 replaced with ${gpioPin} and brcm2835 replaced with brcm2837 (to match rpi3)
          dtsText = ''
            /dts-v1/;
            /plugin/;

            / {
              compatible = "brcm,bcm2837";

              fragment@0 {
                target = <&gpio>;
                __overlay__ {
                  gpio_ir_tx_pins: gpio_ir_tx_pins@12 {
                    brcm,pins = <${toString gpioPin}>;
                    brcm,function = <1>;	// out
                  };
                };
              };

              fragment@1 {
                target-path = "/";
                __overlay__ {
                  gpio_ir_tx: gpio-ir-transmitter@12 {
                    compatible = "gpio-ir-tx";
                    pinctrl-names = "default";
                    pinctrl-0 = <&gpio_ir_tx_pins>;
                    gpios = <&gpio ${toString gpioPin} 0>;
                  };
                };
              };

              __overrides__ {
                gpio_pin = <&gpio_ir_tx>, "gpios:4",           	// pin number
                     <&gpio_ir_tx>, "reg:0",
                     <&gpio_ir_tx_pins>, "brcm,pins:0",
                     <&gpio_ir_tx_pins>, "reg:0";
                invert = <&gpio_ir_tx>, "gpios:8";		// 1 = active low
              };
            };
          '';
        }
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    mosquitto
    netcat
  ];

  systemd.services.irberry = {
    description = "Subscribes to a MQTT topic and runs lirc commands on publish";
    preStart = ''
      ${pkgs.bash}/bin/bash -c '(while ! ${pkgs.netcat}/bin/nc -z -v -w1 ${mqttBrokerHost} ${mqttBrokerPort} 2>/dev/null;
      do echo "Waiting for MQTT broker to be available..."; sleep 2; done); sleep 2'
      echo "${actTriggerDefault}" > /sys/class/leds/ACT/trigger
    '';
    script = ''
      #!/bin/bash

      onPublish() {
        COMMAND="$1"
        echo "$COMMAND"

        # turn on ACT led
        echo "${actTriggerActive}" > /sys/class/leds/ACT/trigger

        if [[ "$COMMAND" = "BTN_QUICK1" ]]; then
          ${pkgs.lirc}/bin/irsend SEND_ONCE DENON_RC1120_2 BTN_QUICK1
        elif [[ "$COMMAND" = "BTN_QUICK2" ]]; then
          ${pkgs.lirc}/bin/irsend SEND_ONCE DENON_RC1120_2 BTN_QUICK2
        else
          echo "Unknown command"
        fi

        # turn off ACT led
        echo "${actTriggerDefault}" > /sys/class/leds/ACT/trigger
      }

      export -f onPublish

      ${pkgs.mosquitto}/bin/mosquitto_sub -h ${mqttBrokerHost} -p ${mqttBrokerPort} -t ${mqttTopic} | xargs -L1 ${pkgs.bash}/bin/bash -c 'onPublish "$@"' _
    '';
    wantedBy = [ "multi-user.target" ];
  };

  # Put a copy of this configuration in /etc/nixos
  environment.etc."nixos/configuration.nix" = {
    mode = "0660";
    gid = config.users.groups.wheel.gid;
    text = builtins.readFile (./. + "/configuration.nix");
  };

  # Periodically clean up old nix generations
  nix.gc.automatic = true;
  nix.gc.options = "--delete-older-than 90d";

  system.stateVersion = "22.05";
}
