rockspec_format = '3.0'

package = "tree-sitter-norg"

version = "scm-1"

source = {
  url = "git://github.com/tree-sitter/tree-sitter-norg",
}

description = {
  summary = "tree-sitter parser for norg",
  homepage = "https://github.com/tree-sitter/tree-sitter-norg",
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
  lang = "norg",
  sources = { "src/parser.c", "src/scanner.cc" },
}
