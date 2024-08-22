local fs = require("luarocks.fs")
local dir = require("luarocks.dir")
local path = require("luarocks.path")
local builtin = require("luarocks.build.builtin")
local util = require("luarocks.util")
local cfg = require("luarocks.core.cfg")
local deps = require("luarocks.deps")

local treesitter_parser = {}

---@alias luarocks.ExternalDependency table

---@class luarocks.RockSpec
---@field package string
---@field version string
---@field type fun(rockspec: luarocks.RockSpec):'rockspec'
---@field format_is_at_least fun(rockspec: luarocks.RockSpec, ver: string): boolean
---@field external_dependencies table<string, luarocks.ExternalDependency>

---@class tree-sitter-parser-cpp.RockSpec: luarocks.RockSpec
---@field name string
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
---@field generate? boolean
---@field generate_from_json? boolean
---@field queries? table<string, string>

--- Run a command displaying its execution on standard output.
---@return boolean success (exit with status code 0)
local function execute(...)
	io.stdout:write(table.concat({ ... }, " ") .. "\n")
	return fs.execute(...)
end

---@param external_dependencies table<string, luarocks.ExternalDependency>
---@param variables table<string,string>
---@return string[] | nil libs
---@return string[] | nil incdirs
---@return string[] | nil libdirs
local function autoextract_libs(external_dependencies, variables)
	if not external_dependencies then
		return nil, nil, nil
	end
	local libs = {}
	local incdirs = {}
	local libdirs = {}
	for name, data in pairs(external_dependencies) do
		if data.library then
			table.insert(libs, data.library)
			table.insert(incdirs, variables[name .. "_INCDIR"])
			table.insert(libdirs, variables[name .. "_LIBDIR"])
		end
	end
	return libs, incdirs, libdirs
end

