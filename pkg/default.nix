{ stdenv
, lib
, fetchFromGitHub
, runCommand
, vips
, nodejs
, nodePackages
, yarn
, python3
, pkg-config
, cypress
, ffmpeg }:
let
  yarn' = yarn.override { inherit nodejs; };
in stdenv.mkDerivation rec {
  pname = "misskey";
  version = "12.88.0";

  src = fetchFromGitHub {
    owner = "misskey-dev";
    repo = "misskey";
    rev = version; 
    sha256 = "sha256-SwWXX2o5M5w0eetrdxZwJliHyuM7Sv+5UYgHjdX9gGg=";
  };

  # large parts of this are lifted from pkgs/servers/code-server/default.nix in nixpkgs
  #
  # mkYarnPackage/yarn2nix would be an alternative here, but problems arise from
  # problems with resultions in Misskey's package.json 
  # (cf https://github.com/nix-community/yarn2nix/issues/136)
  
  yarnCache = stdenv.mkDerivation {
    name =  "${pname}-${version}-yarn-cache";
    inherit src;
    nativeBuildInputs = [ yarn' ];
    buildPhase = ''
      export HOME=$PWD

      yarn config --offline set yarn-offline-mirror $out
      yarn install --frozen-lockfile --ignore-scripts --ignore-platform \
        --ignore-engines
    '';

    dontInstall = true;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-90k1uYnMDpr116jZoomNClx2/0gfkwZXHsbG6nSeEDo=";
  };

  # this allows figuring out the yarnCache outputHash by running
  # `nix build .#misskey.prefetchYarnCache`
  passthru = {
    prefetchYarnCache = lib.overrideDerivation yarnCache (d: {
      outputHash = lib.fakeHash;
    });
  };

  nodeSources = runCommand "node-sources" {} ''
    tar --no-same-owner --no-same-permissions -xf ${nodejs.src}
    mv node-* $out
  '';


  buildInputs = [ 
    ffmpeg 
    vips # required by sharp
  ];

  nativeBuildInputs = [ 
    yarn'
    nodejs
    nodePackages.node-gyp-build
    python3
    pkg-config
  ];

  checkInputs = [
    cypress
  ];

  patches = [
    # Allow setting the config directory via the env variable MISSKEY_CONFIG_DIR
    ./allow-setting-config-dir.patch
    # Allow setting path to the directory where files are stored via default.yml
    ./allow-setting-files-path.patch
  ];

  configurePhase = ''
    export HOME=$PWD
    echo '--install.offline true' >> .yarnrc

    # set nodedir to stop diskusage from trying to download node headers
    npm config set nodedir "${nodeSources}"

    # suppress the Cypress package trying to download the Cypress app 
    export CYPRESS_INSTALL_BINARY=0

    yarn --offline config set yarn-offline-mirror "${yarnCache}"
  '';

  buildPhase = ''
    yarn --offline --frozen-lockfile install

    patchShebangs . 

    NODE_ENV=production yarn --offline build
  '';

  installPhase = ''
    mkdir -p $out/libexec/misskey $out/bin

    cp -R built locales migration assets $out/libexec/misskey
    cp index.js package.json yarn.lock \
      ormconfig.js CHANGELOG.md \
      $out/libexec/misskey

    yarn --offline --cwd $out/libexec/misskey --production

    cat <<EOF > $out/bin/misskey
    #!/bin/sh
    exec ${nodejs}/bin/node $out/libexec/misskey/index.js
    EOF
    chmod +x $out/bin/misskey

    cat <<EOF > $out/bin/misskey-migrate
    #!/bin/sh
    exec $out/libexec/misskey/node_modules/.bin/ts-node \
      $out/libexec/misskey/node_modules/typeorm/cli.js migration:run
    EOF
    chmod +x $out/bin/misskey-migrate

  '';

  meta = with lib; {
    description = "Microblogging platform server";
    homepage = "https://join.misskey.page";
    license = licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}