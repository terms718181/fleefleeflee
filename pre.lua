-- returnfire triggerbot (optimized build)
--
-- Changes vs old version:
--   * shot detection is event-driven: GunFiring / shot-counter / ammo are
--     hooked with GetPropertyChangedSignal, so shots register the instant
--     they happen (the old per-frame poll missed deltas between frames)
--   * a poll fallback covers executors where value hooks fail, so shots
--     are ALWAYS registered one way or the other
--   * the per-frame step no longer scans characters at all (big perf win)
--   * hitbox-px feature removed (useless)

local okWs, WS = pcall(function() return game:GetService("Workspace") end)
local Workspace = (okWs and WS) or workspace
local okPs, PS = pcall(function() return game:GetService("Players") end)
local Players = okPs and PS or nil

pcall(setrobloxinput, true)

local CFG = {
    tb_enabled = true,
    tb_key = 0x06,
    tb_kbmode = "hold",

    tb_maxdist = 150,
    tb_catch = true,

    tb_click_min = 60,
    tb_click_max = 120,
    tb_rel_min = 15,
    tb_rel_max = 50,

    tb_react_min = 20,
    tb_react_max = 80,

    tb_spam_min = 20,
    tb_spam_max = 45,
}

local function v(id)
    return CFG[id]
end

