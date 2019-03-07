# Build an rbe-compatible docker image with all the build-time dependencies of
# the given derivation included

nixpkgs:

let
  # Make the given path a concrete file instead of symlink so that we can
  # overwrite it if needed
  unSymLink = path: ''
    test -L ${path} && mv ${path} ${path}.old && cat ${path}.old > ${path} && rm ${path}.old
  '';

  # Dummy derivation which simply forwards all the buildInputs of the argument
  # and sets a wrapper to emulate a `nix-shell` on the argument
  depsWrapper = originalDrv: originalDrv.overrideAttrs (a: {
    phases = ["forwardDepsPhase"];
    forwardDepsPhase = ''
        mkdir -p $out/bin
        cp ${./entrypoint.py} $out/bin/entrypoint
        sed -i "s#env.json#$out/env.json#" $out/bin/entrypoint
        python ${./dump_env.py} > $out/env.json
        patchShebangs $out
      '';

      buildInputs = (a.buildInputs or []) ++ [nixpkgs.python];
    });


  # The base files needed for the shadow tools to work
  shadowEnv = nixpkgs.runCommand "shadowWithSetup" {} ''
    mkdir -p $out/etc/pam.d
    if [[ ! -f $out/etc/passwd ]]; then
     echo "root:x:0:0::/root:/bin/sh" > $out/etc/passwd
     echo "root:!x:::::::" > $out/etc/shadow
    fi
    if [[ ! -f $out/etc/group ]]; then
     echo "root:x:0:" > $out/etc/group
     echo "root:x::" > $out/etc/gshadow
    fi
    if [[ ! -f $out/etc/pam.d/other ]]; then
     cat > $out/etc/pam.d/other <<EOF
    account sufficient pam_unix.so
    auth sufficient pam_rootok.so
    password requisite pam_unix.so nullok sha512
    session required pam_unix.so
    EOF
    fi
    if [[ ! -f $out/etc/login.defs ]]; then
     touch $out/etc/login.defs
    fi

    mkdir -p $out/bin
    cat <<EOF > $out/bin/groupadd
    #!/bin/sh
    ${unSymLink "/etc/group"}
    ${unSymLink "/etc/gshadow"}
    exec ${nixpkgs.shadow}/bin/groupadd "\$@"
    EOF
    chmod +x $out/bin/groupadd

    cat <<EOF > $out/bin/useradd
    #!/bin/sh
    ${unSymLink "/etc/passwd"}
    ${unSymLink "/etc/shadow"}
    ${nixpkgs.shadow}/bin/useradd "\$@"
    # XXX Big hack: Give the right access to the bazel user
    chmod 755 /nix /nix/store
    EOF
    chmod +x $out/bin/useradd
  '';

  # Actual function for building the image
  buildRbeImage = drv:
    let buildEnv = depsWrapper drv; in
    nixpkgs.dockerTools.buildLayeredImage {
      name = "rbe-image";
      # We need a bit more than strictly the provided content of the image
      # because at least with the local docker sandbox, bazel layers a small
      # dockerfile on top of the given image and requires a few unix utilities
      # to be there.
      contents = [
        buildEnv
        nixpkgs.bash
        nixpkgs.coreutils
        shadowEnv
      ];
      maxLayers = 120;
      config = {
        Entrypoint = "${buildEnv}/bin/entrypoint";
        Cwd = buildEnv;
      };
    };
in
  buildRbeImage