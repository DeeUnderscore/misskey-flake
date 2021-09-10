{ config, lib, pkgs, misskey, ... }: 

with lib; 

let 
  cfg = config.services.misskey;
  settingsFormat = pkgs.formats.yaml {};
  generatedConfig = settingsFormat.generate "default.yml" cfg.settings;
in {
  options.services.misskey = {
    enable = mkEnableOption "misskey";

    package = mkOption {
      type = types.package;
      default = misskey;
      description = "Misskey package to use. By default, this is the flake's Misskey package.";
    };

    settings = mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;

        options = {
          url = mkOption { 
            type = types.str;
            example = "https://misskey.example.com/";
            description = "Base URL of the Misseky instance.";
          };

          port = mkOption {
            type = types.int;
            default = 3000;
            description = "Port the Misskey daemon will listen on.";
          };

          db = {
            host = mkOption {
              type = types.str;
              default = "127.0.0.1";
              description = "Postgresql host to connect to.";
            };

            port = mkOption {
              type = types.int;
              default = config.services.postgresql.port;
              description = "Port of the database to connect to.";
            };

            db = mkOption {
              type = types.str;
              default = "misskey";
              description = "Name of the database that Misskey will use.";
            };

            user = mkOption {
              type = types.str;
              default = "misskey";
              description = "Name of the database user.";
            };

            pass = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Password for connecting to the database. Will be stored in plain text
                in the Nix store; to avoid, use <option>database.passwordFile</option>
                instead.
              '';
            };
          };

          redis = {
            host = mkOption {
              type = types.str;
              default = "127.0.0.1";
              description = "Redis host to connect to.";
            };

            port = mkOption {
              type = types.int;
              default = config.services.redis.port;
              description = "Redis port to connect to.";
            };
          };

          id = mkOption {
            type = types.enum [ "aid" "meid" "ulid" "objectid" ];
            default = "aid";
            description = ''
              ID generation method. Should not tbe changed after database is initalized.
            '';
          };

          filesPath = mkOption {
            type = types.str;
            default = "/var/lib/misskey/files";
            description = "Path to the directory in which Misskey will store media files and uploads.";
          };
        };
      };

      default = { };

      description = ''
        Misskey configuration. See <link xlink:href="https://github.com/misskey-dev/misskey/blob/develop/.config/example.yml">
        for an example configuration. 
      '';
    };

    database = {
      # TODO: add a createLocally option, which would require working around 
      #       what seems to be a lack of peer auth support 

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/secrets/misskey-db-pass";
        description = ''
          A file containing the database password.
        '';
      };
    };

    redis = {
      createLocally = mkOption {
        type = types.bool;
        default = true;
        description = "Ensure Redis is running locally and use it.";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/secrets/misskey-db-pass";
        description = ''
          A file containing the redis password.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = (cfg.database.passwordFile != null || true);
        message = "Database password must be supplied either via settings.db.pass or database.passwordFile. Peer authentication is not supported.";
      }
    ];

    services.misskey.settings = 
         (optionalAttrs (cfg.database.passwordFile != null ) { db.pass = "@DATABASE_PASSWORD@"; })
      // (optionalAttrs (cfg.redis.passwordFile != null) { redis.pass = "@REDIS_PASSWORD@"; });


    users.users.misskey = {
      home = "/run/misskey";
      group = "misskey";
      isSystemUser = true;
      useDefaultShell = true;
    };

    users.groups.misskey = { };

    services.redis = optionalAttrs cfg.redis.createLocally  {
      enable = true;
    };

    systemd.tmpfiles.rules = [
      "d /run/misskey/    0750 misskey misskey - -"
      "d ${cfg.settings.filesPath}  0750 misskey misskey - -"
    ];

    systemd.services.misskey = {
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" "network.target" ];

      environment = {
        MISSKEY_CONFIG_DIR = "/run/misskey";
        NODE_ENV = "production";
      };

      preStart = ''
        install -m 750 ${generatedConfig} /run/misskey/default.yml
      '' + optionalString (cfg.database.passwordFile != null) ''
        ${pkgs.replace-secret}/bin/replace-secret '@DATABASE_PASSWORD@' "${cfg.database.passwordFile}" /run/misskey/default.yml
      '' + optionalString (cfg.redis.passwordFile != null) ''
        ${pkgs.replace-secret}/bin/replace-secret '@REDIS_PASSWORD@' "${cfg.redis.passwordFile}" /run/misskey/default.yml
      '' + ''
        ${misskey}/bin/misskey-migrate
      '';

      serviceConfig = {
        User = "misskey";
        Group = "misskey";

        WorkingDirectory = "${misskey}/libexec/misskey";
        ExecStart = "${misskey}/bin/misskey";
      };
    };
  };
}