---Driver function for the build back-end, based on `luarocks.builtin.run`
---@param rockspec tree-sitter-parser-cpp.RockSpec the loaded rockspec.
---@return boolean | nil success
---@return string | nil error_message
local function run(rockspec, no_install)
	assert(rockspec:type() == "rockspec")
	local compile_object, compile_library

	local build = rockspec.build
	local variables = rockspec.variables
	local checked_lua_h = false

	for _, var in ipairs({ "CC", "CXX", "CFLAGS", "CXXFLAGS", "LDFLAGS" }) do
		variables[var] = variables[var] or os.getenv(var) or ""
	end

	local function add_flags(extras, flag, flags)
		if flags then
			if type(flags) ~= "table" then
				flags = { tostring(flags) }
			end
			util.variable_substitutions(flags, variables)
			for _, v in ipairs(flags) do
				table.insert(extras, flag:format(v))
			end
		end
	end

	---@param source string
	---@return string cc compiler
	---@return string[] flags flags
	local function get_cc(source)
		if source:match("%.cc$") ~= nil or source:match("%.cpp$") ~= nil or source:match("%.cxx$") ~= nil then
			return variables.CXX or variables.CC, variables.CXXFLAGS or variables.CFLAGS
		else
			return variables.CC, variables.CFLAGS
		end
	end

	if cfg.is_platform("mingw32") then
		compile_object = function(object, source, defines, incdirs)
			local extras = {}
			add_flags(extras, "-D%s", defines)
			add_flags(extras, "-I%s", incdirs)
			extras[#extras + 1] = "-shared"
			local cc, flags = get_cc(source)
			return execute(cc .. " " .. flags, "-c", "-o", object, source, unpack(extras))
		end
		compile_library = function(library, objects, libraries, libdirs, name)
			local extras = { unpack(objects) }
			add_flags(extras, "-L%s", libdirs)
			add_flags(extras, "-l%s", libraries)
			extras[#extras + 1] = dir.path(variables.LUA_LIBDIR, variables.LUALIB)
			extras[#extras + 1] = "-l" .. (variables.MSVCRT or "m")
			extras[#extras + 1] = "-lstdc++"

			if variables.CXX:match("clang") ~= nil then
				local exported_name = name:gsub("%.", "_")
				exported_name = exported_name:match("^[^%-]+%-(.+)$") or exported_name
				extras[#extras + 1] = string.format("-Wl,-export:luaopen_%s", exported_name)
			else
				extras[#extras + 1] = "-l" .. (variables.MSVCRT or "m")
			end

			local ok = execute(
				variables.LD .. " " .. variables.LDFLAGS .. " " .. variables.LIBFLAG,
				"-o",
				library,
				unpack(extras)
			)
			return ok
		end
	elseif cfg.is_platform("win32") then
		compile_object = function(object, source, defines, incdirs)
			local extras = {}
			add_flags(extras, "-D%s", defines)
			add_flags(extras, "-I%s", incdirs)
			local cc, flags = get_cc(source)
			return execute(cc .. " " .. flags, "-c", "-Fo" .. object, source, unpack(extras))
		end
		compile_library = function(library, objects, libraries, libdirs, name)
			local extras = { unpack(objects) }
			add_flags(extras, "-libpath:%s", libdirs)
			add_flags(extras, "%s.lib", libraries)
			local basename = dir.base_name(library):gsub(".[^.]*$", "")
			local deffile = basename .. ".def"
			local def = io.open(dir.path(fs.current_dir(), deffile), "w+")
			if not def then
				return nil, "Could not open " .. deffile .. " for writing."
			end
			local exported_name = name:gsub("%.", "_")
			exported_name = exported_name:match("^[^%-]+%-(.+)$") or exported_name
			def:write("EXPORTS\n")
			def:write("luaopen_" .. exported_name .. "\n")
			def:close()
			local ok = execute(
				variables.LD,
				"-dll",
				"-def:" .. deffile,
				"-out:" .. library,
				dir.path(variables.LUA_LIBDIR, variables.LUALIB),
				unpack(extras)
			)
			local basedir = ""
			if name:find("%.") ~= nil then
				basedir = name:gsub("%.%w+$", "\\")
				basedir = basedir:gsub("%.", "\\")
			end
			local manifestfile = basedir .. basename .. ".dll.manifest"

			if ok and fs.exists(manifestfile) then
				ok = execute(
					variables.MT,
					"-manifest",
					manifestfile,
					"-outputresource:" .. basedir .. basename .. ".dll;2"
				)
			end
			return ok
		end
	else
		compile_object = function(object, source, defines, incdirs)
			local extras = {}
			add_flags(extras, "-D%s", defines)
			add_flags(extras, "-I%s", incdirs)
			if cfg.is_platform("macosx") then
				extras[#extras + 1] = "-bundle"
			else
				extras[#extras + 1] = "-shared"
			end
			local cc, flags = get_cc(source)
			return execute(cc .. " " .. flags, "-c", source, "-o", object, unpack(extras))
		end
		compile_library = function(library, objects, libraries, libdirs)
			local extras = { unpack(objects) }
			add_flags(extras, "-L%s", libdirs)
			if cfg.gcc_rpath then
				add_flags(extras, "-Wl,-rpath,%s", libdirs)
			end
			add_flags(extras, "-l%s", libraries)
			extras[#extras + 1] = "-lstdc++"
			return execute(
				variables.LD .. " " .. variables.LDFLAGS .. " " .. variables.LIBFLAG,
				"-o",
				library,
				unpack(extras)
			)
		end
	end

	local ok, err
	local lua_modules = {}
	local lib_modules = {}
	local luadir = path.lua_dir(rockspec.name, rockspec.version)
	local libdir = path.lib_dir(rockspec.name, rockspec.version)

	local autolibs, autoincdirs, autolibdirs = autoextract_libs(rockspec.external_dependencies, rockspec.variables)

	if not build.modules then
		if rockspec:format_is_at_least("3.0") then
			local install, copy_directories
			---@diagnostic disable-next-line: inject-field
			build.modules, install, copy_directories = builtin.autodetect_modules(autolibs, autoincdirs, autolibdirs)
			---@diagnostic disable-next-line: inject-field
			build.install = build.install or install
			---@diagnostic disable-next-line: inject-field
			build.copy_directories = build.copy_directories or copy_directories
		else
			return nil, "Missing build.modules table"
		end
	end

	local compile_temp_dir

	local mkdir_cache = {}
	local function cached_make_dir(name)
		if name == "" or mkdir_cache[name] then
			return true
		end
		mkdir_cache[name] = true
		return fs.make_dir(name)
	end

	for name, info in pairs(build.modules) do
		local moddir = path.module_to_path(name)
		if type(info) == "string" then
			local ext = info:match("%.([^.]+)$")
			if ext == "lua" then
				local filename = dir.base_name(info)
				if filename == "init.lua" and not name:match("%.init$") then
					moddir = path.module_to_path(name .. ".init")
				else
					local basename = name:match("([^.]+)$")
					filename = basename .. ".lua"
				end
				local dest = dir.path(luadir, moddir, filename)
				lua_modules[info] = dest
			else
				info = { info }
			end
		end
		if type(info) == "table" then
			if not checked_lua_h then
				ok, err = deps.check_lua_incdir(rockspec.variables)
				if not ok then
					return nil, err
				end

				if cfg.link_lua_explicitly then
					ok, err = deps.check_lua_libdir(rockspec.variables)
					if not ok then
						return nil, err
					end
				end
				checked_lua_h = true
			end
			local objects = {}
			local sources = info.sources
			if info[1] then
				sources = info
			end
			if type(sources) == "string" then
				sources = { sources }
			end
			if type(sources) ~= "table" then
				return nil, "error in rockspec: module '" .. name .. "' entry has no 'sources' list"
			end
			for _, source in ipairs(sources) do
				if type(source) ~= "string" then
					return nil, "error in rockspec: module '" .. name .. "' does not specify source correctly."
				end
				local object = source:gsub("%.[^.]*$", "." .. cfg.obj_extension)
				if not object then
					object = source .. "." .. cfg.obj_extension
				end
				ok = compile_object(object, source, info.defines, info.incdirs or autoincdirs)
				if not ok then
					return nil, "Failed compiling object " .. object
				end
				table.insert(objects, object)
			end

			if not compile_temp_dir then
				compile_temp_dir = fs.make_temp_dir("build-" .. rockspec.package .. "-" .. rockspec.version)
				util.schedule_function(fs.delete, compile_temp_dir)
			end

			local module_name = name:match("([^.]*)$") .. "." .. util.matchquote(cfg.lib_extension)
			if moddir ~= "" then
				module_name = dir.path(moddir, module_name)
			end

			local build_name = dir.path(compile_temp_dir, module_name)
			local build_dir = dir.dir_name(build_name)
			cached_make_dir(build_dir)

			lib_modules[build_name] = dir.path(libdir, module_name)
			ok = compile_library(build_name, objects, info.libraries, info.libdirs or autolibdirs, name)
			if not ok then
				return nil, "Failed compiling module " .. module_name
			end

			-- for backwards compatibility, try keeping a copy of the module
			-- in the old location (luasec-1.3.2-1 rockspec breaks otherwise)
			if cached_make_dir(dir.dir_name(module_name)) then
				fs.copy(build_name, module_name)
			end
		end
	end
	if not no_install then
		for _, mods in ipairs({ { tbl = lua_modules, perms = "read" }, { tbl = lib_modules, perms = "exec" } }) do
			for name, dest in pairs(mods.tbl) do
				cached_make_dir(dir.dir_name(dest))
				ok, err = fs.copy(name, dest, mods.perms)
				if not ok then
					return nil, "Failed installing " .. name .. " in " .. dest .. ": " .. err
				end
			end
		end
		if fs.is_dir("lua") then
			ok, err = fs.copy_contents("lua", luadir)
			if not ok then
				return nil, "Failed copying contents of 'lua' directory: " .. err
			end
		end
	end
	return true
end
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
		---@diagnostic disable-next-line: inject-field
		rockspec.build.copy_directories = rockspec.build.copy_directories or {}
		table.insert(rockspec.build.copy_directories, "queries")
	end
	---@diagnostic disable-next-line: inject-field
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
		ok, err = run(rockspec, no_install)
		pcall(function()
			local dsym_file = dir.absolute_name(dir.path(parser_dir, parser_lib .. ".dSYM"))
			if fs.exists(dsym_file) or fs.is_dir(dsym_file) then
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
		for _, src in pairs(fs.list_dir(parser_dir)) do
			if src:find("%.so$") ~= nil then
				fs.copy(dir.path(parser_dir, src), dest)
			end
		end
	end
	return ok, err
end

return treesitter_parser
