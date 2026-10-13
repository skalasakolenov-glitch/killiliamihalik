--[[
    nyx_loader.lua  -  registration through a Discord webhook + remote kill switch for nyx.lua
    Engine : Garry's Mod, clientside Lua
    Files  : garrysmod/lua/autorun/client/nyx_loader.lua   (this file, loads on join)
             nyx.lua is NOT on disk: it is downloaded from CHEAT_URL (GitHub raw) into memory
             and run with CompileString, nothing is written to the game folder
    Needs  : sv_allowcslua 1 on the server (CompileString on the client is blocked without it)

    How it works
      1. First start: a window asks for a name. Register posts an embed to your webhook with the
         name, nick and SteamID64. Saved in data/nyx/reg.json, so it is only asked once.
      2. Every CHECK_EVERY seconds STATUS_URL (a JSON file only you can edit) is read:
           { "enabled": true, "min_version": 1, "open": false,
             "allowed": ["7656119..."], "banned": [], "message": "" }
         nyx.lua is downloaded and run only when enabled == true, the SteamID64 is in "allowed"
         (or open == true) and it is not in "banned". Optional in the status file:
           "url"    : another raw link to run instead of CHEAT_URL (switch builds without
                      handing out a new loader)
           "sha256" : hash of the exact nyx.lua that may run; anything else is refused, so a
                      changed file on GitHub never runs by accident
      3. As soon as the answer turns to "no" (enabled false, banned, taken off allowed), NyxUnload()
         runs, and it runs again every second for as long as the answer stays "no" - so loading
         nyx.lua by hand (lua_openscript_cl) is switched off again straight away.

    Console: nyx_register [name]   nyx_status   nyx_recheck
]]

if NyxLoaderUnload then pcall(NyxLoaderUnload) end

local L = {
    WEBHOOK      = "https://discord.com/api/webhooks/1559207350362181753/HZOWv2Ma4jiXu8RImVbl3sGrcRYneGnlMoiLiyp_HJtV558o7w9mB1LrEpT1wH5m7fG6",
    STATUS_URL   = "https://gist.githubusercontent.com/skalasakolenov-glitch/e3c9592a9bb74b53085e2969881fece4/raw/6a397ee6f2c2e89d8fdec31df1c44d28c5787642/gistfile1.txt",
    CHEAT_URL    = "https://raw.githubusercontent.com/skalasakolenov-glitch/killiliamihalik/refs/heads/main/main.lua",
    VERSION      = 1,                 -- compared with "min_version" in the status file
    CHECK_EVERY  = 60,                -- seconds between status checks
    FAIL_CLOSED  = 5,                 -- failed checks in a row before a running cheat is turned off (0 = never)
    REG_FILE     = "nyx/reg.json",
    REG_COOLDOWN = 600,               -- seconds before the same machine may send another registration
}

local S = {
    loaded  = false,      -- nyx.lua is running because of us
    allowed = nil,        -- last answer: true / false / nil (no answer yet)
    status  = "checking...",
    fails   = 0,
    fetching = false,     -- a download of nyx.lua is in flight
    src     = nil,        -- the last downloaded source, kept in memory only
    srcHash = nil,
}

local TIMER = "nyx_loader_check"
local HOOK  = "nyx_loader_enforce"

local function Say(text)
    MsgC(Color(149, 184, 6), "[nyx] ", Color(225, 225, 225), text, "\n")
end

local function SID()
    local me = LocalPlayer()
    if not IsValid(me) then return nil end
    return me:SteamID64() or "0"
end

-- registration file ------------------------------------------------------------------

local function ReadReg()
    local raw = file.Read(L.REG_FILE, "DATA")
    local t = raw and util.JSONToTable(raw)
    return istable(t) and t or nil
end

local function WriteReg(t)
    file.CreateDir("nyx")
    file.Write(L.REG_FILE, util.TableToJSON(t, true))
end

-- Discord markdown would mangle names; mentions are blocked separately through allowed_mentions
local function Clean(s, max)
    s = string.gsub(tostring(s or ""), "[`*_~|>@\\]", "")
    s = string.Trim(s)
    if s == "" then s = "-" end
    return string.sub(s, 1, max or 32)
end