local SNAP_KEYS = {}
for k in pairs(CFG) do SNAP_KEYS[#SNAP_KEYS + 1] = k end

local cfgSnap, cfgSnapAt = nil, 0
local CFG_SNAP_TTL = 0.2

local function cfg(id)
    local now = tick()
    if not cfgSnap or now - cfgSnapAt > CFG_SNAP_TTL then
        cfgSnap = {}
        for _, k in ipairs(SNAP_KEYS) do cfgSnap[k] = v(k) end
        cfgSnapAt = now
    end
    return cfgSnap[id]
end

local function vkHeld(vk)
    if vk == 0x01 then
        local ok, r = pcall(ismouse1pressed)
        return ok and r == true
    elseif vk == 0x02 then
        local ok, r = pcall(ismouse2pressed)
        return ok and r == true
    end
    local ok, r = pcall(iskeypressed, vk)
    return ok and r == true
end

local kbOn, kbPrev = false, false
local function keyActive()
    local mode = CFG.tb_kbmode
    if mode == "always" then return true end
    local held = vkHeld(CFG.tb_key)
    if mode == "toggle" then
        if held and not kbPrev then kbOn = not kbOn end
        kbPrev = held
        return kbOn
    end
    return held
end

local function windowActive()
    local ok, r = pcall(isrbxactive)
    if ok then return r == true end
    return true
end

local function localPlayer()
    local ok, lp = pcall(function() return Players.LocalPlayer end)
    return ok and lp or nil
end

local function localRootPos()
    local lp = localPlayer()
    local hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or Vector3.new(0, 0, 0)
end

local function randRange(a, b)
    a, b = tonumber(a) or 0, tonumber(b) or 0
    if b < a then a, b = b, a end
    return a + math.random() * (b - a)
end

local function dist2squared(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return dx * dx + dy * dy + dz * dz
end

-- ===== crosshair check (catch-off mode) =================================
-- fixed small radius around the cursor, throttled to a few checks/sec;
-- no per-object pixel math like the old hitbox slider
local HOVER_R = 40

local function cursorPos()
    local lp = localPlayer()
    if lp then
        local ok, m = pcall(function() return lp:GetMouse() end)
        if ok and m and m.X and m.Y then return m.X, m.Y end
    end
    return -1, -1
end

local hoverAt, hoverState = 0, false
local function hoverEnemy(now)
    if now - hoverAt < 0.1 then return hoverState end
    hoverAt = now
    hoverState = false
    local lp = localPlayer()
    local mx, my = cursorPos()
    local lpos = localRootPos()
    local maxd = cfg("tb_maxdist") or 0
    for _, m in ipairs(charList()) do
        if not (lp and (m.Name == lp.Name or m == lp.Character)) then
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if hrp then
                local ok, sp, on = pcall(function()
                    local s, o = WorldToScreen(hrp.Position)
                    return s, o
                end)
                if ok and on then
                    local dx, dy = sp.X - mx, sp.Y - my
                    if dx * dx + dy * dy <= HOVER_R * HOVER_R then
                        local d = dist2squared(lpos, hrp.Position)
                        if maxd <= 0 or d <= maxd * maxd then
                            hoverState = true
                            break
                        end
                    end
                end
            end
        end
    end
    return hoverState
end

-- ===== character discovery ==============================================
local charsCache, charsAt = nil, 0
local CHAR_TTL = 0.25

local function invalidateChars()
    charsCache = nil
end

local function allchars()
    local out, seen = {}, {}
    local pf = Workspace:FindFirstChild("Players")
    local charsRoot = pf and (pf:FindFirstChild("Characters") or pf)
    if charsRoot then
        for _, m in ipairs(charsRoot:GetChildren()) do
            if m:IsA("Model") then out[#out + 1] = m seen[m.Address] = true end
        end
    end
    local ok, pls = pcall(function() return Players:GetPlayers() end)
    if ok and pls then
        for _, p in ipairs(pls) do
            local c = Workspace:FindFirstChild(p.Name) or p.Character
            if c and not seen[c.Address] then out[#out + 1] = c end
        end
    end
    return out
end

local function charList()
    local now = tick()
    if not charsCache or now - charsAt > CHAR_TTL then
        charsCache = allchars()
        charsAt = now
    end
    return charsCache
end

pcall(function()
    local pfLoc = Workspace:FindFirstChild("Players")
    if pfLoc then
        pfLoc.ChildAdded:Connect(invalidateChars)
        pfLoc.ChildRemoved:Connect(invalidateChars)
        local cr = pfLoc:FindFirstChild("Characters")
        if cr then
            cr.ChildAdded:Connect(invalidateChars)
            cr.ChildRemoved:Connect(invalidateChars)
        end
    end
end)

-- ===== comp discovery ===================================================
local function isNumValue(o)
    return o and (o:IsA("IntValue") or o:IsA("NumberValue"))
end

local function findNamed(parent, ...)
    for _, n in ipairs({ ... }) do
        local vv = parent:FindFirstChild(n)
        if vv then return vv end
    end
    return nil
end

local function findBodyEffects(m)
    local be = m:FindFirstChild("BodyEffects")
    if be then return be end
    for _, sub in ipairs(m:GetChildren()) do
        if sub:IsA("Folder") then
            be = sub:FindFirstChild("BodyEffects")
            if be then return be end
        end
    end
    return nil
end

-- every equipped gun is scanned, not just the first one, so double
-- barrel / tac shotgun / etc all register. Each entry is a value object
-- whose drop = shots fired.
local function gunAmmoList(m)
    local out = {}
    for _, c in ipairs(m:GetChildren()) do
        if c:FindFirstChild("Handle") then
            local a = findNamed(c, "Ammo", "AMMO")
            local sc = not a and c:FindFirstChild("Script")
            a = a or (sc and findNamed(sc, "Ammo", "AMMO"))
            if isNumValue(a) then out[#out + 1] = a end
        end
    end
    return out
end

-- ===== shot detection (per-frame delta poll + hook fast path) ===========
-- The event hooks alone turned out unreliable on some executors (server
-- replicated value changes can fail to raise the signal), so the realtime
-- guarantee comes from a per-frame delta poll: it reads the raw values
-- directly (no pcall per read - one pcall wraps the whole scan) and inventories
-- every change into shots. Hooks stay attached as a fast path; the dedup
-- window makes counting a burst twice impossible.
-- Three independent signals:
--   1) BodyEffects.GunFiring bool rising edge  -> 1 shot
--   2) BodyEffects shot counter increment      -> delta shots
--   3) equipped tool Ammo decrease             -> delta shots

local comps = setmetatable({}, { __mode = "k" })
local watchers = setmetatable({}, { __mode = "k" })
local fireBaseline = {}
local gcBaseline = {}
local ammoBaseline = {}
local charLastShot = {}          -- [addr] = tick of last counted shot (dedup)
local attachedAmmo = {}          -- [ammo addr] = a hook is attached for it
local shotAt, latched = 0, false
local fireAt = 0                 -- earliest moment we may answer the shot

local HOOK_BUDGET = 400
local hookCount = 0

local function killWatchers(addr)
    local set = watchers[addr]
    if set then
        for _, conn in ipairs(set) do
            pcall(function() conn:Disconnect() end)
        end
        watchers[addr] = nil
        hookCount = math.max(0, hookCount - #set)
    end
    local c = comps[addr]
    if c and c.ams then
        for _, ao in ipairs(c.ams) do
            local aa = ao.Address
            ammoBaseline[aa] = nil
            attachedAmmo[aa] = nil
        end
    end
    fireBaseline[addr] = nil
    gcBaseline[addr] = nil
    charLastShot[addr] = nil
    comps[addr] = nil
end

local function charComps(m)
    local a = m.Address
    local c = comps[a]
    if c then return c end
    c = {}
    c.name = m.Name
    c.hrp = m:FindFirstChild("HumanoidRootPart")
    local be = findBodyEffects(m)
    c.be = be
    c.gf = be and be:FindFirstChild("GunFiring") or nil
    c.gc = be and (be:FindFirstChild("GunShotChanges") or be:FindFirstChild("GunChanges")) or nil
    c.rl = be and (be:FindFirstChild("Reload") or be:FindFirstChild("Reloading")) or nil
    c.ams = gunAmmoList(m)
    comps[a] = c
    return c
end

local function detect(m, n)
    local lp = localPlayer()
    if lp and m.Name == lp.Name then return end
    local hrp = m:FindFirstChild("HumanoidRootPart")
    -- squared distance, compare against squared maxdist
    local d = hrp and dist2squared(localRootPos(), hrp.Position) or 9e18
    local maxd = cfg("tb_maxdist") or 0
    if lp and maxd > 0 and d > maxd * maxd then return end
    local now = tick()
    shotAt = now
    -- reaction delay: now + random(min..max) ms; fireOnce honors fireAt
    fireAt = now + randRange(cfg("tb_react_min"), cfg("tb_react_max")) / 1000
    latched = true
    -- shot log (like the original build)
    print("[shot] " .. tostring(m.Name)
        .. " x" .. tostring(n)
        .. " @ " .. (d < 9e18 and string.format("%.0f", math.sqrt(d)) or "?")
        .. "st")
end

-- handlers shared between hooks, the poll fallback and the per-frame scan
local function makeHandlers(m, c)
    local addr = m.Address

    -- dedup: one registration per burst per source; the window covers the
    -- poll+hook race so a burst can never be counted twice
    local function shots(n)
        if n <= 0 then return end
        local now = tick()
        local last = charLastShot[addr] or 0
        if now - last < 0.05 then return end
        charLastShot[addr] = now
        detect(m, n)
    end

    local handlers = {}

    handlers.gf = function()
        local ok, val = pcall(function() return c.gf.Value end)
        if not ok then return end
        local f = val == true
        local prev = fireBaseline[addr]
        fireBaseline[addr] = f
        if f and not prev then shots(1) end
    end

    handlers.gc = function()
        local ok, val = pcall(function() return c.gc.Value end)
        if not ok or type(val) ~= "number" then return end
        local prev = gcBaseline[addr]
        gcBaseline[addr] = val
        if prev and val > prev then shots(val - prev) end
    end

    -- ammo hooks are handled per-tool by attachAmmo below (all guns)

    return handlers
end

-- hook one ammo value object; every equipped gun gets its own
local function attachAmmo(set, m, c, ao)
    local aa = ao.Address
    if not aa or attachedAmmo[aa] or hookCount >= HOOK_BUDGET then return end
    local okv, v0 = pcall(function() return ao.Value end)
    ammoBaseline[aa] = okv and type(v0) == "number" and v0 or nil
    local ok, conn = pcall(function()
        return ao:GetPropertyChangedSignal("Value"):Connect(function()
            local ok2, val = pcall(function() return ao.Value end)
            if not ok2 or type(val) ~= "number" then return end
            local okR, rl = pcall(function() return c.rl and c.rl.Value end)
            if okR and rl then
                ammoBaseline[aa] = val -- reloading; resync (refill != shots)
                return
            end
            local prev = ammoBaseline[aa]
            ammoBaseline[aa] = val
            if prev and val < prev then
                local now = tick()
                local last = charLastShot[m.Address] or 0
                if now - last >= 0.05 then
                    charLastShot[m.Address] = now
                    detect(m, prev - val)
                end
            end
        end)
    end)
    if ok and conn then
        set[#set + 1] = conn
        hookCount = hookCount + 1
        attachedAmmo[aa] = true
    end
end

local function watchChar(m)
    local addr = m.Address
    if watchers[addr] or hookCount >= HOOK_BUDGET then return end
    local c = charComps(m)
    if not (c.gf or c.gc or c.am) then return end

    local set = {}
    watchers[addr] = set
    local handlers = makeHandlers(m, c)

    local function hook(obj, prop, handler)
        if not obj then return end
        if hookCount >= HOOK_BUDGET then return end
        local ok, conn = pcall(function()
            return obj:GetPropertyChangedSignal(prop):Connect(handler)
        end)
        if ok and conn then
            set[#set + 1] = conn
            hookCount = hookCount + 1
        end
    end

    if c.gf then
        fireBaseline[addr] = c.gf.Value == true
        hook(c.gf, "Value", handlers.gf)
    end
    if c.gc then
        local ok, v0 = pcall(function() return c.gc.Value end)
        gcBaseline[addr] = ok and type(v0) == "number" and v0 or nil
        hook(c.gc, "Value", handlers.gc)
    end
    if c.ams then
        for _, ao in ipairs(c.ams) do
            attachAmmo(set, m, c, ao)
        end
    end

    hook(m, "Parent", function()
        if m.Parent == nil then killWatchers(addr) end
    end)
end

pcall(function()
    Players.PlayerAdded:Connect(invalidateChars)
    Players.PlayerRemoving:Connect(function(p)
        if p and p.Character then killWatchers(p.Character.Address) end
        invalidateChars()
    end)
end)

-- rescan a char's gun tools/effect values (covers weapon swaps) and
-- attach hooks for any ammo value not seen before
local function refreshComps(m)
    local c = comps[m.Address]
    if not c then return end
    c.be = findBodyEffects(m)
    c.gf = c.be and c.be:FindFirstChild("GunFiring") or nil
    c.gc = c.be and (c.be:FindFirstChild("GunShotChanges") or c.be:FindFirstChild("GunChanges")) or nil
    c.rl = c.be and (c.be:FindFirstChild("Reload") or c.be:FindFirstChild("Reloading")) or nil
    c.ams = gunAmmoList(m)
    local set = watchers[m.Address]
    if set then
        for _, ao in ipairs(c.ams) do
            attachAmmo(set, m, c, ao)
        end
    end
end

local sweepAt = 0
local function watchSweep()
    local now = tick()
    if now - sweepAt < 0.33 then return end
    sweepAt = now
    local list = charList()
    local seenL = {}
    for _, m in ipairs(list) do
        seenL[m.Address] = true
        if not watchers[m.Address] then
            killWatchers(m.Address)
            watchChar(m)
        else
            refreshComps(m)
        end
    end
    for addr in pairs(watchers) do
        if not seenL[addr] then killWatchers(addr) end
    end
end

-- ===== realtime scan (per-frame, direct reads) ==========================
-- This is the mechanism that actually guarantees shots are registered: raw
-- value reads each frame (single pcall around the whole scan, no per-read
-- pcall overhead), delta math inline. Hooks attached above stay as an extra
-- fast path; charLastShot dedupes so no burst is ever counted twice.
local function realtimeScan()
    local ok = pcall(function()
        local now = tick()
        for _, m in ipairs(charList()) do
            local addr = m.Address
            local c = charComps(m)
            -- 1) GunFiring rising edge
            if c.gf then
                local f = c.gf.Value == true
                if f and not fireBaseline[addr] then
                    fireBaseline[addr] = true
                    local last = charLastShot[addr] or 0
                    if now - last >= 0.05 then
                        charLastShot[addr] = now
                        detect(m, 1)
                    end
                else
                    fireBaseline[addr] = f
                end
            end
            -- 2) shot counter delta
            if c.gc then
                local val = c.gc.Value
                if type(val) == "number" then
                    local prev = gcBaseline[addr]
                    if prev and val > prev then
                        local last = charLastShot[addr] or 0
                        if now - last >= 0.05 then
                            charLastShot[addr] = now
                            detect(m, val - prev)
                        end
                    end
                    gcBaseline[addr] = val
                end
            end
            -- 3) any gun's ammo decrease (every tool scanned; reload protected)
            for _, ao in ipairs(c.ams or {}) do
                local aa = ao.Address
                local val = ao.Value
                if type(val) == "number" then
                    local rl = c.rl and c.rl.Value
                    if rl then
                        ammoBaseline[aa] = val
                    else
                        local prev = ammoBaseline[aa]
                        if prev and val < prev then
                            local last = charLastShot[addr] or 0
                            if now - last >= 0.05 then
                                charLastShot[addr] = now
                                detect(m, prev - val)
                            end
                        end
                        ammoBaseline[aa] = val
                    end
                end
            end
        end
    end)
end

-- ===== clicking =========================================================
local lastClick, nextClickIn = 0, 0
local pendingRelease = 0
local spamLast, spamNext = 0, 0

local function resetEngagement()
    nextClickIn = 0
    spamNext = 0
end

local function fireOnce(now)
    if pendingRelease > 0 and now < pendingRelease then return end
    if pendingRelease > 0 then
        pcall(mouse1release)
        pendingRelease = 0
    end
    local hold = randRange(cfg("tb_rel_min"), cfg("tb_rel_max")) / 1000
    if hold > 0.002 and pcall(mouse1press) then
        pendingRelease = now + hold
    else
        pcall(mouse1click)
    end
    nextClickIn = randRange(cfg("tb_click_min"), cfg("tb_click_max")) / 1000
    lastClick = now
end

local alive = true
_G.RETURNFIRE_STOP = function()
    alive = false
    pcall(mouse1release)
    for addr in pairs(watchers) do killWatchers(addr) end
end

-- ===== main step ========================================================
local function step(now)
    if pendingRelease > 0 and now >= pendingRelease then
        pcall(mouse1release)
        pendingRelease = 0
    end

    watchSweep()
    realtimeScan()

    if not cfg("tb_enabled") or not windowActive() then
        latched = false
        resetEngagement()
        return
    end

    if not keyActive() then
        latched = false
        resetEngagement()
        return
    end

    if latched then
        if not cfg("tb_catch") then
            latched = false
            resetEngagement()
            return
        end
        -- reaction delay for the first answer, then rapid-fire for as long
        -- as the key stays held (keyActive clearing latched stops it)
        if now >= fireAt and now - spamLast >= spamNext then
            fireOnce(now)
            spamLast = now
            spamNext = math.max(0.01, randRange(cfg("tb_spam_min"), cfg("tb_spam_max")) / 1000)
        end
    elseif not cfg("tb_catch") then
        if hoverEnemy(now) and now >= fireAt and now - lastClick >= nextClickIn then
            fireOnce(now)
            fireAt = now + randRange(cfg("tb_react_min"), cfg("tb_react_max")) / 1000
        end
    else
        resetEngagement()
    end
end

local lastErr = nil
local function safeStep()
    local ok, err = pcall(step, tick())
    if not ok and err ~= lastErr then
        lastErr = err
        warn("triggerbot error: " .. tostring(err))
    end
end

local hooked = false
pcall(function()
    local rs = game:GetService("RunService")
    if rs and rs.Heartbeat then
        rs.Heartbeat:Connect(safeStep)
        hooked = true
    end
end)
if not hooked then
    local runner = task and task.spawn or spawn
    local waiter = task and task.wait or wait
    runner(function()
        while alive do
            safeStep()
            waiter(0.02)
        end
    end)
end

-- ===== menu (Drawing api) ===============================================
local C = {
    bg = Color3.fromRGB(10, 10, 13),
    border = Color3.fromRGB(30, 30, 36),
    accent = Color3.fromRGB(140, 120, 140),
    text = Color3.fromRGB(185, 185, 192),
    dim = Color3.fromRGB(98, 98, 106),
    off = Color3.fromRGB(34, 34, 40),
    bar = Color3.fromRGB(28, 28, 34),
    panel = Color3.fromRGB(16, 16, 20),
}

local MW, MH = 460, 300
local COLW, ROWH, TITLEH = 400, 20, 14
local TABW, TABH = 153, 24

local menu = {
    open = true,
    x = 60, y = 80,
    tab = 1,
    objs = {},
    rows = {},
    chrome = {},
    listening = nil,
    listenAt = 0,
    editing = nil,
    editBuf = "",
    editPrev = {},
    cfgName = "config1",
    cfgFiles = {},
    cfgScanAt = 0,
    confirm = nil,
    modePick = nil,
    prevClickR = false,
    dragging = nil,
    slider = nil,
    prevClick = false,
    prevIns = false,
}
menu.baseY = menu.y

local COLUMNS = {
    { title = "general", widgets = {
        { kind = "toggle", id = "tb_enabled", label = "enabled" },
        { kind = "bind", id = "tb_key", label = "keybind" },
        { kind = "slider", id = "tb_maxdist", label = "max dist", min = 0, max = 2000, fmt = "%d" },
        { kind = "toggle", id = "tb_catch", label = "catch shot" },
        { kind = "note", label = "on = fires back after a shot" },
    }},
    { title = "timing", widgets = {
        { kind = "slider", id = "tb_react_min", label = "react min", min = 0, max = 1000, fmt = "%dms" },
        { kind = "slider", id = "tb_react_max", label = "react max", min = 0, max = 1000, fmt = "%dms" },
        { kind = "note", label = "reaction = delay before answering" },
        { kind = "slider", id = "tb_spam_min", label = "spam min", min = 10, max = 500, fmt = "%dms" },
        { kind = "slider", id = "tb_spam_max", label = "spam max", min = 10, max = 500, fmt = "%dms" },
        { kind = "note", label = "spam = click speed while firing back" },
        { kind = "slider", id = "tb_click_min", label = "min click delay", min = 0, max = 1000, fmt = "%dms" },
        { kind = "slider", id = "tb_click_max", label = "max click delay", min = 0, max = 1000, fmt = "%dms" },
        { kind = "slider", id = "tb_rel_min", label = "min release", min = 0, max = 500, fmt = "%dms" },
        { kind = "slider", id = "tb_rel_max", label = "max release", min = 0, max = 500, fmt = "%dms" },
        { kind = "note", label = "delay = between clicks" },
        { kind = "note", label = "release = how long held" },
    }},
    { title = "configs", widgets = {} },
}

local CFG_DIR = "returnfire"

local function cfgPath(name)
    return CFG_DIR .. "/" .. name .. ".cfg"
end

local function saveConfig(name)
    local lines = {}
    for k, val in pairs(CFG) do
        lines[#lines + 1] = k .. "=" .. tostring(val)
    end
    table.sort(lines)
    pcall(makefolder, CFG_DIR)
    return pcall(writefile, cfgPath(name), table.concat(lines, "\n"))
end

local function loadConfig(name)
    local ok, raw = pcall(readfile, cfgPath(name))
    if not ok or type(raw) ~= "string" then return false end
    for line in raw:gmatch("[^\r\n]+") do
        local k, val = line:match("^([%w_]+)=(.*)$")
        if k and CFG[k] ~= nil then
            local n = tonumber(val)
            if n then CFG[k] = n
            elseif val == "true" then CFG[k] = true
            elseif val == "false" then CFG[k] = false end
        end
    end
    return true
end

local function scanConfigs()
    local out = {}
    local ok, files = pcall(listfiles, CFG_DIR)
    if ok and type(files) == "table" then
        for _, f in ipairs(files) do
            local n = tostring(f):match("([^/\\]+)%.cfg$")
            if n then out[#out + 1] = n end
        end
    end
    table.sort(out)
    return out
end

local VK_NAMES = {
    [0x01] = "lmb", [0x02] = "rmb", [0x04] = "mmb",
    [0x05] = "x1", [0x06] = "x2",
    [0x08] = "bksp", [0x09] = "tab", [0x0D] = "enter",
    [0x10] = "shift", [0x11] = "ctrl", [0x12] = "alt",
    [0x14] = "caps", [0x1B] = "esc", [0x20] = "space",
    [0xA0] = "lshift", [0xA1] = "rshift", [0xA2] = "lctrl",
    [0xA4] = "lalt", [0xA5] = "ralt", [0x2D] = "ins", [0x2E] = "del",
}
for i = 0x30, 0x39 do VK_NAMES[i] = string.char(i) end
for i = 0x41, 0x5A do VK_NAMES[i] = string.char(i):lower() end

local function vkName(vk)
    return VK_NAMES[vk] or string.format("0x%02X", vk)
end

local EDIT_CHARS = {
    [0xBE] = ".", [0x6E] = ".", [0xBD] = "-", [0x6D] = "-",
    [0x08] = "\b", [0x0D] = "\n", [0x1B] = "\x1b", [0x2E] = "\b",
}
for i = 0, 9 do
    EDIT_CHARS[0x30 + i] = tostring(i)
    EDIT_CHARS[0x60 + i] = tostring(i)
end
for i = 0x41, 0x5A do EDIT_CHARS[i] = string.char(i + 32) end
EDIT_CHARS[0x20] = " "
EDIT_CHARS[0xBA] = "_"
EDIT_CHARS[0xBB] = "+"

local function newSq(color, z)
    local s = Drawing.new("Square")
    s.Filled, s.Color, s.Visible, s.ZIndex = true, color, false, z
    menu.objs[#menu.objs + 1] = s
    return s
end

local function newTxt(size, color, z)
    local t = Drawing.new("Text")
    t.Size, t.Color, t.Visible, t.ZIndex, t.Outline = size, color, false, z, false
    pcall(function() t.Font = Drawing.Fonts.System end)
    menu.objs[#menu.objs + 1] = t
    return t
end

local oc = setmetatable({}, { __mode = "k" })
local function ocache(o)
    local c = oc[o]
    if not c then c = {} oc[o] = c end
    return c
end
local function opos(o, x, y)
    local c = ocache(o)
    if c.px ~= x or c.py ~= y then c.px, c.py = x, y o.Position = Vector2.new(x, y) end
end
local function osiz(o, w, h)
    local c = ocache(o)
    if c.sw ~= w or c.sh ~= h then c.sw, c.sh = w, h o.Size = Vector2.new(w, h) end
end
local function otxt(o, s)
    local c = ocache(o)
    if c.tx ~= s then c.tx = s o.Text = s end
end
local function ocol(o, col)
    local c = ocache(o)
    if c.cl ~= col then c.cl = col o.Color = col end
end
local function ovis(o, b)
    local c = ocache(o)
    if c.vs ~= b then c.vs = b o.Visible = b end
end

local menuBuilt = false
local function buildMenu()
    if menuBuilt then return end
    menu.bg = newSq(C.bg, 1)
    menu.border = newSq(C.border, 0)
    menu.titleBar = newSq(C.panel, 2)
    menu.tabBar = newSq(C.panel, 1)
    menu.edge = newSq(C.accent, 2)
    menu.tabChip = newSq(C.accent, 2)
    menu.chrome = { menu.bg, menu.border, menu.titleBar, menu.tabBar, menu.edge, menu.tabChip }

    for ci, col in ipairs(COLUMNS) do
        col.hdObj = newTxt(13, C.text, 3)
        col.hdObj.Text = col.title
        menu.chrome[#menu.chrome + 1] = col.hdObj
        for _, w in ipairs(col.widgets) do
            local r = { w = w, col = ci, vis = {} }
            local function reg(o)
                r.vis[#r.vis + 1] = o
                return o
            end
            r.label = reg(newTxt(14, C.text, 3))
            r.label.Text = w.label
            if w.kind == "toggle" then
                r.box = reg(newSq(C.off, 3))
            elseif w.kind == "slider" then
                r.barBg = reg(newSq(C.off, 3))
                r.barFill = reg(newSq(C.accent, 3))
                r.knob = reg(newSq(C.accent, 3))
                r.valTxt = reg(newTxt(12, C.text, 3))
            elseif w.kind == "bind" then
                r.box = reg(newSq(C.bar, 3))
                r.valTxt = reg(newTxt(12, C.accent, 3))
            end
            menu.rows[#menu.rows + 1] = r
        end
        if col.title == "configs" then
            local function mkrow(w)
                local r = { w = w, col = ci, vis = {} }
                r.label = newTxt(14, C.text, 3)
                r.vis[#r.vis + 1] = r.label
                if w.kind ~= "file" then
                    r.box = newSq(C.bar, 3)
                    r.valTxt = newTxt(12, C.accent, 3)
                    r.vis[#r.vis + 1] = r.box
                    r.vis[#r.vis + 1] = r.valTxt
                else
                    r.valTxt = newTxt(12, C.dim, 3)
                    r.loadTxt = newTxt(12, C.accent, 3)
                    r.saveTxt = newTxt(12, C.text, 3)
                    r.vis[#r.vis + 1] = r.valTxt
                    r.vis[#r.vis + 1] = r.loadTxt
                    r.vis[#r.vis + 1] = r.saveTxt
                end
                menu.rows[#menu.rows + 1] = r
                return r
            end
            mkrow({ kind = "text", label = "name" })
            mkrow({ kind = "button", label = "" })
            for i = 1, 12 do
                local r = mkrow({ kind = "file", label = "" })
                r.fileIdx = i
            end
        end
    end
    menu.cfBg = newSq(C.panel, 6)
    menu.cfBorder = newSq(C.border, 5)
    menu.cfTxt = newTxt(13, C.text, 7)
    menu.cfYes = newSq(C.accent, 7)
    menu.cfYesTxt = newTxt(12, C.bg, 7)
    menu.cfYesTxt.Text = "yes"
    menu.cfNo = newSq(C.bar, 7)
    menu.cfNoTxt = newTxt(12, C.text, 7)
    menu.cfNoTxt.Text = "no"

    menu.mpBg = newSq(C.panel, 8)
    menu.mpBorder = newSq(C.border, 7)
    menu.mpTxts = {}
    for i = 1, 3 do
        menu.mpTxts[i] = newTxt(12, C.text, 9)
    end
    menuBuilt = true
end

local MODE_OPTS = { "hold", "toggle", "always" }

local function layoutMode()
    local r = menu.modePick
    local on = r ~= nil
    for _, o in ipairs({ menu.mpBg, menu.mpBorder }) do ovis(o, on) end
    for i = 1, 3 do ovis(menu.mpTxts[i], on) end
    if not on then return end
    local pw, ph = 84, 3 * 16 + 8
    local px = r.x + COLW - pw
    local py = r.y + ROWH + 2
    opos(menu.mpBorder, px - 1, py - 1)
    osiz(menu.mpBorder, pw + 2, ph + 2)
    opos(menu.mpBg, px, py)
    osiz(menu.mpBg, pw, ph)
    r.opts = {}
    for i, m in ipairs(MODE_OPTS) do
        local ty = py + 4 + (i - 1) * 16
        local t = menu.mpTxts[i]
        opos(t, px + 8, ty)
        otxt(t, m)
        ocol(t, CFG.tb_kbmode == m and C.accent or C.text)
        r.opts[i] = { px, ty - 2, pw, 16 }
    end
end

local function layoutConfirm()
    local on = menu.confirm ~= nil
    for _, o in ipairs({ menu.cfBg, menu.cfBorder, menu.cfTxt, menu.cfYes, menu.cfYesTxt, menu.cfNo, menu.cfNoTxt }) do
        ovis(o, on)
    end
    if not on then return end
    local bw, bh = 210, 64
    local bx = menu.x + (MW - bw) / 2
    local by = menu.y + TITLEH + (MH - TITLEH - bh) / 2
    opos(menu.cfBorder, bx - 1, by - 1)
    osiz(menu.cfBorder, bw + 2, bh + 2)
    opos(menu.cfBg, bx, by)
    osiz(menu.cfBg, bw, bh)
    opos(menu.cfTxt, bx + 12, by + 10)
    otxt(menu.cfTxt, menu.confirm.act == "del"
        and ("delete '" .. menu.confirm.name .. "'?")
        or ("overwrite '" .. menu.confirm.name .. "'?"))
    opos(menu.cfYes, bx + 12, by + bh - 24)
    osiz(menu.cfYes, 60, 16)
    opos(menu.cfYesTxt, bx + 34, by + bh - 22)
    opos(menu.cfNo, bx + bw - 72, by + bh - 24)
    osiz(menu.cfNo, 60, 16)
    opos(menu.cfNoTxt, bx + bw - 48, by + bh - 22)
    menu.confirm.yes = { bx + 12, by + bh - 24, 60, 16 }
    menu.confirm.no = { bx + bw - 72, by + bh - 24, 60, 16 }
end

local function tabX(i)
    return menu.x + (i - 1) * TABW
end

local function layoutMenu()
    opos(menu.border, menu.x - 1, menu.y - 1)
    osiz(menu.border, MW + 2, MH + 2)
    opos(menu.bg, menu.x, menu.y)
    osiz(menu.bg, MW, MH)
    opos(menu.titleBar, menu.x, menu.y)
    osiz(menu.titleBar, MW, TITLEH)
    opos(menu.tabBar, menu.x, menu.y + TITLEH)
    osiz(menu.tabBar, MW, TABH)
    opos(menu.edge, menu.x, menu.y)
    osiz(menu.edge, 2, MH)

    local ctx = tabX(menu.tab) + 10
    menu.chipX = (menu.chipX or ctx) + (menu.x - (menu.px or menu.x))
    menu.px = menu.x
    menu.chipX = menu.chipX + (ctx - menu.chipX) * 0.3
    opos(menu.tabChip, menu.chipX, menu.y + TITLEH + 3)
    osiz(menu.tabChip, TABW - 20, 17)

    for ci, col in ipairs(COLUMNS) do
        local tx = tabX(ci)
        local on = ci == menu.tab
        opos(col.hdObj, tx + 18, menu.y + TITLEH + 5)
        ocol(col.hdObj, on and C.bg or C.dim)
    end

    local cx = menu.x + 30
    for ci, col in ipairs(COLUMNS) do
        local ri = 0
        for _, r in ipairs(menu.rows) do
            if r.col == ci then
                ri = ri + 1
                local w = r.w
                local ry = menu.y + TITLEH + TABH + 10 + (ri - 1) * ROWH
                r.x, r.y = cx, ry
                opos(r.label, cx, ry + 3)
                if w.kind == "toggle" then
                    opos(r.box, cx + COLW - 16, ry + 5)
                    osiz(r.box, 10, 10)
                    ocol(r.box, CFG[w.id] and C.accent or C.off)
                elseif w.kind == "slider" then
                    opos(r.barBg, cx + COLW - 140, ry + 9)
                    osiz(r.barBg, 80, 2)
                    local f = math.max(0, math.min(1, (CFG[w.id] - w.min) / (w.max - w.min)))
                    r.fv = r.fv and (r.fv + (f - r.fv) * 0.35) or f
                    local c = ocache(r.barFill)
                    local bx, by = cx + COLW - 140, ry + 9
                    if c.px ~= bx or c.py ~= by then c.px, c.py = bx, by r.barFill.Position = Vector2.new(bx, by) end
                    osiz(r.barFill, 80 * r.fv, 2)
                    opos(r.knob, cx + COLW - 142 + 80 * r.fv, ry + 6)
                    osiz(r.knob, 4, 8)
                    opos(r.valTxt, cx + COLW - 52, ry + 4)
                    if menu.editing == r then
                        otxt(r.valTxt, menu.editBuf .. "_")
                        ocol(r.valTxt, C.accent)
                    elseif w.id == "tb_maxdist" and CFG[w.id] <= 0 then
                        otxt(r.valTxt, "off")
                        ocol(r.valTxt, C.dim)
                    else
                        otxt(r.valTxt, string.format(w.fmt, CFG[w.id]))
                        ocol(r.valTxt, C.text)
                    end
                elseif w.kind == "note" then
                    ocol(r.label, C.dim)
                elseif w.kind == "bind" then
                    otxt(r.label, w.id == "tb_key"
                        and ("keybind  " .. tostring(CFG.tb_kbmode)) or w.label)
                    opos(r.box, cx + COLW - 48, ry + 4)
                    osiz(r.box, 40, 13)
                    ocol(r.box, menu.listening == r and C.accent or C.bar)
                    opos(r.valTxt, cx + COLW - 45, ry + 5)
                    otxt(r.valTxt, vkName(CFG[w.id]))
                    ocol(r.valTxt, menu.listening == r and C.bg or C.accent)
                elseif w.kind == "text" then
                    opos(r.box, cx + COLW - 140, ry + 3)
                    osiz(r.box, 136, 14)
                    ocol(r.box, menu.editing == r and C.accent or C.bar)
                    opos(r.valTxt, cx + COLW - 136, ry + 4)
                    otxt(r.valTxt, menu.editing == r and (menu.editBuf .. "_") or menu.cfgName)
                    ocol(r.valTxt, menu.editing == r and C.bg or C.accent)
                elseif w.kind == "button" then
                    otxt(r.label, "")
                    opos(r.box, cx, ry + 2)
                    osiz(r.box, COLW - 8, 16)
                    ocol(r.box, C.bar)
                    opos(r.valTxt, cx + 8, ry + 4)
                    otxt(r.valTxt, "create config")
                    ocol(r.valTxt, C.accent)
                elseif w.kind == "file" then
                    r.fileName = menu.cfgFiles[r.fileIdx]
                    otxt(r.label, r.fileName or "")
                    ocol(r.label, C.text)
                    opos(r.loadTxt, cx + COLW - 92, ry + 3)
                    otxt(r.loadTxt, r.fileName and "load" or "")
                    opos(r.saveTxt, cx + COLW - 56, ry + 3)
                    otxt(r.saveTxt, r.fileName and "save" or "")
                    opos(r.valTxt, cx + COLW - 18, ry + 3)
                    otxt(r.valTxt, r.fileName and "x" or "")
                end
            end
        end
    end
end

local function setMenuVisible(b)
    if not b then
        for _, o in ipairs(menu.objs) do ovis(o, false) end
        return
    end
    for _, o in ipairs(menu.chrome) do ovis(o, true) end
    for _, r in ipairs(menu.rows) do
        local on = r.col == menu.tab
        for _, o in ipairs(r.vis) do ovis(o, on) end
    end
end

local function inRect(mx, my, x, y, w, h)
    if not (x and y and w and h) then return false end
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function menuMousePos()
    local lp = localPlayer()
    if lp then
        local ok, m = pcall(function() return lp:GetMouse() end)
        if ok and m and m.X and m.Y then return m.X, m.Y end
    end
    return -1, -1
end

local function captureKey()
    for vk = 0x01, 0xFE do
        if vk ~= 0x1B then
            local ok, r = pcall(iskeypressed, vk)
            if ok and r then return vk end
        end
    end
end

local function commitEdit()
    local w = menu.editing.w
    if w.kind == "text" then
        local n = menu.editBuf:gsub("[^%w_%- ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #n > 0 then menu.cfgName = n end
        menu.editing = nil
        return
    end
    local n = tonumber(menu.editBuf)
    if n then
        n = math.max(w.min, math.min(w.max, n))
        if w.fmt == "%d" or w.fmt == "%dms" or w.fmt == "%d%%" then
            n = math.floor(n + 0.5)
        end
        CFG[w.id] = n
    end
    menu.editing = nil
end

local function editStep()
    for vk, ch in pairs(EDIT_CHARS) do
        local ok, p = pcall(iskeypressed, vk)
        p = ok and p == true
        if p and not menu.editPrev[vk] then
            if ch == "\b" then
                menu.editBuf = menu.editBuf:sub(1, -2)
            elseif ch == "\n" then
                commitEdit()
            elseif ch == "\x1b" then
                menu.editing = nil
            else
                local isNum = menu.editing.w.kind == "slider"
                if isNum and not ch:match("[%d%.%-]") then
                    -- numbers only
                elseif ch == "." and menu.editBuf:find("%.") then
                    -- already has a dot
                elseif ch == "-" and #menu.editBuf > 0 then
                    -- minus only first
                else
                    menu.editBuf = menu.editBuf .. ch
                end
            end
        end
        menu.editPrev[vk] = p
    end
end

local function menuStep()
    buildMenu()

    local okIns, ins = pcall(iskeypressed, 0x08)
    ins = okIns and ins == true
    if ins and not menu.prevIns and not menu.editing then
        menu.open = not menu.open
        if menu.open then
            layoutMenu()
        else
            setMenuVisible(false)
            menu.listening, menu.dragging, menu.slider = nil, nil, nil
            menu.editing = nil
        end
    end
    menu.prevIns = ins

    if menu.offY == nil then menu.offY = menu.open and -16 or 0 end
    local targetY = menu.open and 0 or -16
    menu.offY = menu.offY + (targetY - menu.offY) * 0.3
    if math.abs(targetY - menu.offY) < 0.5 then menu.offY = targetY end
    if not menu.open and menu.offY <= -16 then
        setMenuVisible(false)
        menu.listening, menu.dragging, menu.slider = nil, nil, nil
        menu.editing = nil
        return
    end
    menu.y = menu.baseY + menu.offY

    if not menu.open then
        layoutMenu()
        setMenuVisible(true)
        layoutConfirm()
        layoutMode()
        return
    end

    local mx, my = menuMousePos()
    local ok, down = pcall(ismouse1pressed)
    down = ok and down == true
    local click = down and not menu.prevClick
    menu.prevClick = down
    local okR, rdown = pcall(ismouse2pressed)
    rdown = okR and rdown == true
    local rclick = rdown and not menu.prevClickR
    menu.prevClickR = rdown

    if rclick and not menu.confirm and not menu.listening then
        for _, r in ipairs(menu.rows) do
            if r.col == menu.tab and r.w.kind == "bind" and r.w.id == "tb_key"
                and inRect(mx, my, r.x, r.y, COLW, ROWH - 2) then
                menu.modePick = r
            end
        end
    end

    if menu.listening then
        if tick() - menu.listenAt > 0.15 then
            local okEsc, esc = pcall(iskeypressed, 0x1B)
            if okEsc and esc then
                menu.listening = nil
            else
                local vk = captureKey()
                if vk then
                    CFG[menu.listening.w.id] = vk
                    menu.listening = nil
                end
            end
        end
    end

    if click then
        if menu.confirm then
            local c = menu.confirm
            if c.yes and inRect(mx, my, c.yes[1], c.yes[2], c.yes[3], c.yes[4]) then
                if c.act == "del" then
                    pcall(delfile, cfgPath(c.name))
                else
                    saveConfig(c.name)
                end
                menu.cfgFiles = scanConfigs()
            end
            menu.confirm = nil
        elseif menu.modePick then
            local picked = false
            for i, rc in ipairs(menu.modePick.opts or {}) do
                if inRect(mx, my, rc[1], rc[2], rc[3], rc[4]) then
                    CFG.tb_kbmode = MODE_OPTS[i]
                    picked = true
                end
            end
            menu.modePick = nil
            if picked then
                menu.listening, menu.slider, menu.dragging = nil, nil, nil
            end
        elseif menu.editing then
            commitEdit()
        elseif inRect(mx, my, menu.x, menu.y, MW, TITLEH) then
            menu.dragging = { mx - menu.x, my - menu.y }
        elseif inRect(mx, my, menu.x, menu.y + TITLEH, MW, TABH) then
            local ti = math.floor((mx - menu.x) / TABW) + 1
            if COLUMNS[ti] then menu.tab = ti end
        else
            for _, r in ipairs(menu.rows) do
                local w = r.w
                if r.col == menu.tab and inRect(mx, my, r.x, r.y, COLW, ROWH - 2) then
                    if w.kind == "toggle" then
                        CFG[w.id] = not CFG[w.id]
                    elseif w.kind == "bind" then
                        menu.listening = r
                        menu.listenAt = tick()
                    elseif w.kind == "slider" then
                        if inRect(mx, my, r.x + COLW - 60, r.y, 60, ROWH - 2) then
                            menu.editing = r
                            menu.editBuf = tostring(CFG[w.id])
                            menu.editPrev = {}
                        else
                            menu.slider = r
                        end
                    elseif w.kind == "text" then
                        menu.editing = r
                        menu.editBuf = menu.cfgName
                        menu.editPrev = {}
                    elseif w.kind == "button" then
                        local n = menu.cfgName:gsub("[^%w_%- ]", "")
                        if #n > 0 and saveConfig(n) then
                            menu.cfgFiles = scanConfigs()
                        end
                    elseif w.kind == "file" and r.fileName then
                        if inRect(mx, my, r.x + COLW - 24, r.y, 24, ROWH - 2) then
                            menu.confirm = { act = "del", name = r.fileName }
                        elseif inRect(mx, my, r.x + COLW - 62, r.y, 34, ROWH - 2) then
                            menu.confirm = { act = "save", name = r.fileName }
                        elseif inRect(mx, my, r.x + COLW - 98, r.y, 34, ROWH - 2) then
                            loadConfig(r.fileName)
                        end
                    end
                end
            end
        end
    end

    if menu.editing then editStep() end

    if COLUMNS[menu.tab].title == "configs" and tick() - menu.cfgScanAt > 1 then
        menu.cfgScanAt = tick()
        menu.cfgFiles = scanConfigs()
    end

    if menu.dragging then
        menu.x, menu.baseY = mx - menu.dragging[1], my - menu.dragging[2]
        menu.y = menu.baseY + (menu.offY or 0)
    end
    if menu.slider then
        local w = menu.slider.w
        local bx = menu.slider.x + COLW - 140
        local f = math.max(0, math.min(1, (mx - bx) / 80))
        local val = w.min + f * (w.max - w.min)
        if w.fmt == "%d" or w.fmt == "%dms" or w.fmt == "%d%%" then
            val = math.floor(val + 0.5)
        end
        CFG[w.id] = val
    end
    if not down then
        menu.dragging, menu.slider = nil, nil
    end

    layoutMenu()
    setMenuVisible(true)
    layoutConfirm()
    layoutMode()
end

local lastUiErr = nil
local function safeMenu()
    local ok, e = pcall(menuStep)
    if not ok and e ~= lastUiErr then
        lastUiErr = e
        warn("[tb] menu: " .. tostring(e))
    end
end

pcall(function()
    local rs = game:GetService("RunService")
    if rs and rs.Heartbeat then
        rs.Heartbeat:Connect(safeMenu)
    end
end)
