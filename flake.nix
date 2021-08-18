{
  description = "Misskey, a decentralized microblogging platform";

  inputs.utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let 
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages.misskey = pkgs.callPackage ./pkg/default.nix { };

        defaultPackage = self.packages.${system}.misskey;
      }
    ) //
    {
      nixosModule = {pkgs, ...}@args: 
        import ./module/misskey.nix (args // 
          { misskey = self.packages.${pkgs.system}.misskey; });
    };
}
