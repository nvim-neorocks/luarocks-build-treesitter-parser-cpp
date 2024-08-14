{self}: final: prev: let
  luaPackage-override = luaself: luaprev: {
    luarocks-build-treesitter-parser-cpp = luaself.callPackage ({
      buildLuarocksPackage,
      luaOlder,
      luafilesystem,
    }:
      buildLuarocksPackage {
        pname = "luarocks-build-treesitter-parser-cpp";
        version = "scm-1";
        knownRockspec = "${self}/luarocks-build-treesitter-parser-cpp-scm-1.rockspec";
        src = self;
        disabled = luaOlder "5.1";
        propagatedBuildInputs = [
          luafilesystem
        ];
      }) {};

    tree-sitter-norg = luaself.callPackage ({
      buildLuarocksPackage,
      fetchFromGitHub,
      luaOlder,
      luarocks-build-treesitter-parser-cpp,
    }:
      buildLuarocksPackage {
        pname = "tree-sitter-norg";
        version = "scm-1";
        knownRockspec = "${self}/fixtures/tree-sitter-norg-scm-1.rockspec";
        src = fetchFromGitHub {
          owner = "nvim-neorg";
          repo = "tree-sitter-norg";
          rev = "014073fe8016d1ac440c51d22c77e3765d8f6855";
          hash = "sha256-0wL3Pby7e4nbeVHCRfWwxZfEcAF9/s8e6Njva+lj+Rc=";
        };
        buildInputs = [
          final.libcxx
        ];
        propagatedBuildInputs = [
          luarocks-build-treesitter-parser-cpp
        ];
        disabled = luaOlder "5.1";
        fixupPhase = ''
          if [ ! -f $out/lib/lua/5.1/parser/norg.so ]; then
          echo "Build did not create parser/norg.so in the expected location"
          exit 1
          fi
          if [ -f $out/lib/lua/5.1/parser/norg.so.dSYM ]; then
          echo "Unwanted darwin debug symbols!"
          exit 1
          fi
        '';
      }) {};
  };
in {
  lua5_1 = prev.lua5_1.override {
    packageOverrides = luaPackage-override;
  };
  lua51Packages = final.lua5_1.pkgs;
}
