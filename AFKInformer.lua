script_name('AFK Informer')
script_author("dmitriyewich")
script_description("With this simple script you will always know how long you have spent in AFK.")
script_url("https://vk.com/dmitriyewichmods")
script_dependencies("ffi","encoding", "memory", "vkeys", "mimgui", "lfs", "ziplib")
script_properties('work-in-pause', 'forced-reloading-only')
script_version("1.3")
script_version_number(03)

require "lib.moonloader"
script_properties('work-in-pause')
local dlstatus = require "moonloader".download_status
local lffi, ffi = pcall(require, 'ffi') assert(lffi, 'Library \'ffi\' not found.')
local lwinmm, winmm = pcall(ffi.load, ("Winmm")) assert(lwinmm, 'System library \'Winmm\' not found.')
local lmemory, memory = pcall(require, 'memory') assert(lmemory, 'Library \'memory\' not found.')
local limgui, imgui = pcall(require, 'mimgui') -- https://github.com/THE-FYP/mimgui
local lencoding, encoding = pcall(require, 'encoding') assert(lencoding, 'Library \'encoding\' not found.')
local llfs, lfs = pcall(require, 'lfs')
local lziplib, ziplib = pcall(ffi.load, string.format("%s/lib/ziplib.dll",getWorkingDirectory()))
local lvkeys, vkeys = pcall(require, 'vkeys')
assert(lvkeys, 'Library \'vkeys\' not found.') -- Библиотека с кодами клавиш в удобном формате
local lwm, wm = pcall(require, 'lib.windows.message')
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local new, str, sizeof = imgui.new, ffi.string, ffi.sizeof

local function isarray(t, emptyIsObject)
	if type(t)~='table' then return false end
	if not next(t) then return not emptyIsObject end
	local len = #t
	for k,_ in pairs(t) do
		if type(k)~='number' then
			return false
		else
			local _,frac = math.modf(k)
			if frac~=0 or k<1 or k>len then
				return false
			end
		end
	end
	return true
end

local function map(t,f)
	local r={}
	for i,v in ipairs(t) do r[i]=f(v) end
	return r
end

