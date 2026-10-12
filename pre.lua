local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

pcall(setrobloxinput, true)

local MOUSE_Y_OFFSET = 0 -- shots landing ~58px above cursor? set 58

local CFG = {
    tb_enabled = true,
    tb_key = 0x06,
    tb_kbmode = "hold",

    tb_visualize = false,
    tb_hitbox_x = 1.0,
    tb_hitbox_y = 2.0,
    tb_maxdist = 0,

    tb_sticky = false,
    tb_selkey = 0,
    tb_unselkey = 0,
    tb_selvis = true,

    tb_pred = false,
    tb_dist_pred = false,
    tb_close_dist = 20,
    tb_mid_dist = 50,
    tb_close_x = 0.15,
    tb_close_y = 0.15,
    tb_mid_x = 0.15,
    tb_mid_y = 0.15,
    tb_far_x = 0.15,
    tb_far_y = 0.15,
    tb_pred_x = 0.15,
    tb_pred_y = 0.15,
    tb_pred_smooth = 0.4,

    tb_humanize = false,
    tb_delay_min = 30,
    tb_delay_max = 120,
    tb_int_min = 80,
    tb_int_max = 160,
    tb_hold_min = 15,
    tb_hold_max = 55,
    tb_hes_chance = 10,
    tb_hes_min = 150,
    tb_hes_max = 450,
    tb_fatigue = 8,

    tb_knock = true, -- skip knocked (K.O) players
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

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function dist3(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local SELECTED, SELVIS = {}, {}
local prevSelKey, prevUnselKey = false, false

-- instance userdata gets rewrapped between frames, key on Address
local function selKey(t)
    local ok, a = pcall(function() return t.character.Address end)
    return ok and a or t.character
end

local function addSel(t)
    if t and t.character then SELECTED[selKey(t)] = t end
end

local function remSel(t)
    local k = t and t.character and selKey(t)
    if not k then return end
    local sv = SELVIS[k]
    SELECTED[k], SELVIS[k] = nil, nil
    if sv then
        pcall(function() sv.box:Remove() end)
        pcall(function() sv.txt:Remove() end)
    end
end

local function selOk(t)
    return not cfg("tb_sticky") or SELECTED[selKey(t)] ~= nil
end

-- reuse the stored target's rootName when resolving a selection's root
local function selRoot(ch, t)
    local h = t and t.hrp
    if h then
        local ok, alive = pcall(function() return h.Parent ~= nil end)
        if ok and alive then return h end
    end
    h = ch:FindFirstChild(t and t.rootName or "HumanoidRootPart")
    if t then t.hrp = h end
    return h
end

local function pruneSel()
    for k, t in pairs(SELECTED) do
        local ok, alive = pcall(function() return t.character.Parent ~= nil end)
        if ok and alive then
            -- still up
        elseif t.player then
            local okC, nc = pcall(function() return t.player.Character end)
            if okC and nc then
                local okP, par = pcall(function() return nc.Parent end)
                if okP and par then
                    t.character = nc
                    t.hrp = nil
                    SELECTED[k] = nil
                    local sv = SELVIS[k]
                    SELVIS[k] = nil
                    local nk = selKey(t)
                    SELECTED[nk] = t
                    if sv then SELVIS[nk] = sv end
                end
            end
            -- player-linked picks stay through death, wait for respawn
        else
            remSel(t)
        end
    end
end

local function updateSelVis(cam, lens)
    for k, t in pairs(SELECTED) do
        local sv = SELVIS[k]
        if not sv then
            local box = Drawing.new("Square")
            box.Filled, box.Color, box.Visible, box.ZIndex = false, Color3.fromRGB(255, 60, 60), false, 4
            local txt = Drawing.new("Text")
            txt.Size, txt.Color, txt.Visible, txt.ZIndex, txt.Center, txt.Outline = 13, Color3.fromRGB(255, 60, 60), false, 4, true, true
            pcall(function() txt.Font = Drawing.Fonts.SystemBold end)
            txt.Text = "TARGET"
            sv = { box = box, txt = txt }
            SELVIS[k] = sv
        end
        local show, pos = false
        local hrp = cfg("tb_selvis") and cfg("tb_sticky") and selRoot(t.character, t)
        if hrp then
            local ok
            ok, pos = pcall(function() return hrp.Position end)
            if not ok then pos = nil end
        end
        if pos then
            local sp, onScreen = WorldToScreen(pos)
            if onScreen then
                local d = dist3(cam.Position, pos)
                local pxs = (lens.vp.Y * 0.5) / math.tan(math.rad(lens.fov) * 0.5) / math.max(d, 0.05)
                local h, w = 5 * pxs, 3 * pxs
                sv.box.Position = Vector2.new(sp.X - w / 2, sp.Y - h / 2)
                sv.box.Size = Vector2.new(w, h)
                sv.txt.Position = Vector2.new(sp.X, sp.Y - h / 2 - 16)
                show = true
            end
        end
        sv.box.Visible, sv.txt.Visible = show, show
    end
end

local LOCKED, TRACK_CHAR, TRACK_POS = nil, nil, nil
local TRACK_T = 0
local TRACKED_VEL = Vector3.new(0, 0, 0)

_G.StellarTriggerbot = _G.StellarTriggerbot or {}
_G.StellarTriggerbot.LockedTarget = nil
_G.StellarTriggerbot.TargetPosition = nil

-- engagement state
local insideSince, entryDelay = nil, 0
local lastClick, nextClickIn = 0, 0
local pendingRelease, shotCount = 0, 0
local pauseUntil, stickyUntil = 0, 0
local wallBlocked, wallCheckAt = false, 0

local function resetEngagement()
    insideSince = nil
    shotCount = 0
    pauseUntil = 0
    nextClickIn = 0
    wallBlocked = false
    stickyUntil = 0
end

local function resetLock()
    LOCKED = nil
    TRACK_CHAR = nil
    TRACK_POS = nil
    TRACKED_VEL = Vector3.new(0, 0, 0)
    resetEngagement()
    _G.StellarTriggerbot.LockedTarget = nil
end

local function localPlayer()
    return Players.LocalPlayer
end

local function cursorPos()
    local lp = localPlayer()
    if lp then
        local ok, m = pcall(function() return lp:GetMouse() end)
        if ok and m and m.X and m.Y then
            return m.X, m.Y - MOUSE_Y_OFFSET
        end
    end
    local cam = Workspace.CurrentCamera
    if cam and cam.ViewportSize then
        return cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2
    end
    return 0, 0
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

local function cross2d(o, a, b)
    return (a.X - o.X) * (b.Y - o.Y) - (a.Y - o.Y) * (b.X - o.X)
end

local function convexHull(pts)
    table.sort(pts, function(a, b)
        return a.X < b.X or (a.X == b.X and a.Y < b.Y)
    end)
    if #pts < 3 then
        return pts
    end
    local lower, upper = {}, {}
    for i = 1, #pts do
        while #lower >= 2 and cross2d(lower[#lower - 1], lower[#lower], pts[i]) <= 0 do
            table.remove(lower)
        end
        lower[#lower + 1] = pts[i]
    end
    for i = #pts, 1, -1 do
        while #upper >= 2 and cross2d(upper[#upper - 1], upper[#upper], pts[i]) <= 0 do
            table.remove(upper)
        end
        upper[#upper + 1] = pts[i]
    end
    table.remove(lower)
    table.remove(upper)
    for _, p in ipairs(upper) do
        lower[#lower + 1] = p
    end
    return lower
end

local function pointInPolygon(poly, px, py)
    local inside = false
    local j = #poly
    for i = 1, #poly do
        local xi, yi = poly[i].X, poly[i].Y
        local xj, yj = poly[j].X, poly[j].Y
        if (yi > py) ~= (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function distToSeg(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
    local ex, ey = px - (ax + t * dx), py - (ay + t * dy)
    return math.sqrt(ex * ex + ey * ey)
end

local function nearPolygonEdge(poly, px, py, margin)
    local j = #poly
    for i = 1, #poly do
        if distToSeg(px, py, poly[j].X, poly[j].Y, poly[i].X, poly[i].Y) <= margin then
            return true
        end
        j = i
    end
    return false
end

-- 8 corners of the world-space hitbox
local function getCorners(pos, size)
    local c, idx = {}, 1
    for xi = -1, 1, 2 do
        for yi = -1, 1, 2 do
            for zi = -1, 1, 2 do
                c[idx] = Vector3.new(pos.X + size.X * xi, pos.Y + size.Y * yi, pos.Z + size.Z * zi)
                idx = idx + 1
            end
        end
    end
    return c
end

local EDGES = {
    { 1, 2 }, { 3, 4 }, { 5, 6 }, { 7, 8 },
    { 1, 3 }, { 2, 4 }, { 5, 7 }, { 6, 8 },
    { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

local function rootOf(t)
    local h = t.hrp
    if h then
        local ok, alive = pcall(function() return h.Parent ~= nil end)
        if ok and alive then return h end
    end
    h = t.character and t.character:FindFirstChild(t.rootName or "HumanoidRootPart")
    t.hrp = h
    return h
end

local knifeAt, knifeCached = 0, false

local function knifeOut()
    local now = tick()
    if now - knifeAt > 0.2 then
        knifeAt = now
        local lp = localPlayer()
        local char = lp and lp.Character
        knifeCached = char ~= nil and char:FindFirstChild("[Knife]") ~= nil
    end
    return knifeCached
end

-- knock check: characters in ZHD (place 138014591158268) carry a
-- BodyEffects folder with a BoolValue named "K.O" that is true for as long
-- as the player is knocked on the floor. The check stays generic: no folder
-- or failed read = not knocked, so it is drop-in portable to Da Hood /
-- other hood clones, and harmless in games without the flag.
local function isKnocked(ch)
    if not ch then return false end
    local ok, be = pcall(function() return ch:FindFirstChild("BodyEffects") end)
    if not ok or not be then return false end
    local ok2, ko = pcall(function() return be:FindFirstChild("K.O") end)
    if not ok2 or not ko then return false end
    local ok3, v = pcall(function() return ko.Value end)
    return ok3 and v == true
end

local camLens, camLensAt = nil, 0

local function lensInfo()
    local now = tick()
    if not camLens or now - camLensAt > 0.5 then
        local ok, s = pcall(function()
            local cam = Workspace.CurrentCamera
            return { vp = cam.ViewportSize, fov = cam.FieldOfView or 70 }
        end)
        if ok and s then
            camLens, camLensAt = s, now
        end
    end
    return camLens
end

local function makeTarget(character, player, rootName)
    return {
        character = character,
        player = player,
        rootName = rootName,
        hrp = character and character:FindFirstChild(rootName or "HumanoidRootPart"),
    }
end

local targetCache, targetCacheAt = nil, 0
local TARGET_CACHE_TTL = 0.2

local function invalidateTargets()
    targetCache = nil
end

local function buildTargets()
    local out = {}
    local lp = localPlayer()
    local placeId = game.PlaceId

    if placeId == 3233893879 then
        local chars = Workspace:FindFirstChild("Characters")
        if chars then
            for _, model in ipairs(chars:GetChildren()) do
                if model:IsA("Model") and model:FindFirstChild("Root") then
                    out[#out + 1] = makeTarget(model, nil, "Root")
                end
            end
        end
    elseif placeId == 292439477 then
        local playersFolder = Workspace:FindFirstChild("Players")
        if playersFolder then
            for _, team in ipairs(playersFolder:GetChildren()) do
                for _, model in ipairs(team:GetChildren()) do
                    if model:IsA("Model") then
                        local rootName = nil
                        for _, part in ipairs(model:GetChildren()) do
                            if (part:IsA("Part") or part:IsA("MeshPart")) and part.Size then
                                local s = part.Size
                                if math.abs(s.X - 2) < 0.1 and math.abs(s.Y - 2) < 0.1 and math.abs(s.Z - 1) < 0.1 then
                                    rootName = part.Name
                                end
                            end
                        end
                        if rootName then
                            out[#out + 1] = makeTarget(model, nil, rootName)
                        end
                    end
                end
            end
        end
    else
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lp and plr.Character then
                out[#out + 1] = makeTarget(plr.Character, plr, "HumanoidRootPart")
            end
        end
    end

    local folder = Workspace:FindFirstChild("Bot") or Workspace:FindFirstChild("Bots")
    if folder then
        for _, inst in ipairs(folder:GetChildren()) do
            local model = inst
            if not inst:IsA("Model") then
                model = inst:FindFirstChild("Model")
                if not model then
                    for _, child in ipairs(inst:GetChildren()) do
                        if child:IsA("Model") then
                            model = child
                            break
                        end
                    end
                end
                if not model then
                    model = inst
                end
            end
            if model:FindFirstChild("HumanoidRootPart") and model:FindFirstChild("Head") then
                out[#out + 1] = makeTarget(model, nil, "HumanoidRootPart")
            end
        end
    end

    return out
end

local function collectTargets()
    local now = tick()
    if not targetCache or now - targetCacheAt > TARGET_CACHE_TTL then
        targetCache = buildTargets()
        targetCacheAt = now
    end
    return targetCache
end

pcall(function()
    Players.PlayerAdded:Connect(invalidateTargets)
    Players.PlayerRemoving:Connect(invalidateTargets)
    Workspace.ChildAdded:Connect(function(c)
        if c.Name == "Characters" or c.Name == "Players" or c.Name == "Bot" or c.Name == "Bots" then
            invalidateTargets()
        end
    end)
    Workspace.ChildRemoved:Connect(function(c)
        if c.Name == "Characters" or c.Name == "Players" or c.Name == "Bot" or c.Name == "Bots" then
            invalidateTargets()
        end
    end)
end)

-- nearest selected target to the cursor
local function closestSelected(cx, cy)
    local best, bestDist = nil, 9e9
    for _, t in ipairs(collectTargets()) do
        local hrp = SELECTED[selKey(t)] and rootOf(t)
        if hrp then
            local ok, pos = pcall(function() return hrp.Position end)
            if ok and pos then
                local sp, onScreen = WorldToScreen(pos)
                if onScreen then
                    local d = dist2(sp.X, sp.Y, cx, cy)
                    if d < bestDist then best, bestDist = t, d end
                end
            end
        end
    end
    return best
end

local function findClosest(cx, cy, localPos, ignoreSel)
    local best, bestDist = nil, 9e9
    local maxd = cfg("tb_maxdist") or 0
    for _, t in ipairs(collectTargets()) do
        local hrp = t.hrp
        if hrp then
            local okPos, pos = pcall(function() return hrp.Position end)
            if okPos and pos and (pos.X ~= 0 or pos.Y ~= 0 or pos.Z ~= 0) and pos ~= localPos
                and (maxd <= 0 or dist3(localPos, pos) <= maxd)
                and (ignoreSel or selOk(t)) then
                local sp, onScreen = WorldToScreen(pos)
                if onScreen then
                    local d = dist2(sp.X, sp.Y, cx, cy)
                    if d < bestDist then
                        best, bestDist = t, d
                    end
                end
            end
        end
    end
    return best, bestDist
end

local function validTarget(t)
    if not t or not t.character or not t.character.Parent then return false end
    if not rootOf(t) then return false end
    if cfg("tb_knock") and isKnocked(t.character) then return false end
    local okFf, ff = pcall(function()
        return t.character:FindFirstChildOfClass("ForceField")
    end)
    return not (okFf and ff)
end

local cubeLines = nil

local function ensureDrawings()
    if cubeLines then return end
    cubeLines = {}
    for i = 1, 12 do
        local l = Drawing.new("Line")
        l.Thickness = 1
        l.Color = Color3.fromRGB(199, 171, 197)
        l.Visible = false
        cubeLines[i] = l
    end
end

local function drawCube(verts2d)
    ensureDrawings()
    for i = 1, 12 do
        local e = EDGES[i]
        cubeLines[i].From = verts2d[e[1]]
        cubeLines[i].To = verts2d[e[2]]
        cubeLines[i].Visible = true
    end
end

local function hideCube()
    if cubeLines then
        for i = 1, 12 do
            cubeLines[i].Visible = false
        end
    end
end

-- walk the ray past glass/nc parts, give up after 8 hops
local function wallBetween(pos, targetChar)
    local lp = localPlayer()
    local lpChar = lp and lp.Character
    local cam = Workspace.CurrentCamera
    local origin = (cam and cam.Position) or localRootPos()

    for _ = 1, 8 do
        local dir = pos - origin
        if dir.Magnitude < 0.05 then return false end
        local ok, res = pcall(function()
            return Workspace:Raycast(origin, dir)
        end)
        if not ok or res == nil or res.Instance == nil then return false end
        local inst = res.Instance
        if inst:IsDescendantOf(targetChar) then return false end
        local skip = (lpChar and inst:IsDescendantOf(lpChar))
            or inst.CanCollide == false
            or (inst.Transparency or 0) > 0.9
        if not skip then return true end
        if res.Position == nil then return false end
        origin = res.Position + dir.Unit * 0.15
    end
    return false
end

local function fireGun(now)
    local hold = randRange(cfg("tb_hold_min"), cfg("tb_hold_max")) / 1000
    if hold > 0.002 and pcall(mouse1press) then
        pendingRelease = now + hold
        return
    end
    pcall(mouse1click)
end

local lastErr = nil

local function step()
    local now = tick()

    if pendingRelease > 0 and now >= pendingRelease then
        pcall(mouse1release)
        pendingRelease = 0
    end

    if not cfg("tb_enabled") or not windowActive() then
        resetLock()
        hideCube()
        return
    end

    local cx, cy = cursorPos()

    pruneSel()
    do
        local cam = Workspace.CurrentCamera
        local lens = lensInfo()
        if cam and lens then updateSelVis(cam, lens) end
    end

    local localPos = localRootPos()
    local closest0 = findClosest(cx, cy, localPos, true)
    local selH = CFG.tb_selkey ~= 0 and vkHeld(CFG.tb_selkey)
    local unselH = CFG.tb_unselkey ~= 0 and vkHeld(CFG.tb_unselkey)
    if selH and not prevSelKey and closest0 then
        if SELECTED[selKey(closest0)] then remSel(closest0) else addSel(closest0) end
    end
    if unselH and not prevUnselKey then
        local st = closestSelected(cx, cy)
        if st then remSel(st) end
    end
    prevSelKey, prevUnselKey = selH, unselH

    if knifeOut() then
        return
    end

    if not keyActive() then
        resetLock()
        hideCube()
        return
    end

    local target = LOCKED
    local closest, closestDist = findClosest(cx, cy, localPos)

    if not LOCKED then
        target = closest
    elseif closest and closest.character ~= LOCKED.character then
        local lhrp = rootOf(LOCKED)
        local lockedDist = 9e9
        if lhrp then
            local lsp, lon = WorldToScreen(lhrp.Position)
            if lon then
                lockedDist = dist2(lsp.X, lsp.Y, cx, cy)
            end
        end
        if closestDist + 8 < lockedDist then
            target = closest
        end
    end

    if not validTarget(target) or not selOk(target) then
        resetLock()
        hideCube()
        return
    end

    LOCKED = target
    _G.StellarTriggerbot.LockedTarget = target.character

    local hrp = rootOf(target)
    local pos = hrp.Position

    local maxd = cfg("tb_maxdist") or 0
    if (pos.X == 0 and pos.Y == 0 and pos.Z == 0) or pos == localPos
        or (maxd > 0 and dist3(localPos, pos) > maxd) then
        resetLock()
        hideCube()
        return
    end

    if TRACK_CHAR ~= target.character then
        TRACK_CHAR = target.character
        TRACKED_VEL = Vector3.new(0, 0, 0)
        resetEngagement()
    else
        local dt = now - TRACK_T
        if dt > 0 then
            local sm = math.min(math.max(cfg("tb_pred_smooth") or 0.4, 0), 0.95)
            local iv = (pos - TRACK_POS) / dt
            TRACKED_VEL = TRACKED_VEL + (iv - TRACKED_VEL) * (1 - sm)
        end
    end
    TRACK_POS = pos
    TRACK_T = now

    if cfg("tb_pred") then
        local vel = TRACKED_VEL

        local px, py = cfg("tb_pred_x"), cfg("tb_pred_y")

        if cfg("tb_dist_pred") then
            local d = dist3(localPos, pos)
            if d <= cfg("tb_close_dist") then
                px, py = cfg("tb_close_x"), cfg("tb_close_y")
            elseif d <= cfg("tb_mid_dist") then
                px, py = cfg("tb_mid_x"), cfg("tb_mid_y")
            else
                px, py = cfg("tb_far_x"), cfg("tb_far_y")
            end
        end

        pos = pos + vel * Vector3.new(px, py, px)
    end

    _G.StellarTriggerbot.TargetPosition = pos

    local sp, onScreen = WorldToScreen(pos)
    if not onScreen then
        resetEngagement()
        hideCube()
        return
    end

    local hx, hy = cfg("tb_hitbox_x"), cfg("tb_hitbox_y")
    local inside = false

    if cfg("tb_visualize") then
        local size = Vector3.new(hx, hy, hx)
        local corners = getCorners(pos, size)

        local verts2d = {}
        local pts = {}
        local allOnScreen = true
        for i = 1, 8 do
            local cp, os2 = WorldToScreen(corners[i])
            verts2d[i] = cp
            if os2 then
                pts[#pts + 1] = cp
            else
                allOnScreen = false
            end
        end

        if allOnScreen then
            drawCube(verts2d)
        else
            hideCube()
        end

        if #pts >= 3 then
            local hull = convexHull(pts)
            inside = pointInPolygon(hull, cx, cy)
                or nearPolygonEdge(hull, cx, cy, 12)
        end
    else
        hideCube()

        local cursorD = dist2(sp.X, sp.Y, cx, cy)
        local test = true
        local lens = lensInfo()
        if lens then
            local dist = dist3(Workspace.CurrentCamera.Position, pos)
            local pxPerStud = (lens.vp.Y * 0.5)
                / math.tan(math.rad(lens.fov) * 0.5)
                / math.max(dist, 0.05)
            test = cursorD
                <= math.sqrt(hx * hx + hy * hy + hx * hx) * pxPerStud + 16
        end

        if test then
            local spx = WorldToScreen(pos + Vector3.new(hx, 0, 0))
            local spz = WorldToScreen(pos + Vector3.new(0, 0, hx))
            local spy = WorldToScreen(pos + Vector3.new(0, hy, 0))
            local hw = math.max(math.abs(spx.X - sp.X), math.abs(spz.X - sp.X))
            local hh = math.abs(spy.Y - sp.Y)
            inside = math.abs(cx - sp.X) <= hw + 12
                and math.abs(cy - sp.Y) <= hh + 12
        end
    end

    if inside then
        stickyUntil = now + 0.12
    elseif now < stickyUntil then
        inside = true
    end

    if inside then
        local fire = true
        local humOn = cfg("tb_humanize")

        if now >= wallCheckAt then
            wallCheckAt = now + 0.05
            wallBlocked = wallBetween(pos, target.character)
        end
        if wallBlocked then
            fire = false
        end

        if fire and humOn then
            if not insideSince then
                insideSince = now
                shotCount = 0
                entryDelay = randRange(cfg("tb_delay_min"), cfg("tb_delay_max")) / 1000
            end
            if now - insideSince < entryDelay
                or now - lastClick < nextClickIn
                or now < pauseUntil
            then
                fire = false
            end
        end

        if fire then
            if humOn then
                fireGun(now)
                shotCount = shotCount + 1
                nextClickIn = (randRange(cfg("tb_int_min"), cfg("tb_int_max"))
                    + math.min(shotCount, 20) * (tonumber(cfg("tb_fatigue")) or 0)) / 1000
                if math.random() * 100 < (tonumber(cfg("tb_hes_chance")) or 0) then
                    pauseUntil = now + randRange(cfg("tb_hes_min"), cfg("tb_hes_max")) / 1000
                end
            else
                pcall(mouse1click)
            end
            lastClick = now
        end
    else
        resetEngagement()
    end
end

local function safeStep()
    local ok, err = pcall(step)
    if not ok and err ~= lastErr then
        lastErr = err
        warn("triggerbot error: " .. tostring(err))
    end
end

local loopHooked = false
pcall(function()
    local rs = game:GetService("RunService")
    if rs and rs.Heartbeat then
        rs.Heartbeat:Connect(safeStep)
        loopHooked = true
    end
end)

if not loopHooked then -- fallback if Heartbeat isn't there
    spawn(function()
        while true do
            safeStep()
            wait(0.001)
        end
    end)
end

-- dark menu (Drawing api, outside matcha's ui)
local C = {
    bg = Color3.fromRGB(17, 17, 20),
    border = Color3.fromRGB(44, 44, 52),
    accent = Color3.fromRGB(199, 171, 197),
    text = Color3.fromRGB(205, 205, 210),
    dim = Color3.fromRGB(120, 120, 128),
    off = Color3.fromRGB(45, 45, 52),
    bar = Color3.fromRGB(38, 38, 45),
    panel = Color3.fromRGB(24, 24, 29),
}

local MW, MH = 560, 316
local COLW, ROWH, TITLEH = 300, 20, 28
local SIDEW, TABH = 104, 26

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

local COLUMNS = {
    { title = "general", widgets = {
        { kind = "toggle", id = "tb_enabled", label = "enabled" },
        { kind = "bind", id = "tb_key", label = "keybind" },
        { kind = "toggle", id = "tb_knock", label = "knock check" },
        { kind = "note", label = "wont aim at knocked" },
        { kind = "toggle", id = "tb_visualize", label = "visualize" },
        { kind = "slider", id = "tb_maxdist", label = "max dist", min = 0, max = 2000, fmt = "%d" },
        { kind = "slider", id = "tb_hitbox_x", label = "hitbox x", min = 0.1, max = 5.0, fmt = "%.1f" },
        { kind = "slider", id = "tb_hitbox_y", label = "hitbox y", min = 0.5, max = 8.0, fmt = "%.1f" },
    }},
    { title = "targeting", widgets = {
        { kind = "toggle", id = "tb_sticky", label = "sticky aim" },
        { kind = "note", label = "only selected targets" },
        { kind = "note", label = "will be shot at" },
        { kind = "bind", id = "tb_selkey", label = "select key" },
        { kind = "bind", id = "tb_unselkey", label = "unselect key" },
        { kind = "toggle", id = "tb_selvis", label = "target visuals" },
        { kind = "note", label = "red box + TARGET on" },
        { kind = "note", label = "selected players" },
    }},
    { title = "accuracy", widgets = {
        { kind = "toggle", id = "tb_pred", label = "prediction" },
        { kind = "slider", id = "tb_pred_x", label = "pred x", min = 0.0, max = 0.5, fmt = "%.3f" },
        { kind = "slider", id = "tb_pred_y", label = "pred y", min = 0.0, max = 0.5, fmt = "%.3f" },
        { kind = "slider", id = "tb_pred_smooth", label = "vel smooth", min = 0.0, max = 0.9, fmt = "%.2f" },
        { kind = "toggle", id = "tb_dist_pred", label = "distance based" },
        { kind = "slider", id = "tb_close_dist", label = "close dist", min = 1, max = 150, fmt = "%d" },
        { kind = "slider", id = "tb_close_x", label = "close x", min = 0.0, max = 0.5, fmt = "%.3f" },
        { kind = "slider", id = "tb_close_y", label = "close y", min = 0.0, max = 0.5, fmt = "%.3f" },
        { kind = "slider", id = "tb_mid_dist", label = "mid dist", min = 1, max = 300, fmt = "%d" },
        { kind = "slider", id = "tb_mid_x", label = "mid x", min = 0.0, max = 0.5, fmt = "%.3f" },
        { kind = "slider", id = "tb_mid_y", label = "mid y", min = 0.0, max = 0.5, fmt = "%.3f" },
        { kind = "slider", id = "tb_far_x", label = "far x", min = 0.0, max = 0.5, fmt = "%.3f" },
        { kind = "slider", id = "tb_far_y", label = "far y", min = 0.0, max = 0.5, fmt = "%.3f" },
    }},
    { title = "humanization", widgets = {
        { kind = "toggle", id = "tb_humanize", label = "enabled" },
        { kind = "slider", id = "tb_delay_min", label = "react min", min = 0, max = 500, fmt = "%dms" },
        { kind = "slider", id = "tb_delay_max", label = "react max", min = 0, max = 500, fmt = "%dms" },
        { kind = "slider", id = "tb_int_min", label = "int min", min = 0, max = 1000, fmt = "%dms" },
        { kind = "slider", id = "tb_int_max", label = "int max", min = 0, max = 1000, fmt = "%dms" },
        { kind = "slider", id = "tb_hold_min", label = "hold min", min = 0, max = 300, fmt = "%dms" },
        { kind = "slider", id = "tb_hold_max", label = "hold max", min = 0, max = 300, fmt = "%dms" },
        { kind = "slider", id = "tb_hes_chance", label = "hesit %", min = 0, max = 100, fmt = "%d%%" },
        { kind = "slider", id = "tb_hes_min", label = "hesit min", min = 0, max = 2000, fmt = "%dms" },
        { kind = "slider", id = "tb_hes_max", label = "hesit max", min = 0, max = 2000, fmt = "%dms" },
        { kind = "slider", id = "tb_fatigue", label = "fatigue", min = 0, max = 100, fmt = "%dms" },
    }},
    { title = "configs", widgets = {} },
}

local CFG_DIR = "triggerbot"

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

local menuBuilt = false
local function buildMenu()
    if menuBuilt then return end
    menu.bg = newSq(C.bg, 1)
    menu.border = newSq(C.border, 0)
    menu.titleBar = newSq(C.border, 2)
    menu.sideBg = newSq(C.panel, 1)
    menu.titleTxt = newTxt(15, C.accent, 3)
    menu.titleTxt.Text = "triggerbot"
    menu.foot = newTxt(12, C.dim, 3)
    menu.foot.Text = "backspace to hide"
    menu.chrome = { menu.bg, menu.border, menu.titleBar, menu.sideBg, menu.titleTxt, menu.foot }

    for ci, col in ipairs(COLUMNS) do
        col.tabBg = newSq(C.panel, 2)
        col.hdObj = newTxt(13, C.text, 3)
        col.hdObj.Text = col.title
        menu.chrome[#menu.chrome + 1] = col.tabBg
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
                r.barBg = reg(newSq(C.bar, 3))
                r.barFill = reg(newSq(C.accent, 3))
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
    for _, o in ipairs({ menu.mpBg, menu.mpBorder }) do o.Visible = on end
    for i = 1, 3 do menu.mpTxts[i].Visible = on end
    if not on then return end
    local pw, ph = 84, 3 * 16 + 8
    local px = r.x + COLW - pw
    local py = r.y + ROWH + 2
    menu.mpBorder.Position = Vector2.new(px - 1, py - 1)
    menu.mpBorder.Size = Vector2.new(pw + 2, ph + 2)
    menu.mpBg.Position = Vector2.new(px, py)
    menu.mpBg.Size = Vector2.new(pw, ph)
    r.opts = {}
    for i, m in ipairs(MODE_OPTS) do
        local ty = py + 4 + (i - 1) * 16
        local t = menu.mpTxts[i]
        t.Position = Vector2.new(px + 8, ty)
        t.Text = m
        t.Color = CFG.tb_kbmode == m and C.accent or C.text
        r.opts[i] = { px, ty - 2, pw, 16 }
    end
end

local function layoutConfirm()
    local on = menu.confirm ~= nil
    for _, o in ipairs({ menu.cfBg, menu.cfBorder, menu.cfTxt, menu.cfYes, menu.cfYesTxt, menu.cfNo, menu.cfNoTxt }) do
        o.Visible = on
    end
    if not on then return end
    local bw, bh = 210, 64
    local bx = menu.x + SIDEW + (MW - SIDEW - bw) / 2
    local by = menu.y + TITLEH + (MH - TITLEH - bh) / 2
    menu.cfBorder.Position = Vector2.new(bx - 1, by - 1)
    menu.cfBorder.Size = Vector2.new(bw + 2, bh + 2)
    menu.cfBg.Position = Vector2.new(bx, by)
    menu.cfBg.Size = Vector2.new(bw, bh)
    menu.cfTxt.Position = Vector2.new(bx + 12, by + 10)
    menu.cfTxt.Text = menu.confirm.act == "del"
        and ("delete '" .. menu.confirm.name .. "'?")
        or ("overwrite '" .. menu.confirm.name .. "'?")
    menu.cfYes.Position = Vector2.new(bx + 12, by + bh - 24)
    menu.cfYes.Size = Vector2.new(60, 16)
    menu.cfYesTxt.Position = Vector2.new(bx + 34, by + bh - 22)
    menu.cfNo.Position = Vector2.new(bx + bw - 72, by + bh - 24)
    menu.cfNo.Size = Vector2.new(60, 16)
    menu.cfNoTxt.Position = Vector2.new(bx + bw - 48, by + bh - 22)
    menu.confirm.yes = { bx + 12, by + bh - 24, 60, 16 }
    menu.confirm.no = { bx + bw - 72, by + bh - 24, 60, 16 }
end

local function tabY(i)
    return menu.y + TITLEH + 8 + (i - 1) * TABH
end

local function layoutMenu()
    menu.border.Position = Vector2.new(menu.x - 1, menu.y - 1)
    menu.border.Size = Vector2.new(MW + 2, MH + 2)
    menu.bg.Position = Vector2.new(menu.x, menu.y)
    menu.bg.Size = Vector2.new(MW, MH)
    menu.titleBar.Position = Vector2.new(menu.x, menu.y)
    menu.titleBar.Size = Vector2.new(MW, TITLEH)
    menu.sideBg.Position = Vector2.new(menu.x, menu.y + TITLEH)
    menu.sideBg.Size = Vector2.new(SIDEW, MH - TITLEH)
    menu.titleTxt.Position = Vector2.new(menu.x + 8, menu.y + 6)
    menu.foot.Position = Vector2.new(menu.x + 8, menu.y + MH - 19)

    for ci, col in ipairs(COLUMNS) do
        local ty = tabY(ci)
        col.tabBg.Position = Vector2.new(menu.x + 2, ty - 2)
        col.tabBg.Size = Vector2.new(SIDEW - 4, TABH)
        col.tabBg.Color = ci == menu.tab and C.bar or C.panel
        col.hdObj.Position = Vector2.new(menu.x + 12, ty + 4)
        col.hdObj.Color = ci == menu.tab and C.accent or C.dim
    end

    local cx = menu.x + SIDEW + 16
    for ci, col in ipairs(COLUMNS) do
        local ri = 0
        for _, r in ipairs(menu.rows) do
            if r.col == ci then
            ri = ri + 1
            local w = r.w
            local ry = menu.y + TITLEH + 12 + (ri - 1) * ROWH
            r.x, r.y = cx, ry
            r.label.Position = Vector2.new(cx, ry + 3)
            if w.kind == "toggle" then
                r.box.Position = Vector2.new(cx + COLW - 16, ry + 5)
                r.box.Size = Vector2.new(10, 10)
                r.box.Color = CFG[w.id] and C.accent or C.off
            elseif w.kind == "slider" then
                r.barBg.Position = Vector2.new(cx + COLW - 140, ry + 7)
                r.barBg.Size = Vector2.new(80, 6)
                local f = math.max(0, math.min(1, (CFG[w.id] - w.min) / (w.max - w.min)))
                r.barFill.Position = r.barBg.Position
                r.barFill.Size = Vector2.new(80 * f, 6)
                r.valTxt.Position = Vector2.new(cx + COLW - 52, ry + 4)
                if menu.editing == r then
                    r.valTxt.Text = menu.editBuf .. "_"
                    r.valTxt.Color = C.accent
                elseif w.id == "tb_maxdist" and CFG[w.id] <= 0 then
                    r.valTxt.Text = "off"
                    r.valTxt.Color = C.dim
                else
                    r.valTxt.Text = string.format(w.fmt, CFG[w.id])
                    r.valTxt.Color = C.text
                end
            elseif w.kind == "note" then
                r.label.Color = C.dim
            elseif w.kind == "bind" then
                r.label.Text = w.id == "tb_key"
                    and ("keybind  " .. tostring(CFG.tb_kbmode)) or w.label
                r.box.Position = Vector2.new(cx + COLW - 48, ry + 4)
                r.box.Size = Vector2.new(40, 13)
                r.box.Color = menu.listening == r and C.accent or C.bar
                r.valTxt.Position = Vector2.new(cx + COLW - 45, ry + 5)
                r.valTxt.Text = vkName(CFG[w.id])
                r.valTxt.Color = menu.listening == r and C.bg or C.accent
            elseif w.kind == "text" then
                r.box.Position = Vector2.new(cx + COLW - 140, ry + 3)
                r.box.Size = Vector2.new(136, 14)
                r.box.Color = menu.editing == r and C.accent or C.bar
                r.valTxt.Position = Vector2.new(cx + COLW - 136, ry + 4)
                r.valTxt.Text = menu.editing == r and (menu.editBuf .. "_") or menu.cfgName
                r.valTxt.Color = menu.editing == r and C.bg or C.accent
            elseif w.kind == "button" then
                r.label.Text = ""
                r.box.Position = Vector2.new(cx, ry + 2)
                r.box.Size = Vector2.new(COLW - 8, 16)
                r.box.Color = C.bar
                r.valTxt.Position = Vector2.new(cx + 8, ry + 4)
                r.valTxt.Text = "create config"
                r.valTxt.Color = C.accent
            elseif w.kind == "file" then
                r.fileName = menu.cfgFiles[r.fileIdx]
                r.label.Text = r.fileName or ""
                r.label.Color = C.text
                r.loadTxt.Position = Vector2.new(cx + COLW - 92, ry + 3)
                r.loadTxt.Text = r.fileName and "load" or ""
                r.saveTxt.Position = Vector2.new(cx + COLW - 56, ry + 3)
                r.saveTxt.Text = r.fileName and "save" or ""
                r.valTxt.Position = Vector2.new(cx + COLW - 18, ry + 3)
                r.valTxt.Text = r.fileName and "x" or ""
            end
            end
        end
    end
end

local function setMenuVisible(b)
    if not b then
        for _, o in ipairs(menu.objs) do o.Visible = false end
        return
    end
    for _, o in ipairs(menu.chrome) do o.Visible = true end
    for _, r in ipairs(menu.rows) do
        local on = r.col == menu.tab
        for _, o in ipairs(r.vis) do o.Visible = on end
    end
end

local function inRect(mx, my, x, y, w, h)
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
    return nil
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
                    -- numbers only here
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
        if not menu.open then
            setMenuVisible(false)
            menu.listening, menu.dragging, menu.slider = nil, nil, nil
            menu.editing = nil
        end
    end
    menu.prevIns = ins
    if not menu.open then return end

    layoutMenu()

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

    -- key capture for the bind row
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
        elseif inRect(mx, my, menu.x, menu.y + TITLEH, SIDEW, MH - TITLEH) then
            local ti = math.floor((my - menu.y - TITLEH - 8) / TABH) + 1
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
        menu.x, menu.y = mx - menu.dragging[1], my - menu.dragging[2]
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
