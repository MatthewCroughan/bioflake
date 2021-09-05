{
  inputs =
  {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.05";
    dnas = {
      url = "gitlab:gh0stl1ne/DNASrep/00c6eed3";
      flake = false;
    };
    bioserver1 = {
      url = "gitlab:gh0stl1ne/Bioserver1/fcdfdb52";
      flake = false;
    };
    bioserver2 = {
      url = "gitlab:gh0stl1ne/Bioserver2/a2b5d7f2";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, dnas, bioserver1, bioserver2 }:
    let
      # Generate a user-friendly version numer.
      version = builtins.substring 0 8 self.lastModifiedDate;
      # System types to support.
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" ];
      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });
    in
    {
      overlay = final: prev: {
        bioApache = final.apache.override { openssl = final.openssl_1_0_2; };
        bioserver2 = final.bioserver1.overrideAttrs ( old: { src = bioserver2; name = "bioserver2"; });
        bioserver1 = final.stdenv.mkDerivation rec {
          name = "bioserver1";
          src = bioserver1;
          nativeBuildInputs = with final; [ makeWrapper jdk8 ];
          buildPhase = ''
            javac bioserver/*.java -cp ${final.mysql_jdbc}/share/java/mysql-connector-java.jar
            touch -t 197001010000.01 bioserver/*.class
            jar cfM ${name}.jar bioserver/*.class
          '';
          installPhase = ''
            mkdir -p $out/bin
            mkdir -p $out/share/java
            cp ${name}.jar $out/share/java
            makeWrapper ${final.jdk8.jre}/bin/java $out/bin/${name} \
              --add-flags "-cp ${final.mysql_jdbc}/share/java/mysql-connector-java.jar:$out/share/java/${name}.jar" \
              --add-flags "bioserver.ServerMain"
          '';
        };
      };

      nixosModules.bioserver1 =
        { pkgs, lib, config, ... }:
          with lib;
        {
          options.services.bioserver1 = {
            enable = mkEnableOption "Run the Bioserver1 Service";
          };
          config = {
            nixpkgs.overlays = [ self.overlay ];
            systemd.services.bioserver1 = mkIf config.services.bioserver1.enable {
              description = "The Bioserver1 Service";
              wantedBy = [ "multi-user.target" ];
              after = [ "networking.target" ];
              serviceConfig = {
                DynamicUser = true;
                ExecStart = "${pkgs.bioserver1}/bin/bioserver1";
                PrivateTmp = true;
                Restart = "always";
              };
            };
          };
        };

      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system}) bioApache bioserver1 bioserver2;
        });

      defaultPackage = forAllSystems (system: self.packages.${system}.bioserver1);

    };
}