local keywords = {["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,["end"]=1,["false"]=1,["for"]=1,["function"]=1,["goto"]=1,["if"]=1,["in"]=1,["local"]=1,["nil"]=1,["not"]=1,["or"]=1,["repeat"]=1,["return"]=1,["then"]=1,["true"]=1,["until"]=1,["while"]=1}

local function neatJSON(value, opts)
	opts = opts or {}
	if opts.wrap==nil  then opts.wrap = 80 end
	if opts.wrap==true then opts.wrap = -1 end
	opts.indent         = opts.indent         or "  "
	opts.arrayPadding  = opts.arrayPadding  or opts.padding      or 0
	opts.objectPadding = opts.objectPadding or opts.padding      or 0
	opts.afterComma    = opts.afterComma    or opts.aroundComma  or 0
	opts.beforeComma   = opts.beforeComma   or opts.aroundComma  or 0
	opts.beforeColon   = opts.beforeColon   or opts.aroundColon  or 0
	opts.afterColon    = opts.afterColon    or opts.aroundColon  or 0
	opts.beforeColon1  = opts.beforeColon1  or opts.aroundColon1 or opts.beforeColon or 0
	opts.afterColon1   = opts.afterColon1   or opts.aroundColon1 or opts.afterColon  or 0
	opts.beforeColonN  = opts.beforeColonN  or opts.aroundColonN or opts.beforeColon or 0
	opts.afterColonN   = opts.afterColonN   or opts.aroundColonN or opts.afterColon  or 0

	local colon  = opts.lua and '=' or ':'
	local array  = opts.lua and {'{','}'} or {'[',']'}
	local apad   = string.rep(' ', opts.arrayPadding)
	local opad   = string.rep(' ', opts.objectPadding)
	local comma  = string.rep(' ',opts.beforeComma)..','..string.rep(' ',opts.afterComma)
	local colon1 = string.rep(' ',opts.beforeColon1)..colon..string.rep(' ',opts.afterColon1)
	local colonN = string.rep(' ',opts.beforeColonN)..colon..string.rep(' ',opts.afterColonN)

	local build
	local function rawBuild(o,indent)
		if o==nil then
			return indent..'null'
		else
			local kind = type(o)
			if kind=='number' then
				local _,frac = math.modf(o)
				return indent .. string.format( frac~=0 and opts.decimals and ('%.'..opts.decimals..'f') or '%g', o)
			elseif kind=='boolean' or kind=='nil' then
				return indent..tostring(o)
			elseif kind=='string' then
				return indent..string.format('%q', o):gsub('\\\n','\\n')
			elseif isarray(o, opts.emptyTablesAreObjects) then
				if #o==0 then return indent..array[1]..array[2] end
				local pieces = map(o, function(v) return build(v,'') end)
				local oneLine = indent..array[1]..apad..table.concat(pieces,comma)..apad..array[2]
				if opts.wrap==false or #oneLine<=opts.wrap then return oneLine end
				if opts.short then
					local indent2 = indent..' '..apad;
					pieces = map(o, function(v) return build(v,indent2) end)
					pieces[1] = pieces[1]:gsub(indent2,indent..array[1]..apad, 1)
					pieces[#pieces] = pieces[#pieces]..apad..array[2]
					return table.concat(pieces, ',\n')
				else
					local indent2 = indent..opts.indent
					return indent..array[1]..'\n'..table.concat(map(o, function(v) return build(v,indent2) end), ',\n')..'\n'..(opts.indentLast and indent2 or indent)..array[2]
				end
			elseif kind=='table' then
				if not next(o) then return indent..'{}' end

				local sortedKV = {}
				local sort = opts.sort or opts.sorted
				for k,v in pairs(o) do
					local kind = type(k)
					if kind=='string' or kind=='number' then
						sortedKV[#sortedKV+1] = {k,v}
						if sort==true then
							sortedKV[#sortedKV][3] = tostring(k)
						elseif type(sort)=='function' then
							sortedKV[#sortedKV][3] = sort(k,v,o)
						end
					end
				end
				if sort then table.sort(sortedKV, function(a,b) return a[3]<b[3] end) end
				local keyvals
				if opts.lua then
					keyvals=map(sortedKV, function(kv)
						if type(kv[1])=='string' and not keywords[kv[1]] and string.match(kv[1],'^[%a_][%w_]*$') then
							return string.format('%s%s%s',kv[1],colon1,build(kv[2],''))
						else
							return string.format('[%q]%s%s',kv[1],colon1,build(kv[2],''))
						end
					end)
				else
					keyvals=map(sortedKV, function(kv) return string.format('%q%s%s',kv[1],colon1,build(kv[2],'')) end)
				end
				keyvals=table.concat(keyvals, comma)
				local oneLine = indent.."{"..opad..keyvals..opad.."}"
				if opts.wrap==false or #oneLine<opts.wrap then return oneLine end
				if opts.short then
					keyvals = map(sortedKV, function(kv) return {indent..' '..opad..string.format('%q',kv[1]), kv[2]} end)
					keyvals[1][1] = keyvals[1][1]:gsub(indent..' ', indent..'{', 1)
					if opts.aligned then
						local longest = math.max(table.unpack(map(keyvals, function(kv) return #kv[1] end)))
						local padrt   = '%-'..longest..'s'
						for _,kv in ipairs(keyvals) do kv[1] = padrt:format(kv[1]) end
					end
					for i,kv in ipairs(keyvals) do
						local k,v = kv[1], kv[2]
						local indent2 = string.rep(' ',#(k..colonN))
						local oneLine = k..colonN..build(v,'')
						if opts.wrap==false or #oneLine<=opts.wrap or not v or type(v)~='table' then
							keyvals[i] = oneLine
						else
							keyvals[i] = k..colonN..build(v,indent2):gsub('^%s+','',1)
						end
					end
					return table.concat(keyvals, ',\n')..opad..'}'
				else
					local keyvals
					if opts.lua then
						keyvals=map(sortedKV, function(kv)
							if type(kv[1])=='string' and not keywords[kv[1]] and string.match(kv[1],'^[%a_][%w_]*$') then
								return {table.concat{indent,opts.indent,kv[1]}, kv[2]}
							else
								return {string.format('%s%s[%q]',indent,opts.indent,kv[1]), kv[2]}
							end
						end)
					else
						keyvals = {}
						for i,kv in ipairs(sortedKV) do
							keyvals[i] = {indent..opts.indent..string.format('%q',kv[1]), kv[2]}
						end
					end
					if opts.aligned then
						local longest = math.max(table.unpack(map(keyvals, function(kv) return #kv[1] end)))
						local padrt   = '%-'..longest..'s'
						for _,kv in ipairs(keyvals) do kv[1] = padrt:format(kv[1]) end
					end
					local indent2 = indent..opts.indent
					for i,kv in ipairs(keyvals) do
						local k,v = kv[1], kv[2]
						local oneLine = k..colonN..build(v,'')
						if opts.wrap==false or #oneLine<=opts.wrap or not v or type(v)~='table' then
							keyvals[i] = oneLine
						else
							keyvals[i] = k..colonN..build(v,indent2):gsub('^%s+','',1)
						end
					end
					return indent..'{\n'..table.concat(keyvals, ',\n')..'\n'..(opts.indentLast and indent2 or indent)..'}'
				end
			end
		end
	end

	local function memoize()
		local memo = setmetatable({},{_mode='k'})
		return function(o,indent)
			if o==nil then
				return indent..(opts.lua and 'nil' or 'null')
			elseif o~=o then
				return indent..(opts.lua and '0/0' or '"NaN"')
			elseif o==math.huge then
				return indent..(opts.lua and '1/0' or '9e9999')
			elseif o==-math.huge then
				return indent..(opts.lua and '-1/0' or '-9e9999')
			end
			local byIndent = memo[o]
			if not byIndent then
				byIndent = setmetatable({},{_mode='k'})
				memo[o] = byIndent
			end
			if not byIndent[indent] then
				byIndent[indent] = rawBuild(o,indent)
			end
			return byIndent[indent]
		end
	end

	build = memoize()
	return build(value,'')
end


function savejson(table, path)
    local f = io.open(path, "w")
    f:write(table)
    f:close()
end
function convertTableToJsonString(config)
    return (neatJSON(config, {sort = true, wrap = 40}))
end 
local config = {}

if doesFileExist("moonloader/config/AFK Informer.json") then
    local f = io.open("moonloader/config/AFK Informer.json")
    config = decodeJson(f:read("*a"))
    f:close()
else
   config = {
        ["settings"] = {
            ["time"] = '600',
			["cmd"] = "afki",
			["showwindow"] = false,
			["pushwindow"] = false,
			["soundwindow"] = false,
			["active"] = true;
        }
	}
    savejson(convertTableToJsonString(config), "moonloader/config/AFK Informer.json")
end
if limgui then
	afk_window, showwindow, pushwindow, active, soundwindow = new.bool(false), new.bool(config.settings.showwindow), new.bool(config.settings.pushwindow), new.bool(config.settings.active), new.bool(config.settings.soundwindow)
	Timewaitsec, cmdbuffer = new.char[256](config.settings.time), imgui.new.char[128](config.settings.cmd)
	sizeX, sizeY = getScreenResolution()


	function Standart()
		imgui.SwitchContext()
		local style = imgui.GetStyle()
		local colors = style.Colors
		local clr = imgui.Col
		local ImVec4 = imgui.ImVec4
		local ImVec2 = imgui.ImVec2
		
		style.PopupRounding = 3
		style.WindowBorderSize = 1
		style.ChildBorderSize  = 1
		style.PopupBorderSize  = 1
		style.FrameBorderSize  = 1
		style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
		style.ChildRounding = 3
		style.WindowPadding = ImVec2(15, 15)
		style.WindowRounding = 15.0
		style.FramePadding = ImVec2(5, 5)
		style.ItemSpacing = imgui.ImVec2(2, 3)
		style.ItemInnerSpacing = ImVec2(8, 6)
		style.IndentSpacing = 25.0
		style.ScrollbarSize = 8.0
		style.ScrollbarRounding = 15.0
		style.GrabMinSize = 15.0
		style.GrabRounding = 7.0
		style.FrameRounding = 6.0
		style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)

		colors[clr.Text] = ImVec4(0.80, 0.80, 0.83, 1.00)
		colors[clr.TextDisabled] = ImVec4(0.24, 0.23, 0.29, 1.00)
		colors[clr.WindowBg] = ImVec4(0.06, 0.05, 0.07, 1.00)
		colors[clr.PopupBg] = ImVec4(0.07, 0.07, 0.09, 1.00)
		colors[clr.Border] = ImVec4(0.30, 0.30, 0.30, 0.80)
		colors[clr.BorderShadow] = ImVec4(0.92, 0.91, 0.88, 0.00)
		colors[clr.FrameBg] = ImVec4(0.10, 0.09, 0.12, 1.00)
		colors[clr.FrameBgHovered] = ImVec4(0.24, 0.23, 0.29, 1.00)
		colors[clr.FrameBgActive] = ImVec4(0.56, 0.56, 0.58, 1.00)
		colors[clr.TitleBg] = ImVec4(0.10, 0.09, 0.12, 1.00)
		colors[clr.TitleBgActive] = ImVec4(0.07, 0.07, 0.09, 1.00)
		colors[clr.TitleBgCollapsed] = ImVec4(1.00, 0.98, 0.95, 0.75)
		colors[clr.MenuBarBg] = ImVec4(0.10, 0.09, 0.12, 1.00)
		colors[clr.ScrollbarBg] = ImVec4(0.02, 0.02, 0.02, 0.53)
		colors[clr.ScrollbarGrab] = ImVec4(0.80, 0.80, 0.83, 0.31)
		colors[clr.ScrollbarGrabHovered] = ImVec4(0.56, 0.56, 0.58, 1.00)
		colors[clr.ScrollbarGrabActive] = ImVec4(0.06, 0.05, 0.07, 1.00)
		colors[clr.CheckMark] = ImVec4(0.98, 0.26, 0.26, 1.00)
		colors[clr.SliderGrab] = ImVec4(0.28, 0.28, 0.28, 1.00)
		colors[clr.SliderGrabActive] = ImVec4(0.06, 0.05, 0.07, 1.00)
		colors[clr.Button] = ImVec4(0.10, 0.09, 0.12, 1.00)
		colors[clr.ButtonHovered] = ImVec4(0.24, 0.23, 0.29, 1.00)
		colors[clr.ButtonActive] = ImVec4(0.56, 0.56, 0.58, 1.00)
		colors[clr.Header] = ImVec4(0.10, 0.09, 0.12, 1.00)
		colors[clr.HeaderHovered] = ImVec4(0.56, 0.56, 0.58, 1.000)
		colors[clr.HeaderActive] = ImVec4(0.06, 0.05, 0.07, 1.00)
		colors[clr.Separator] = colors[clr.Border]
		colors[clr.SeparatorHovered] = ImVec4(0.26, 0.59, 0.98, 0.78)
		colors[clr.SeparatorActive] = ImVec4(0.26, 0.59, 0.98, 1.00)
		colors[clr.ResizeGrip] = ImVec4(0.00, 0.00, 0.00, 0.00)
		colors[clr.ResizeGripHovered] = ImVec4(0.56, 0.56, 0.58, 1.00)
		colors[clr.ResizeGripActive] = ImVec4(0.06, 0.05, 0.07, 1.00)
		colors[clr.PlotLines] = ImVec4(0.40, 0.39, 0.38, 0.63)
		colors[clr.PlotLinesHovered] = ImVec4(0.25, 1.00, 0.00, 1.00)
		colors[clr.PlotHistogram] = ImVec4(0.40, 0.39, 0.38, 0.63)
		colors[clr.PlotHistogramHovered] = ImVec4(0.25, 1.00, 0.00, 1.00)
		colors[clr.TextSelectedBg] = ImVec4(0.25, 1.00, 0.00, 0.43)
	end


	imgui.OnInitialize(function()
		Standart()
		imgui.GetIO().IniFilename = nil
	end)
	infoOK = ''
	if showwindow[0] and pushwindow[0] then infoOK = 'Нажмите Да, чтобы развернуть игру' else infoOK = '' end
	changecmdtext = u8''
	newFrame = imgui.OnFrame(
		function() return afk_window[0] end,
		function(player)
			imgui.SetNextWindowPos(imgui.ImVec2(sizeX / 1.2, sizeY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
			imgui.SetNextWindowSize(imgui.ImVec2(247, 257), imgui.Cond.FirstUseEver)
			imgui.Begin("AFK Informer by dmitriyewich", afk_window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
				if imgui.IsItemHovered() then
					if go_CMDserver == nil then go_CMDserver = os.clock() + (0.55 and 0.55 or 0.0) end
					local alpha = (os.clock() - go_CMDserver) * 3.5
					if os.clock() >= go_CMDserver then
						imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, (alpha <= 1.0 and alpha or 1.0))
							imgui.BeginTooltip()
							imgui.PushTextWrapPos(450)
								imgui.TextUnformatted(u8'©dmitriyewich aka Валерий Дмитриевич.\nРаспространение допускается только с указанием автора\nПКМ - Открыть группу в вк')
							if not imgui.IsItemVisible() and imgui.GetStyle().Alpha == 1.0 then go_CMDserver = nil end
							imgui.PopTextWrapPos()
							imgui.EndTooltip()
						imgui.PopStyleVar()
					end
				end
				if not imgui.IsItemHovered() then go_CMDserver = nil end
				if not imgui.IsAnyItemHovered() and imgui.GetStyle().Alpha == 1.0 then go_hint = nil end
				if imgui.IsItemClicked(1) then
					os.execute('explorer "https://vk.com/dmitriyewichmods"') -- открытие браузера с этой ссылкой
				end
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 3)
			if imgui.Checkbox(u8'Вкл\\Выкл скрипт', active) then
				config.settings.active = active[0]
				savejson(convertTableToJsonString(config), "moonloader/config/AFK Informer.json")
			end
			if showwindow[0] and pushwindow[0] then infoOK = 'Нажмите Да, чтобы развернуть игру' else infoOK = '' end
			imgui.SetCursorPosX((imgui.GetWindowWidth() - imgui.CalcTextSize(u8'Текущий таймер: '..config.settings.time.. u8' секунд').x) / 2)
			imgui.Text(u8"Текущий таймер: "..config.settings.time.. u8' секунд')
			-- imgui.SetCursorPosX((imgui.GetWindowWidth() - 215) / 2)
			imgui.PushItemWidth(217)
			if imgui.InputTextWithHint(u8'##ID 2', u8'Введите время в секундах', Timewaitsec, sizeof(Timewaitsec), imgui.InputTextFlags.CharsDecimal + imgui.InputTextFlags.AutoSelectAll + imgui.InputTextFlags.EnterReturnsTrue) then
				config.settings.time = str(Timewaitsec)
				savejson(convertTableToJsonString(config), "moonloader/config/AFK Informer.json")
			end
			imgui.PopItemWidth()
			imgui.SetCursorPosX((imgui.GetWindowWidth() - 130) / 2)
			if imgui.Button(u8"Сохранить таймер", imgui.ImVec2(130, 0)) then
				config.settings.time = str(Timewaitsec)
				savejson(convertTableToJsonString(config), "moonloader/config/AFK Informer.json")
			end
			if imgui.Checkbox(u8'Разворачивать окно игры', showwindow) then
				config.settings.showwindow = showwindow[0]
				savejson(convertTableToJsonString(config), "moonloader/config/AFK Informer.json")
			end
			if imgui.Checkbox(u8'Показывать окно уведомления', pushwindow) then
				config.settings.pushwindow = pushwindow[0]
				savejson(convertTableToJsonString(config), "moonloader/config/AFK Informer.json")
			end
			if imgui.Checkbox(u8'Звукое уведомления', soundwindow) then
				config.settings.soundwindow = soundwindow[0]
				savejson(convertTableToJsonString(config), "moonloader/config/AFK Informer.json")
			end
			if imgui.CollapsingHeader(u8'Доп.Настройки') then
				imgui.SetCursorPosX((imgui.GetWindowWidth() - 210) / 2)
				imgui.PushItemWidth(210)
				if imgui.InputTextWithHint(u8'##cmd', u8'Введите команду без "/"', cmdbuffer, sizeof(cmdbuffer), imgui.InputTextFlags.AutoSelectAll) then
					config.settings.cmd = str(cmdbuffer)
					-- savejson(convertTableToJsonString(config), "moonloader/config/AFK Informer.json")
				end
					if imgui.IsItemHovered() then
						imgui.BeginTooltip()
						imgui.PushTextWrapPos(600)
							imgui.TextUnformatted(u8'Чтобы изменить команду активации\nвведите команду без "/"')
						imgui.PopTextWrapPos()
						imgui.EndTooltip()
					end
				imgui.PopItemWidth()
				imgui.SetCursorPosX((imgui.GetWindowWidth() - 130) / 2)
				if imgui.Button(u8'Сохранить команду', imgui.ImVec2(130, 0)) then
					config.settings.cmd = str(cmdbuffer)
					sampUnregisterChatCommand(config.settings.cmd)
					savejson(convertTableToJsonString(config), "moonloader/config/AFK Informer.json")
					sampRegisterChatCommand(config.settings.cmd, function() main_window[0] = not main_window[0] end)
				if str(cmdbuffer) == nil or str(cmdbuffer) == '' or ffi.string(cmdbuffer) == ' ' or str(cmdbuffer):find('/.+') then
						changecmdtext = u8'Поле ввода пустое или содержит символ "/"\nВведите команду без "/" '
						config.settings.cmd = 'afki'
						savejson(convertTableToJsonString(config), "moonloader/config/AFK Informer.json")
					else
						changecmdtext = u8''
					end
				end
				imgui.TextWrapped(u8""..changecmdtext)
				imgui.SetScrollY(imgui.GetScrollMaxY())
			end
		imgui.End()
	end)
end

ffi.cdef [[
	typedef void* HANDLE;
	typedef const char* LPCSTR;
	typedef unsigned UINT;
    typedef int BOOL;
    typedef unsigned long HANDLE;
    typedef HANDLE HWND;
    typedef int bInvert;
	typedef unsigned long DWORD;
	typedef DWORD *PDWORD;
 
    HWND GetActiveWindow(void);
	HWND SetActiveWindow(HWND hWnd);
	BOOL ShowWindow(HWND hWnd, int  nCmdShow);
	
	BOOL OpenIcon(HWND hWnd);
	
	HWND FindWindowA(LPCSTR lpClassName, LPCSTR lpWindowName);
	BOOL IsIconic(HWND hWnd);
	BOOL SetForegroundWindow(HWND hWnd);
	BOOL ShowWindowAsync(HWND hWnd,int nCmdShow);
	void SwitchToThisWindow(HWND hwnd, BOOL fUnknown);
	BOOL BlockInput(BOOL fBlockIt);
	BOOL BringWindowToTop(HWND hWnd);
	
	HWND GetForegroundWindow(void);
	DWORD GetCurrentThreadId(void);
	DWORD GetWindowThreadProcessId(HWND hWnd, PDWORD lpdwProcessId);
	BOOL AttachThreadInput(DWORD idAttach, DWORD idAttachTo, BOOL  fAttach);
	
	int MessageBoxA(HWND, LPCSTR, LPCSTR, UINT);
	
	int zip_extract(const char *zipname, const char *dir,int *func, void *arg);
	
	bool PlaySound(const char *pszSound, void *hmod, uint32_t fdwSound);
]]

function ShowMessage(text, title)
  MB_YESNO = 4
  IDNO = 7
	if pushwindow[0] and showwindow[0] then
		if ffi.C.MessageBoxA(nil, text, title, 0x00000004 + 0x30 + 0x00002000 + 0x00010000 + 0x00040000) ~= IDNO then
			lua_thread.create(function()
				hCurrWnd = ffi.C.GetForegroundWindow()
				iMyTID   = ffi.C.GetCurrentThreadId()
				iCurrTID = ffi.C.GetWindowThreadProcessId(hCurrWnd, nil)
				ffi.C.BlockInput(true)
				wait(10)
				ffi.C.AttachThreadInput(iMyTID, iCurrTID, true)
				ffi.C.SetForegroundWindow(hwnd)
				ffi.C.OpenIcon(hwnd);
				ffi.C.SetActiveWindow(hwnd)
				ffi.C.ShowWindow(hwnd, 3)
				ffi.C.SwitchToThisWindow(hwnd, true)
				ffi.C.BringWindowToTop(hwnd)
				wait(10)
				ffi.C.BlockInput(false)
				ffi.C.AttachThreadInput(iMyTID, iCurrTID, false)
			end)
		else
			print('Нажато No')
		end
	elseif pushwindow[0] and not showwindow[0] then
		ffi.C.MessageBoxA(nil, text, title, 0x30 + 0x00002000 + 0x00010000 + 0x00040000)
	end
end


function main()
	if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
	checksound()
	checklibs() -- эту удалить если не нужна проверка на библиотеки
	hwnd = ffi.C.FindWindowA("Grand theft auto San Andreas", nil)
	if config.settings.cmd == 'afki' then
		sampRegisterChatCommand('afki', function() afk_window[0] = not afk_window[0] end)
	else
		sampUnregisterChatCommand('afki')
		sampRegisterChatCommand(config.settings.cmd, function() afk_window[0] = not afk_window[0] end)
	end
	sampSetClientCommandDescription(config.settings.cmd, string.format("Активация/деактивация окна %s, Файл: %s", thisScript().name, thisScript().filename))
	thread1 = lua_thread.create_suspended(secondThread)
	wait(-1)
end

function checksound()
	if not doesFileExist(getWorkingDirectory()..'\\resource\\AFK Informer\\sound.wav') then
		lua_thread.create(function()
			createDirectory(getWorkingDirectory()..'\\resource\\AFK Informer')
			downloadFile('sound', getWorkingDirectory()..'\\resource\\AFK Informer\\sound.wav', 'https://dl.dropbox.com/s/ozpzp8c000azr8j/sound.wav')
			while not doesFileExist(getWorkingDirectory()..'\\resource\\AFK Informer\\sound.wav') do wait(0) end
		end)
		return true
	end
	return false
end

function playsound(filepath)
	winmm.PlaySound(filepath, nil, 0x00020003)
end

function secondThread()
	wait(config.settings.time * 1000)
	if soundwindow[0] then playsound(getWorkingDirectory()..'\\resource\\AFK Informer\\sound.wav'); end
	if pushwindow[0] then
		ShowMessage('Вы стоите в афк уже '.. config.settings.time ..' секунд\nВремя начала афк ' .. test ..' \nТекущее время '.. os.date('%X') ..'\n'..infoOK, 'AFK Informer')
	end
	if showwindow[0] and not pushwindow[0] then
		lua_thread.create(function()
			hCurrWnd = ffi.C.GetForegroundWindow()
			iMyTID   = ffi.C.GetCurrentThreadId()
			iCurrTID = ffi.C.GetWindowThreadProcessId(hCurrWnd, nil)
			ffi.C.BlockInput(true)
			wait(10)
			ffi.C.AttachThreadInput(iMyTID, iCurrTID, true)
			ffi.C.SetForegroundWindow(hwnd)
			ffi.C.OpenIcon(hwnd);
			ffi.C.SetActiveWindow(hwnd)
			ffi.C.ShowWindow(hwnd, 3)
			ffi.C.SwitchToThisWindow(hwnd, true)
			ffi.C.BringWindowToTop(hwnd)
			wait(10)
			ffi.C.BlockInput(false)
			ffi.C.AttachThreadInput(iMyTID, iCurrTID, false)
		end)
	end
end

local arr = {}
function onWindowMessage(msg, wparam, lparam)
	if active[0] then
		if msg == wm.WM_KILLFOCUS then
			memory.write(0x747FB6, 0x1, 1, true)
			memory.write(0x74805A, 0x1, 1, true)
			memory.fill(0x74542B, 0x90, 8, true)
			memory.fill(0x53EA88, 0x90, 6, true)
			lockPlayerControl(true)
			test = os.date('%X')
			thread1:run()
		elseif msg == wm.WM_SETFOCUS then
			memory.write(0x747FB6, 0x0, 1, true)
			memory.write(0x74805A, 0x0, 1, true)
			arr = { 0x50, 0x51, 0xFF, 0x15, 0x00, 0x83, 0x85, 0x00 }
			memset(0x74542B)
			arr = { 0x0F, 0x84, 0x7B, 0x01, 0x00, 0x00 }
			memset(0x53EA88)
			lockPlayerControl(false)
			thread1:terminate()
		end
	end
	if msg == 0x100 or msg == 0x101 then
		if wparam == vkeys.VK_ESCAPE and  afk_window[0] and not isPauseMenuActive() then
			consumeWindowMessage(true, false)
			if msg == 0x101 then
				afk_window[0] = false
			end
		end
	end
end

function memset(addr)
	for i = 1, #arr do
		memory.write(addr + i - 1, arr[i], 1, true)
	end
end

if lziplib then -- с этой строки и до конца
	function zipextract(script_name)
		file_path = getWorkingDirectory() .. "\\" .. script_name ..".zip"
		if doesFileExist(file_path) then
			print("Распаковка архива: " .. script_name)
			local extract_des = string.format("%s\\%s",getWorkingDirectory(),script_name)
			ziplib.zip_extract(file_path,extract_des,nil,nil)
			MoveFiles(extract_des,getWorkingDirectory().."\\lib")
			os.remove(file_path)
			print("Распаковка прошла успешно, распакован архив: " .. script_name)
		else
			print("Файлы не найдет, перезапустите скрипт.")
		end
	end
end

if llfs then
	function MoveFiles(main_dir,dest_dir)
		for f in lfs.dir(main_dir) do
			local main_file = main_dir .. "\\" .. f

			if doesDirectoryExist(main_file) and f ~= "." and f ~= ".." then
				MoveFiles(main_file,dest_dir .. "\\" .. f)
			end

			if doesFileExist(main_file) then
				dest_file = dest_dir .. "/" .. f
				if not doesDirectoryExist(dest_dir) then
					lfs.mkdir(dest_dir)
				end
				
				if doesFileExist(dest_file) then
					os.remove(dest_file)
				end
				if doesFileExist(dest_file) then
					os.remove(main_file)
					print("Невозможно удалить файл " .. dest_file)
				else
					os.rename(main_file,dest_file)
				end
				
			end
		end
		lfs.rmdir(main_dir)
	end
end

function checklibs()
	if not limgui or not llfs or not lziplib then
		lua_thread.create(function()
			print('Подгрузка необходимых библиотек..')
			if not lziplib then
				downloadFile('ziplib', getWorkingDirectory()..'\\lib\\ziplib.dll', 'https://www.dropbox.com/s/uw0huxlf5tkv8ls/ziplib.dll?dl=1')
				while not doesFileExist(getWorkingDirectory()..'\\lib\\ziplib.dll') do wait(0) end
				reloadScripts()
			else
				wait(0)
			end
			if not llfs then
				downloadFile('lfs.dll', getWorkingDirectory()..'\\lib\\lfs.dll', 'https://www.dropbox.com/s/d6urv7nxcrtkcz3/lfs.dll?dl=1')
				while not doesFileExist(getWorkingDirectory()..'\\lib\\lfs.dll') do wait(0) end
				reloadScripts()
			else
				wait(0)
			end
			if not limgui then
			downloadFile('mimgui-v1.7.0.zip', getWorkingDirectory()..'\\mimgui-v1.7.0.zip', 'https://github.com/THE-FYP/mimgui/releases/download/v1.7.0/mimgui-v1.7.0.zip')
			while not doesFileExist(getWorkingDirectory()..'\\mimgui-v1.7.0.zip') do wait(0) end
			zipextract("mimgui-v1.7.0")
			else
				wait(0)
			end
			print('Подгрузка необходимых библиотек окончена. Перезагружаюсь..')
			wait(1000)
			reloadScripts()
		end)
		return false
	end
	return true
end

function downloadFile(name, path, link)
	if not doesFileExist(path) then
		downloadUrlToFile(link, path, function(id, status, p1, p2)
			if status == dlstatus.STATUSEX_ENDDOWNLOAD then
				print('{FFFFFF}Файл {35ab2b}«'..name..'»{FFFFFF} загружен!')
			end
		end)
	end
end
