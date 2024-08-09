local _MODREV, _SPECREV = "scm", "-1"
rockspec_format = "3.0"
package = "luarocks-build-treesitter-parser-cpp"
version = _MODREV .. _SPECREV

dependencies = {
    "lua >= 5.1",
    "luafilesystem ~> 1",
}

test_dependencies = {
    "lua >= 5.1",
}

source = {
    url = "git://github.com/nvim-neorocks/" .. package,
}