local function Register(name, onDone)
    local me, sid = LocalPlayer(), SID()
    if not sid then onDone(false, "not in game yet") return end

    local reg = ReadReg()
    if reg and reg.sid == sid and reg.sentAt and os.time() - reg.sentAt < L.REG_COOLDOWN then
        onDone(false, string.format("already sent, wait %ds", L.REG_COOLDOWN - (os.time() - reg.sentAt)))
        return
    end

    local payload = {
        username = "nyx register",
        allowed_mentions = {parse = {}},
        embeds = {{
            title = "New registration",
            color = 9811974,           -- 0x95B806, the menu accent
            fields = {
                {name = "Name",      value = Clean(name),               inline = true},
                {name = "Steam nick", value = Clean(me:Nick()),          inline = true},
                {name = "Loader",    value = "v" .. L.VERSION,          inline = true},
                {name = "SteamID64", value = "`" .. sid .. "`",         inline = false},
                {name = "Profile",   value = "https://steamcommunity.com/profiles/" .. sid, inline = false},
            },
            footer = {text = "approve: add the SteamID64 to \"allowed\" in status.json"},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }},
    }

    HTTP({
        url = L.WEBHOOK,
        method = "POST",
        type = "application/json",
        body = util.TableToJSON(payload),
        success = function(code)
            if code >= 200 and code < 300 then
                WriteReg({name = Clean(name), sid = sid, sentAt = os.time()})
                onDone(true)
            else
                onDone(false, "discord answered " .. code)
            end
        end,
        failed = function(err) onDone(false, tostring(err)) end,
    })
end

-- cheat on / off -----------------------------------------------------------------------

-- compile and run source that is already in memory; true when nyx is running afterwards
local function RunSource(src)
    local fn = CompileString(src, "nyx", false)
    if not isfunction(fn) then
        S.status = "nyx.lua does not compile: " .. tostring(fn)
        Say(S.status)
        return false
    end

    local ok, err = pcall(fn)
    if not ok then
        S.status = "nyx.lua failed: " .. tostring(err)
        Say(S.status)
        return false
    end

    return true
end

-- t = the status file: its "url" / "sha256" override the defaults
local function StartCheat(t)
    if S.loaded and NyxUnload then return end
    if S.fetching then return end

    local want = isstring(t.sha256) and t.sha256 ~= "" and string.lower(t.sha256) or nil

    -- the copy from last time is still the approved one: no second download
    if S.src and (not want or want == S.srcHash) then
        S.loaded = RunSource(S.src)
        return
    end

    local url = (isstring(t.url) and t.url ~= "") and t.url or L.CHEAT_URL
    local sep = string.find(url, "?", 1, true) and "&" or "?"

    S.fetching = true
    S.status = "downloading nyx..."

    HTTP({
        url = url .. sep .. "t=" .. os.time(),
        method = "GET",
        success = function(code, body)
            S.fetching = false

            if code ~= 200 or not isstring(body) or #body == 0 then
                S.status = "download failed: http " .. tostring(code)
                Say(S.status)
                return
            end

            local hash = util.SHA256(body)
            if want and hash ~= want then
                S.status = "nyx.lua hash does not match status.json, refused"
                Say(S.status)
                return
            end

            S.src, S.srcHash = body, hash

            -- the answer may have turned to "no" while the file was on its way
            if S.allowed then S.loaded = RunSource(body) end
            if S.loaded then S.status = "approved, running" end
        end,
        failed = function(err)
            S.fetching = false
            S.status = "download failed: " .. tostring(err)
            Say(S.status)
        end,
    })
end

local function KillCheat()
    if NyxUnload then pcall(NyxUnload) end
    S.loaded = false
end

-- status check -------------------------------------------------------------------------

local function InList(list, sid)
    if not istable(list) then return false end
    for _, v in ipairs(list) do
        if tostring(v) == sid then return true end
    end
    return false
end

-- true, or false + the reason
local function Decide(t)
    local sid = SID()
    if not sid then return false, "not in game yet" end

    if t.enabled ~= true then
        return false, (isstring(t.message) and t.message ~= "") and t.message or "disabled by the owner"
    end
    if isnumber(t.min_version) and L.VERSION < t.min_version then return false, "loader is outdated" end
    if InList(t.banned, sid) then return false, "banned" end
    if t.open == true or InList(t.allowed, sid) then return true end

    local reg = ReadReg()
    if reg and reg.sid == sid then return false, "waiting for approval" end
    return false, "not registered (nyx_register)"
end

