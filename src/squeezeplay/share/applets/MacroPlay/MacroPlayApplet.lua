
--[[
=head1 NAME

applets.MacroPlay.MarcoPlayApplet - applet to play ui sequences for testing.

=head1 DESCRIPTION

This applet will play ui sequences using a lua script for testing.

=cut
--]]


-- stuff we use
local assert, getfenv, loadfile, ipairs, package, pairs, require, setfenv, setmetatable, tostring, type, unpack = assert, getfenv, loadfile, ipairs, package, pairs, require, setfenv, setmetatable, tostring, type, unpack

local oo               = require("loop.simple")
local io               = require("io")
local os               = require("os")
local lfs              = require("lfs")
local math             = require("math")
local string           = require("string")
local table            = require("jive.utils.table")
local dumper           = require("jive.utils.dumper")

local Applet           = require("jive.Applet")
local Event            = require("jive.ui.Event")
local Framework        = require("jive.ui.Framework")
local Icon             = require("jive.ui.Icon")
local Menu             = require("jive.ui.Menu")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Surface          = require("jive.ui.Surface")
local Task             = require("jive.ui.Task")
local Textarea         = require("jive.ui.Textarea")
local Timer            = require("jive.ui.Timer")
local Window           = require("jive.ui.Window")

local debug            = require("jive.utils.debug")
local log              = require("jive.utils.log").logger("applets.misc")

local LAYER_CONTENT    = jive.ui.LAYER_CONTENT
local LAYER_FRAME      = jive.ui.LAYER_FRAME

local jive = jive


module(..., Framework.constants)
oo.class(_M, Applet)


-- macro (global) state
local instance = false


function init(self)
	self.config = {}
	self:loadConfig()
end


local function loadmacro(file)
	for dir in package.path:gmatch("([^;]*)%?[^;]*;") do
		local filepath = dir .. file

		if lfs.attributes(filepath, "mode") == "file" then
			local f, err = loadfile(filepath)
			if err == nil then
				-- Set chunk environment to be contained in the
				-- MacroPlay applet.
				setfenv(f, getfenv(1))
				return f, string.match(filepath, "(.*[/\]).+")
			else
				return nil, err
			end
		end
	end

	return nil
end


function loadConfig(self)
	-- Load macro configuration
	local f, dirorerr = loadmacro("Macros.lua")
	if f then
		self.configFile = dirorerr .. "Macros.lua"
		self.config = f()
	else
		log:warn("Error loading Macros: ", dirorerr)
	end
end


function saveConfig(self)
	local file = assert(io.open(self.configFile, "w"))
	file:write(dumper.dump(self.config, nil, false))
	file:close()
end


function autoplayShow(self, countdown)
	-- Create window
	local window = Window("window", self:string("MACRO_AUTOSTART"))
	local menu = SimpleMenu("menu", items)
	local help = Textarea("textarea", "")

	window:addWidget(help)
	window:addWidget(menu)

	menu:addItem({
		text = self:string("MACRO_START"),
		sound = "WINDOWSHOW",
		callback = function(event, menuItem)
			if self.config.auto == false then
				self:autoplayReset()
			end

			window:hide()
			self:autoplay()
		end,
	})
	menu:addItem({
		text = self:string("MACRO_CANCEL"),
		sound = "WINDOWSHOW",
		callback = function(event, menuItem)
			window:hide()
		end,
	})

	for i, key in ipairs(self.config.autostart) do
		local macro = self.config.macros[key]

		local item = {
			text = self:string(macro.name),
			sound = "BUMP",
		}

		if macro.passed then
			item.icon = Icon("macroPass")
		end
		if macro.failed then
			item.icon = Icon("macroFail")
		end

		menu:addItem(item)
	end

	if self.config.auto > #self.config.autostart then
		-- test finished
		self.config.auto = false
		self:saveConfig()

		help:setValue(self:string("MACRO_AUTOSTART_COMPLETE"))
	else
		-- countdown to tests
		local timer = countdown or 20
		help:setValue(self:string("MACRO_AUTOSTART_HELP", timer))

		window:addTimer(1000,
				function()
					if timer == 1 then
						window:hide()
						self:autoplay()
					end

					timer = timer - 1
					help:setValue(self:string("MACRO_AUTOSTART_HELP", timer))
				end)
	end

	window:setAllowScreensaver(false)
	window:setAlwaysOnTop(true)
	window:setAutoHide(false)

	window:show()
end


