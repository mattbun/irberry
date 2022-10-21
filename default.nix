with import <nixpkgs> { };
mkShell {
  nativeBuildInputs = [
    mosquitto
    netcat
  ];
}
