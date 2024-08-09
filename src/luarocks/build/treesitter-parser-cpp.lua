---@diagnostic disable: inject-field
local fs = require("luarocks.fs")
local dir = require("luarocks.dir")
local path = require("luarocks.path")
local builtin = require("luarocks.build.builtin")
local util = require("luarocks.util")
local cfg = require("luarocks.core.cfg")

local treesitter_parser = {}

---@class tree-sitter-parser-cpp.RockSpec
---@field name string
---@field version string
---@field build tree-sitter-parser-cpp.BuildSpec
---@field variables table

---@class tree-sitter-parser-cpp.BuildSpec
---@field type string

---@class TreeSitterRockSpec: tree-sitter-parser-cpp.RockSpec
---@field type fun():string
---@field build TreeSitterBuildSpec

---@class TreeSitterBuildSpec: tree-sitter-parser-cpp.BuildSpec
---@field lang string
---@field sources string[]
---@field parser? boolean
---@field libflags? string[]
---@field generate? boolean
---@field generate_from_json? boolean
---@field queries? table<string, string>

---@param rockspec table
---@param no_install boolean
function treesitter_parser.run(rockspec, no_install)
	assert(rockspec:type() == "rockspec")
	---@cast rockspec tree-sitter-parser-cpp.RockSpec
	assert(rockspec.build.type == "treesitter-parser-cpp")
	---@cast rockspec TreeSitterRockSpec

	local build = rockspec.build

	local build_parser = build.parser == nil or build.parser

	if build.generate and not fs.is_tool_available("tree-sitter", "tree-sitter CLI") then
		return nil,
			"'tree-sitter CLI' is not installed.\n" .. rockspec.name .. " requires the tree-sitter CLI to build.\n"
	end
	if build.generate then
		local js_runtime = os.getenv("TREE_SITTER_JS_RUNTIME") or "node"
		local js_runtime_name = js_runtime == "node" and "Node JS" or js_runtime
		if not fs.is_tool_available(js_runtime, js_runtime_name) then
			return nil,
				("'%s' is not installed.\n%s requires %s to build."):format(js_runtime, rockspec.name, js_runtime_name)
		end
	end
	if build.generate then
		local cmd
		cmd = { "tree-sitter", "generate", "--no-bindings" }
		local abi = os.getenv("TREE_SITTER_LANGUAGE_VERSION")
		if abi then
			table.insert(cmd, "--abi")
			table.insert(cmd, abi)
		end
		if build.generate_from_json then
			table.insert(cmd, "src/grammar.json")
		end
		util.printout("Generating tree-sitter sources...")
		local cmd_str = table.concat(cmd, " ")
		util.printout(cmd_str)
		if not fs.execute(cmd_str) then
			return nil, "Failed to generate tree-sitter grammar."
		end
		util.printout("Done.")
	end
	local incdirs = {}
	for _, source in ipairs(build.sources or {}) do
		local source_dir = source:match("(.-)%/")
		if dir then
			table.insert(incdirs, source_dir)
		end
	end
	if not rockspec.build.libflags then
		local prev = rockspec.variables.LIBFLAG
		rockspec.variables.LIBFLAG = prev .. (prev and #prev > 1 and " " or "") .. "-lstdc++"
	end
	if rockspec.build.libflags then
		rockspec.variables.LIBFLAG = table.concat(rockspec.build.libflags, " ")
	end
	if build.queries then
		if fs.is_dir("queries") then
			pcall(fs.delete, "queries")
		end
		fs.make_dir("queries")
		if not fs.exists("queries") then
			return nil, "Could not create directory: queries"
		end
		local queries_dir = dir.path("queries", build.lang)
		fs.make_dir(queries_dir)
		if not fs.exists(queries_dir) then
			return nil, "Could not create directory: " .. queries_dir
		end
		for name, content in pairs(build.queries) do
			local queries_file = fs.absolute_name(dir.path(queries_dir, name))
			local fd = io.open(queries_file, "w+")
			if not fd then
				return nil, "Could not open " .. queries_file .. " for writing"
			end
			fd:write(content)
			fd:close()
		end
		rockspec.build.copy_directories = rockspec.build.copy_directories or {}
		table.insert(rockspec.build.copy_directories, "queries")
	end
	rockspec.build.modules = {
		["parser." .. build.lang] = {
			sources = build.sources,
			incdirs = incdirs,
		},
	}
	local lib_dir = path.lib_dir(rockspec.name, rockspec.version)
	local parser_dir = dir.path(lib_dir, "parser")
	local ok, err
	if build_parser then
		local parser_lib = rockspec.build.lang .. "." .. cfg.lib_extension
		ok, err = builtin.run(rockspec, no_install)
		pcall(function()
			local dsym_file = dir.absolute_name(dir.path(parser_dir, parser_lib .. ".dSYM"))
			if fs.exists(dsym_file) then
				-- Try to remove macos debug symbols if they exist
				fs.delete(dsym_file)
			end
		end)
	else
		ok = true
	end
	if ok and fs.exists(parser_dir) then
		-- For neovim plugin managers that do not symlink parser_dir to the rtp
		local dest = dir.path(path.install_dir(rockspec.name, rockspec.version), "parser")
		fs.make_dir(dest)
		ok, err = fs.copy_contents(parser_dir, dest)
	end
	return ok, err
end

return treesitter_parser