function settingsShow(self)
	-- Create window
	local window = Window("window", self:string("MACRO_PLAY"))
	local menu = SimpleMenu("menu", items)
	local help = Textarea("help", "")

	menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)

	window:addWidget(help)
	window:addWidget(menu)

	-- Macro menus
	if self.config.autostart then
		local item = {
			text = self:string("MACRO_AUTOPLAY"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:autoplayReset()
				self:autoplayShow()
			end,
			focusGained = function()
				help:setValue(self:string("MACRO_AUTOPLAY_HELP"))
			end,
			weight = 1,
		}
		menu:addItem(item)
	end

	for key, macro in pairs(self.config.macros) do
		local item = {
			text = self:string(macro.name),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self.config.auto = false
				self:play(macro)
			end,
			focusGained = function()
				help:setValue(macro.desc)
			end,
			weight = 5,
		}

		menu:addItem(item)
	end

	-- FIXME can't tie applet due to global macro state
	window:show()
end


-- reset autoplay
function autoplayReset(self)
	self.config.auto = 1

	for key, macro in pairs(self.config.macros) do
		macro.passed = nil
		macro.failed = nil
	end
end


-- play the next autostart macro
function autoplay(self)
	local config = self.config

	if config.auto == false then
		return
	end

	if config.auto > #config.autostart then
		log:info("Macro Autoplay FINISHED")
		config.auto = false

	else
		local macro = config.macros[config.autostart[config.auto]]
		config.auto = config.auto + 1

		self:play(macro)
	end

	self:saveConfig()
end


-- play the macro
function play(self, _macro)
	local task = Task("MacroPlay", self,
		function()
			local f, dirorerr = loadmacro(_macro.file)
			if f then
				self.macro = _macro
				self.macrodir = dirorerr

				instance = self

				log:info("Macro starting: ", _macro.file)
				f()

				if self.config.auto then
					self:autoplayShow(5)
				end
			else
				log:warn("Macro error: ", dirorerr)
			end
		end)
	task:addTask()

	self.timer = Timer(0, function()
				      task:addTask()
			      end, true)
end


-- delay macro for interval ms
function macroDelay(interval)
	local self = instance

	if interval then
		self.timer:restart(interval)
		Task:yield(false)
	end
end


-- dispatch ui event Event(...), and delay for interval ms
function macroEvent(interval, ...)
	local event = Event:new(...)

	log:info("macroEvent: ", event:tostring())

	Framework:pushEvent(event)
	macroDelay(interval)
end


-- returns the widgets of type class from the window
function _macroFindWidget(class)
	local window = Framework.windowStack[1]

	-- find widget
	local widget = {}
	window:iterate(function(w)
		if oo.instanceof(w, class) then
			widget[#widget + 1] = w
		end
	end)

	return unpack(widget)
end


-- returns the text of the selected menu item (or nil)
function macroGetMenuText()
	local menu = _macroFindWidget(Menu)
	if not menu then
		return
	end

	local item = menu:getSelectedItem()
	if not item then
		return
	end

	-- assumes Group with "text" widget
	return item:getWidget("text"):getValue()
end


-- select the menu item, using index
function macroSelectMenuIndex(interval, index)
	local menu = _macroFindWidget(Menu)
	if not menu then
		return
	end

	local ok = false

	local len = #menu:getItems()
	if index > len then
		return false
	end

	while menu:getSelectedIndex() ~= index do
		macroEvent(100, EVENT_KEY_PRESS, KEY_DOWN)
	end

	macroDelay(interval)
	return true
end


-- select the menu item, based on pattern. this uses key down events.
function macroSelectMenuItem(interval, pattern)
	local menu = _macroFindWidget(Menu)
	if not menu then
		return
	end

	local index = menu:getSelectedIndex() or 1

	local ok = false
	repeat
		if macroIsMenuItem(pattern) then
			ok = true
			break
		end

		macroEvent(100, EVENT_KEY_PRESS, KEY_DOWN)
	until menu:getSelectedIndex() == index

	macroDelay(interval)
	return ok
end


-- returns true if the menu item 'text' is selected
function macroIsMenuItem(pattern)
	local menuText = macroGetMenuText()

	log:info("macroIsMenuItem ", menuText, "==", pattern)

	return string.match(tostring(menuText), pattern)
end


-- force return to the home menu
function macroHome(interval)
	log:info("macroHome")
	if #Framework.windowStack > 1 then
		Framework.windowStack[#Framework.windowStack - 1]:hideToTop()
	end

	macroDelay(interval)
end


-- capture or verify a screenshot
function macroScreenshot(interval, file, limit)
	local self = instance
	local pass = false

	limit = limit or 100

	-- create screenshot
	local w, h = Framework:getScreenSize()

	local window = Framework.windowStack[1]

	local screen = Surface:newRGB(w, h)
	window:draw(screen, LAYER_FRAME | LAYER_CONTENT)

	local reffile = self.macrodir .. file .. ".bmp"
	if lfs.attributes(reffile, "mode") == "file" then
		-- verify screenshot
		log:debug("Loading reference screenshot " .. reffile)
		local ref = Surface:loadImage(reffile)

		local match = ref:compare(screen, 0xFF00FF)

		if match < limit then
			-- failure
			log:warn("Macro Screenshot " .. file .. " FAILED match=" .. match .. " limt=" .. limit)
			failfile = self.macrodir .. file .. "_fail.bmp"
			screen:saveBMP(failfile)
		else
			log:info("Macro Screenshot " .. file .. " PASSED")
			pass = true
		end
	else
		log:debug("Saving reference screenshot " .. reffile)
		screen:saveBMP(reffile)
	end

	macroDelay(interval)
	return pass
end


function macroPass(msg)
	local self = instance

	log:warn("Macro PASS ", self.macro.name, ": ", msg)

	self.macro.passed = os.date()
	self.macro.failed = nil

	self:saveConfig()
end


function macroFail(msg)
	local self = instance

	log:warn("Macro FAIL ", self.macro.name, ": ", msg)

	self.macro.passed = nil
	self.macro.failed = os.date()

	self:saveConfig()
end


function skin(self, s)
	s.macroPass = {
		img = Surface:loadImage("applets/MacroPlay/pass.png")
	}
	s.macroFail = {
		img = Surface:loadImage("applets/MacroPlay/fail.png")
	}
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]
