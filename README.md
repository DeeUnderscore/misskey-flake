# Nix Flake for Misskey

This is a [Nix](https://nixos.org/) [flake](https://nixos.wiki/wiki/Flakes) for [Misskey](https://join.misskey.page/en-US/). It can be used to deploy Misskey, a decentralized, ActivityPub-based microblogging platform, on NixOS. 

This is an **unofficial effort**, not associated with the Misskey project. Please **do not report any issues** encountered when deploying Misskey via this method to the upstream Misskey project. 

## Usage

### Import
To use the Misskey module provided by this flake, add this flake as an input to the flake.nix used for your system configurations, and then import `nixosModule` from it. 

For example, your flake.nix might look something like this:

```nix
{
  inputs = {
    misskey.url = "github:DeeUnderscore/misskey-flake";
  };

  outputs = {self, nixpkgs, misskey}: {
    nixosConfigurations.exampleBox = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./exampleBox/configuration.nix ];
      specialArgs = { 
          inherit misskey;
      };
    };
  };
}
```

Then, in your confiuguration.nix, you can import the module like so:

```nix
{ config, pkgs, misskey, ...}:
{
  imports = [
      misskey.nixosModule
  ];
}
```

### Settings 
For detailed options provided by the module, see the [module source file](./module/misskey.nix). There is currently no generated documentation.  

`services.misskey.settings` follows the [Misskey config file](https://github.com/misskey-dev/misskey/blob/develop/.config/example.yml) structure. 

### Database setup
The module supplied by the flake does not provide a `createLocally` option for the database. Additionally, there is no support for peer authentication, so you will most likely need to set a password for the Misskey user manually. 

To do this, add a Misskey user to your Postgresql configuration in your `configuration.nix`:

```nix
services.postgresql = {
    enable = true;
    authentication = ''
      host   misskey   misskey  127.0.0.1/32 password
    '';

    ensureDatabases = [
      "misskey"
    ];

    ensureUsers = [
      {
        name = "misskey";
        ensurePermissions."DATABASE misskey" = "ALL PRIVILEGES";
      }
    ];
  };
```

And then, imperatively:

```shellsession
$ sudo -u postgres psql 
postgres=# ALTER ROLE misskey WITH PASSWORD 'passwordGoesHere';
```


## License
The contents of this repository are available under the MIT license. See [LICENSE](./LICENSE) for full text.