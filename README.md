# luarocks-build-treesitter-parser-cpp

A luarocks build backend for tree-sitter parsers written in C++. 

> [!WARNING]
>
> tree-sitter has dropped support for C++ scanners.
> This build backend is forked from [luarocks-build-treesitter-parser](https://github.com/nvim-neorocks/luarocks-build-treesitter-parser)
> with the aim of keeping C++ support.
> But it is recommended to switch to C, as this build backend
> may not work on all platforms.

The resulting parser libraries are installed to
`<luarocks-install-tree>/lib/lua/<lua-version>/parser`.

> [!IMPORTANT]
>
> The installed parsers are *not* lua modules, but they
> can be added to the `package.cpath`.

## Example rockspec

```lua
rockspec_format = '3.0'

package = "tree-sitter-LANG"

version = "scm-1"

source = {
  url = "https://github.com/tree-sitter/tree-sitter-LANG/archive/<REF>.zip",
  dir = 'tree-sitter-LANG-<REF>',
}
source = {
  url = "git://github.com/tree-sitter/tree-sitter-LANG",
}

description = {
  summary = "tree-sitter parser for LANG",
  homepage = "https://github.com/tree-sitter/tree-sitter-LANG",
  license = "MIT"
}

dependencies = {
  "lua >= 5.1",
}

build_dependencies = {
  "luarocks-build-treesitter-parser-cpp",
}

build = {

  type = "treesitter-parser-cpp",
 
  ---@type string (required) Name of the language, e.g. "norg".
  lang = "LANG",

  ---@type string[] parser source files.
  sources = { "src/parser.c", "src/scanner.cc" },

  ---@type boolean? (optional) Won't build the parser if `false`.
  parser = true,

  ---@type boolean? (optional) Must the sources be generated using the tree-sitter CLI?
  generate = true,

  --- Ignored if `generate` is false.
  ---@type boolean? (optional) Generate the sources from src/grammar.json?
  generate_from_json = false,

  --- Overwrites any existing queries with the embedded queries.
  --- Will add 'queries' to the rockspec's 'copy_directories' if set.
  ---@type table<string, string>? (optional)
  queries = {
        -- Will create a `queries/<lang>/highlights.scm`
        -- Note that the content should not be indented.
        ["highlights.scm"] = [==[
(signature
  name: (variable) @function)

(function
  name: (variable) @function)
]==],
  },

}
```

> [!TIP]
>
> You can find more examples in the [fixtures](./fixtures) directory.

## Usage with Neovim

Neovim searches for tree-sitter parsers in a `parser` directory
on the runtimepath (`:h rtp`).

Parsers installed with luarocks-build-treesitter-parser-cpp can be found
by creating a symlink to the `parser` directory in the install location
on the Neovim runtimepath.

