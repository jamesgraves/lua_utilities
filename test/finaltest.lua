#!/usr/bin/env lua
for k,v in pairs(require "final") do _G[k] = v end

print"-- Finalize on error"
do
	local function add5(x)
		finally(print, "W")
		finally(false, print, x)
		finally(false, print, "Y")
		finally(true, print, "Z")
		return x + 5
	end

	fcall(add5,5)
	assert(not fcall(add5), "Error expected")
	print"OK"
end

print"-- Redirected output"
do
	local function with_output(f, func, ...)
		finally(io.output, io.output())
		io.output(f)
		return func(...)
	end

	local f = io.tmpfile()
	local s = "test redirect"
	fcall(with_output, f,io.write,s)
	io.write"Display\n"
	f:seek("set")
	assert(f:read("*a") == s)
	f:close()
	print"OK"
end

print"-- Manually finalized block"
do
	local nproc = 2

	local obj = {v = 0}
	function obj:close(e)
		assert(not e or e == self, "Error object expected")
		self.v = self.v + 1
	end

	local function block()
		for i = 1, nproc do
			local fin = finally(obj)
			if i == nproc then error(obj) end
			finalize(fin)
		end
	end

	fcall(block)
	assert(obj.v == nproc, "Object not processed: "..obj.v)
	print"OK"
end

print"-- Tail call"
do
	local nproc = 2

	local obj = {v = ""}
	function obj:close() self.v = self.v .. "c" end

	local i = nproc

	local function tail()
		finally(obj)
		obj.v = obj.v .. "p"
		i = i - 1
		if i > 0 then return tail() end
	end

	fcall(tail)
	assert(obj.v == string.rep("p",nproc)..string.rep("c",nproc))
	print"OK"
end

print"-- Transaction"
do
	local str = ""

	local function undo(step)
		str = str .. step
	end

	local function transact()
		local f = "Foo"
		finally(false, undo, f)

		local b = "Bar"
		finally(false, undo, b)

		local d = error("Def")

		return print(f, b, d)
	end

	fcall(transact)
	assert(str == "BarFoo", "Failure expected")
	print"OK"
end

print"-- Coroutine"
do
	local function foo(x)
		finally(print, x)
		coroutine.yield()
		finally(false, print, "F")
		finally(true, print, "T")
		error"on failure"
	end

	local co = coroutine.create(function() fcall(foo) end)
	coroutine.resume(co, "Z")
	coroutine.resume(co)
	print"OK"
end

print"-- GC'ed coroutine"
do
	local g

	local function foo()
		finally(function() g = true end)
		coroutine.yield()
	end

	local co = coroutine.create(function() fcall(foo) end)
	coroutine.resume(co)
	-- force GC
	co = nil
	collectgarbage("collect")
	assert(g, "Not finalized")
	print"OK"
end
