--[[

    Typical use will be to create a new command-line alias for lua like
    this:

        alias ilua='rlwrap lua -l interactive'

]]--


local basic = require "basic_utils"

basic.global_import "basic_utils"
tp = basic.table_print
global_import "final"

function reload(mod)
    package.loaded[mod] = nil
    return require(mod)
end

function reload_import(mod)
    package.loaded[mod] = nil
    global_import(mod)
end