local function Apply(t)
    S.fails = 0

    local ok, why = Decide(t)
    local before = S.allowed
    S.allowed = ok

    if ok then
        if not S.loaded then S.status = "approved" end
        StartCheat(t)
    else
        S.status = why
        S.src, S.srcHash = nil, nil      -- a revoked user keeps no copy in memory either
        KillCheat()
    end

    if before ~= ok then Say(ok and "access granted" or ("off: " .. why)) end
end

local function Fail(err)
    S.fails = S.fails + 1
    S.status = string.format("check failed (%d): %s", S.fails, tostring(err))

    if L.FAIL_CLOSED > 0 and S.fails >= L.FAIL_CLOSED and S.allowed then
        S.allowed = false
        KillCheat()
        Say("status unreachable, nyx turned off")
    end
end

local function CheckStatus()
    -- the time in the query keeps caches from handing out an old copy
    local sep = string.find(L.STATUS_URL, "?", 1, true) and "&" or "?"

    HTTP({
        url = L.STATUS_URL .. sep .. "t=" .. os.time(),
        method = "GET",
        success = function(code, body)
            if code ~= 200 then return Fail("http " .. code) end

            local t = util.JSONToTable(body or "")
            if not istable(t) then return Fail("status file is not valid JSON") end

            Apply(t)
        end,
        failed = Fail,
    })
end

-- registration window ------------------------------------------------------------------

local regFrame

local function OpenRegister()
    if IsValid(regFrame) then regFrame:MakePopup() return end

    local f = vgui.Create("DFrame")
    f:SetTitle("nyx - registration")
    f:SetSize(320, 150)
    f:Center()
    f:MakePopup()
    regFrame = f

    local lbl = vgui.Create("DLabel", f)
    lbl:SetPos(12, 32)
    lbl:SetSize(296, 18)
    lbl:SetText("Name (shown to the owner):")

    local entry = vgui.Create("DTextEntry", f)
    entry:SetPos(12, 52)
    entry:SetSize(296, 22)
    entry:SetText(LocalPlayer():Nick())

    local info = vgui.Create("DLabel", f)
    info:SetPos(12, 114)
    info:SetSize(296, 18)
    info:SetText("")

    local btn = vgui.Create("DButton", f)
    btn:SetPos(12, 82)
    btn:SetSize(296, 26)
    btn:SetText("Register")

    btn.DoClick = function()
        btn:SetEnabled(false)
        info:SetText("sending...")

        Register(entry:GetValue(), function(ok, err)
            if not IsValid(f) then return end
            btn:SetEnabled(true)

            if ok then
                info:SetText("sent - wait until the owner approves you")
                timer.Simple(2, function() if IsValid(f) then f:Close() end end)
                CheckStatus()
            else
                info:SetText("failed: " .. tostring(err))
            end
        end)
    end
end

-- start --------------------------------------------------------------------------------

local function Init()
    local reg = ReadReg()
    if not reg or reg.sid ~= SID() then OpenRegister() end

    CheckStatus()
    timer.Create(TIMER, L.CHECK_EVERY, 0, CheckStatus)
end

-- while the answer is "no", a hand-loaded nyx.lua is unloaded again within a second
local nextEnforce = 0
hook.Add("Think", HOOK, function()
    local now = RealTime()
    if now < nextEnforce then return end
    nextEnforce = now + 1

    if S.allowed ~= true and NyxUnload then KillCheat() end
end)

concommand.Add("nyx_register", function(ply, cmd, args, argStr)
    if argStr and string.Trim(argStr) ~= "" then
        Register(argStr, function(ok, err) Say(ok and "registration sent" or ("failed: " .. tostring(err))) end)
    else
        OpenRegister()
    end
end)

concommand.Add("nyx_status", function()
    Say(string.format("%s | nyx %s | SteamID64 %s", S.status, S.loaded and "running" or "off", SID() or "?"))
end)

concommand.Add("nyx_recheck", CheckStatus)

function NyxLoaderUnload()
    timer.Remove(TIMER)
    hook.Remove("Think", HOOK)
    hook.Remove("InitPostEntity", HOOK)
    concommand.Remove("nyx_register")
    concommand.Remove("nyx_status")
    concommand.Remove("nyx_recheck")
    if IsValid(regFrame) then regFrame:Remove() end
    NyxLoaderUnload = nil
end

-- autorun runs before the local player exists; run by hand in game it is already there
if IsValid(LocalPlayer()) then
    Init()
else
    hook.Add("InitPostEntity", HOOK, function()
        hook.Remove("InitPostEntity", HOOK)
        Init()
    end)
end
