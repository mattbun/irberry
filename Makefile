irberry:
	nix-build \
		'<nixpkgs/nixos>' \
		-A config.system.build.sdImage \
		--argstr system aarch64-linux \
		-I nixos-config="./configuration.nix"
