--[[
 - Finalizer module for Lua
 - Copyright (C) 2011 Tom N Harris. All rights reserved.
 -
 -  This software is provided 'as-is', without any express or implied
 -  warranty.  In no event will the authors be held liable for any damages
 -  arising from the use of this software.
 -
 -  Permission is granted to anyone to use this software for any purpose,
 -  including commercial applications, and to alter it and redistribute it
 -  freely, subject to the following restrictions:
 -
 -  1. This notice may not be removed or altered from any source distribution.
 -  2. Neither the names of the authors nor the names of any of the software 
 -     contributors may be used to endorse or promote products derived from 
 -     this software without specific prior written permission.
 -]]
local debug = require"debug"
local getinfo,getlocal = debug.getinfo,debug.getlocal
local setmetatable,getmetatable = setmetatable,getmetatable
local select,pcall,ipairs,assert,error = select,pcall,ipairs,assert,error
local unpack = unpack or table.unpack
local tinsert = table.insert
local pack = table.pack or function (...)
  local t = {...}
  t.n = select('#',...)
  return t
end
local function call(fn,...) return fn(...) end
local _newproxy,newproxy = newproxy
if _newproxy then
  newproxy = function(gc)
    local proxy = newproxy(1)
    getmetatable(proxy).__gc = gc
    return proxy
  end
else
  newproxy = function(gc)
    return setmetatable({},{__gc=gc})
  end
end

--[[ do_final - run finalizers down to a certain level.
  stack - finalizer stack from the function environment
  level - stack index to restore
  is_err - optional error object. If not nil, it is passed as an extra argument to the finalizer
  prot - catch (and ignore) errors from the finalizers if true. 
  ]]
local function do_final(stack,level,err,prot)
  local caller = prot and pcall or call
  level = level or 0 -- default unroll completely
  for i=#stack,level,-1 do
    -- pop the finalizer
    local finalizer = stack[i]
    stack[i] = nil
    -- finalizer = { when, function, ... }
    -- when to call the finalizer
    local when = finalizer[1]
    if not err and (when==nil or when==true) then
      -- not an error, call untyped or on-success finalizers
      caller(unpack(finalizer,2,finalizer.n))
    elseif err and (when==nil or when==false) then
      -- an error occurred, call untyped or on-failure finalizers
      finalizer[finalizer.n+1] = err
      caller(unpack(finalizer,2,finalizer.n+1))
    end
  end
end

--[[ fcall - execute a function in an environment with a finalizer stack
  This creates a finalizer stack in the function environment then executes 
  the function in a protected environment. When the function exits, the 
  finalizers are called in reverse-order. If an error occurred, the finalizers 
  will get the error object as an extra argument.
  ]]
local function fcall(func, ...)
  -- finalizer stack
  local stack = {}
  -- if the coroutine is collected, this proxy will trigger finalizers, just in case
  local proxy=newproxy(function() do_final(stack,1,nil,true) end)
  -- set the environment then call the function
  local result = pack(pcall(func,...))
  -- result contains the success flag and returned values, or an error object
  local success = result[1]
  local err
  if not success then err = result[2] end
  -- unroll the finalizers. the error object will be nil when the call is successful
  do_final(stack, 1, err, true)
  -- return the same as pcall
  return unpack(result,1,result.n)
end

local function getfinalstack()
  -- skip first two functions
  local n = 3
  while true do
    local info = getinfo(n, 'f')
    if not info then break end
    if info.func == fcall then
      for i=2,5 do
        local var,stack = getlocal(n, 2)
        if var=="stack" then
          return stack
        end
      end
      break
    end
    n = n + 1
  end
  return nil
end

--[[ finally - add a finalizer function
  When used in an environment with a finalizer stack, the function and
  a list of arguments is pushed on the finalizer stack.
  when - (optional) `true' to only call the finalizer when the fcall exits 
         successfully, `false' to only call when there is an error
  finalizer - finalizer function to call. Can also be an object with a `close' method.
  ... - extra arguments for the function.
  ]]
local function finally(finalizer,...)
  local when,args
  -- find the finalizer stack
  local stack = assert(getfinalstack(), "no fcall on stack")
  -- if finalizer is `true' or `false' then the finalizer is the second argument
  if finalizer==true or finalizer==false then
    when,finalizer = finalizer,...
    args = pack(select(2,...))
  else
    args = pack(...)
  end
  -- call without any arguments to just return the current stack level
  if not finalizer then
    return #stack
  end
  if type(finalizer)~='function' then
    -- finalizer can be an object
    if type(finalizer.close)=='function' then
      -- emulate finalizer:close()
      tinsert(args,1,finalizer)
      args.n = args.n + 1
      finalizer = finalizer.close
    else
      -- object without a `close' method, try the `__gc' metamethod
      local mt = getmetatable(finalizer)
      if mt and type(mt.__gc)=='function' then
        tinsert(args,1,finalizer)
        args.n = args.n + 1
        finalizer = mt.__gc
      else
        error("finalizer is not a function", 2)
      end
    end
  end
  -- build the stack entry {when, finalizer, ... }
  tinsert(args,1,when)
  tinsert(args,2,finalizer)
  args.n = args.n + 2
  stack[#stack+1] = args
  return #stack
end

--[[ finalize - unroll finalizers to a certain stack level
  level - stack level of the last finalizer you want called.
  err - optional error object
  ]]
local function finalize(level,err)
  -- find the finalizer stack
  local stack = assert(getfinalstack(), "no fcall on stack")
  -- unroll the stack. finalizers are called unprotected
  do_final(stack, level, err)
end

return {
fcall = fcall,
finally = finally,
finalize = finalize
}
