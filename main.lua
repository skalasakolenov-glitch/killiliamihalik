--[[
    nyx.lua  -  silent aim + bhop + directional autostrafe + player ESP, skeet-style menu
    Engine : Garry's Mod, clientside Lua (CreateMove / CalcView / HUDPaint / VGUI)
    Run    : garrysmod/lua/autorun/client/nyx.lua   (loads on join)
             or  sv_allowcslua 1  +  lua_openscript_cl nyx.lua
    Keys   : INSERT = menu, CTRL+F = function search (unload: Config tab button)
    Works on any GMod server / gamemode (no Rust-specific classes).
]]

if NyxUnload then pcall(NyxUnload) end   -- re-running the file replaces the old instance

local ID = "nyx_"
local addedHooks = {}

local function AddHook(event, name, fn)
    hook.Add(event, ID .. name, fn)
    addedHooks[#addedHooks + 1] = {event, ID .. name}
end

-- ---------------------------------------------------------------------------
-- config
-- ---------------------------------------------------------------------------

-- one anti-aim profile (standing / moving / in air each get their own)
local function AAState()
    return {
        pitchMode    = "down",     -- none | down | up | zero | jitter | random | custom
        pitchValue   = 89,         -- custom pitch
        yawBase      = "view",     -- view | static | target
        yawOffset    = 180,
        yawMod       = "jitter",   -- none | jitter | random | spin | sway | switch
        modRange     = 30,         -- degrees (jitter / random / sway amplitude)
        modSpeed     = 360,        -- deg/s (spin, sway); negative spins the other way
        modInterval  = 1,          -- ticks between jitter flips / random re-rolls / switches
        switchOffset = -90,        -- second yaw offset for "switch"
        noise        = 0,          -- extra random yaw on top, +-degrees
        roll         = 0,
    }
end

local cfg = {
    aim = {
        enabled    = false,
        silent     = true,         -- rewrite the sent cmd only, screen stays on your real view
        fireOnly   = true,         -- silent: only on ticks where you shoot
        autoFire   = false,        -- pull the trigger yourself once a target is locked
        sticky     = true,         -- stay on the current target while it's still valid
        key        = MOUSE_RIGHT,
        fov        = 8,            -- degrees, radius around your crosshair
        smooth     = 6,            -- only used when silent is off (1 = instant, 30 = slow)
        maxDist    = 300,          -- metres
        hitbox     = "head",       -- head | chest | pelvis
        fallback   = true,         -- hitbox blocked -> try the other ones
        priority   = "fov",        -- fov | distance | health
        visCheck   = true,
        teamCheck  = false,
        ignoreFriends = true,
        targetOnly = false,        -- only players marked as targets in the Players tab
        recoilOn   = false,
        recoil     = 1,            -- view-punch compensation (2 = css style)
        predictOn  = false,
        predict    = 3,            -- ticks of target velocity to lead
        humanizeOn = false,
        humanize   = 2,            -- units of random aim-point wobble
        extrapOn   = false,        -- extrapolation (settings in cfg.extrap, shared with rage)
        drawFov    = true,
        drawTarget = true,
    },
    move = {
        bhop       = true,
        autostrafe = true,
        strafeMode = "directional", -- directional | mouse
        circle         = false,    -- adaptive circle strafe (bind it: hold)
        circleSide     = "left",   -- left | right
        circleAvoid    = true,     -- flip the circle when a wall is in the way
        circleMinSpeed = 40,       -- below this it just pushes along the view
        edgebug     = false,       -- lobotomy-style edge bug (bind it: hold)
        ebTicks     = 32,          -- how many ticks ahead each variant is simulated
        ebAdvanced  = true,        -- also the variants with your keys and the mouse still turning
        ebTurnScale = 1,           -- how much of the current mouse turn those variants keep
        ebLock      = 0.6,         -- mouse slowed this much while an edge bug is lined up
        ebDraw      = true,        -- predicted fall path / lined-up edge bug on screen
        ebIndicator = true,        -- "edgebug" on screen when one happens
        ebSteer     = false,       -- advanced: a fan of strafe directions, steers you onto the edge
        ebLines     = 12,          -- advanced: strafe directions in the fan (each ducked + standing)
        ebSpread    = 180,         -- advanced: degrees either side of your flight the fan covers
        ebFanEvery  = 2,           -- advanced: the fan is searched every N ticks (it's the costly part)
        -- texture bug (hackvshack texturebug.cpp)
        texturebug  = false,       -- bruteforce of tiny presses at the wall (bind it: hold)
        tbFwd1      = 0.1,         -- the two press strengths of your own tried first
        tbFwd2      = 0.25,
        tbAngleStart = 0,          -- angles to the wall that are tried, degrees
        tbAngleEnd  = 90,
        tbWiggle    = 3,           -- step between them (smaller = finer and slower)
        tbHug       = 0.5,         -- wall hug when the closest gap left is under this
        tbZStep     = 6,           -- wall scan: one line every this many units of hull height
        tbBothDuck  = true,        -- in the air also try the other duck state (twice the work)
        tbBudget    = 150,         -- bruteforce candidates simulated per tick (the rest next ticks)
        tbAhead     = 3,           -- a press counts if it catches within this many ticks
        simQuads    = false,       -- simulation: SDK 2013 quarter-hull ground check (GMod: off)
        -- wall hang: the texture bug's catch on any wall, diagonal / slanted ones included;
        -- it uses the texture bug's search settings above
        wallhang    = false,       -- bind it: hold
        whApproach  = 6,           -- closes in on a wall up to this many units off the hull
        -- module: no packet goes out, so the server stops simulating you where you are
        airstuck    = false,       -- bind it: hold
        asMax       = 4,           -- seconds at most (then it lets go until pressed again)
    },
    esp = {
        enabled   = true,
        box       = true,
        name      = true,
        health    = true,
        -- the HP number (settings of the health bar)
        hpText    = true,
        hpPos     = "follow",      -- follow (beside the top of the bar) | top (above the bar) | below (under the box)
        hpPercent = false,         -- 73% instead of 73
        hpHideFull = false,        -- no number while at full health
        hpColor   = "bar",         -- bar (green .. red like the bar) | text (the ESP colour) | custom
        hpR = 255, hpG = 255, hpB = 255,
        weapon    = true,
        distance  = true,
        teamColor = false,
        teamCheck = false,
        maxDist   = 4000,          -- metres
        r = 255, g = 255, b = 255, -- box / text colour
        dormant     = true,        -- keep drawing players that left the PVS, at their last position
        dormantTime = 8,           -- seconds they stay visible, fading out
    },
    view = {
        thirdperson = false,
        distance    = 90,          -- units behind the head
        shoulder    = 0,           -- + right / - left
        height      = 0,
        fovOn       = false,
        fov         = 100,
        aspectOn    = false,
        aspect      = 1.7778,      -- width / height
    },
    free = {                       -- free camera
        enabled  = false,
        speed    = 700,            -- units / s
        boost    = 3,              -- multiplier while SPRINT is held
    },
    vm = {                         -- viewmodel manipulation
        offsetOn = false,
        x = 0, y = 0, z = 0,
        fovOn    = false,
        fov      = 70,
    },
    taunt = {
        enabled  = false,
        name     = "dance",
        interval = 1.0,            -- seconds
        move     = true,           -- keep moving / aiming while the taunt plays
        hideFirst = true,          -- first person: no taunt camera, the model is not drawn
    },
    interp = {
        mode = "default",          -- default | low | off | smooth
    },
    nospread = {                   -- default HL2 weapons only (pistol, smg1, ar2)
        enabled    = false,
        seedOffset = 0,            -- added to the low byte of the prediction seed (+1 is the usual variant)
        scale      = 1,            -- multiplies the weapon's cone, for tuning
        bases      = false,        -- SWB / CW 2.0 too (ak47hack's way, experimental: seeded by the
                                   -- command number, which only matches if the base does the same)
    },
    norecoil = {                   -- your own shots (the aimbots have their own recoil setting)
        enabled    = false,        -- the view punch taken off the sent angle on shot ticks
        scale      = 1,            -- 1 = exactly the punch (2 = the CS:S style double)
        exceptions = true,         -- skip weapons that don't kick through the punch (M9K, HL2 pistol ...)
    },
    tpose = {
        enabled     = false,       -- every player drawn in the reference pose
        includeSelf = true,
    },
    seq = {                        -- local animation sequence override (you see it, others don't)
        enabled = false,
        index   = 0,
    },
    resolver = {
        enabled = false,
        mode    = "step",          -- step: +step degrees per shot | list: -180,-120,...,180 per shot
        step    = 45,              -- degrees added to the target's yaw after every shot of yours
        reset   = 6,               -- seconds without shots before the target goes back to 0
        pitch   = false,           -- also fix a pitch pinned at the limits
        memory       = true,       -- memory resolver: reuse the offset that last hit this player
        memoryMisses = 2,          -- misses in a row before the remembered offset is given up on
        memoryTime   = 180,        -- seconds an entry stays valid
    },
    model = {                      -- custom player model, client side only (nobody else sees it)
        self        = false,
        selfModel   = "models/player/kleiner.mdl",
        others      = false,
        othersModel = "models/player/combine_soldier.mdl",
        teamCheck   = false,       -- others: leave your teammates alone
    },
    glow = {
        enabled      = false,
        r = 255, g = 80, b = 80,
        width        = 2,
        throughWalls = true,
        teamCheck    = false,
        self         = false,      -- yourself, third person / free camera only
        selfR = 80, selfG = 180, selfB = 255,
    },
    killsay = {
        enabled = false,
        set     = "english",       -- english | russian | both | custom
        delay   = 0.6,             -- seconds after the kill
        custom  = "",              -- set with the console command nyx_killsay <text> ({name} = victim)
    },
    world = {
        enabled    = false,        -- entity ESP over the whole map
        npc        = true,
        weapon     = true,         -- weapons lying around
        prop       = false,
        vehicle    = true,
        item       = true,         -- item_* / ammo_*
        door       = false,
        other      = true,         -- Lua (scripted) entities: printers, shipments, ...
        box        = true,
        name       = true,
        distance   = true,
        glow       = false,        -- halo through walls
        maxDist    = 2000,         -- metres
        fullbright = false,
        noFog      = false,
        -- custom fog
        fogOn      = false,
        fogR = 170, fogG = 180, fogB = 200,
        fogStart   = 0,            -- units
        fogEnd     = 4000,
        fogDensity = 1,            -- 0..1, how thick it gets at fogEnd
        -- night mode darkens the map and the sky, players and props stay lit
        night       = false,
        nightAmount = 0.7,
        nightScreen = false,       -- also dim the screen itself (fallback / stronger)
        -- custom time of day: map light, sky colours, dusk, stars and sun follow the hour
        -- (overrides night mode while on)
        timeOn      = false,
        timeHour    = 12,          -- 0..24
        timeCycle   = false,       -- the hour runs on by itself
        timeSpeed   = 10,          -- in-game hours per real minute while cycling
        timeScreen  = true,        -- also tint the screen: players / dynamic props, and maps whose
                                   -- materials ignore the tint
        -- skybox changer
        skyPreset  = "default",    -- default or a sky name (see SKY_PRESETS)
        skyTint    = false,
        skyR = 255, skyG = 255, skyB = 255,
        skySolid   = false,        -- replace the sky with a flat colour
        solidR = 15, solidG = 18, solidB = 40,
        skyPic     = false,        -- your own picture wrapped around the sky
        skyPicFile = "",           -- a file in data/nyx/bg/
        skyPicRot  = 0,            -- degrees per second the sky turns
        skyPicBright = 1,
    },
    entview = {                    -- Entities tab: list + 3D viewer
        filter    = "all",         -- all | player | npc | weapon | prop | vehicle | item | door | other | any
        highlight = true,          -- halo on the selected entity
        live      = true,          -- the copy follows the real entity (pose, skin, weapon...)
        spin      = false,         -- the viewer turns on its own
        lit       = true,          -- studio light (off: the map's light where the entity stands)
        -- chams on entities picked in the list (right-click a row); which ones is kept in
        -- data/nyx/entities.json, the look here
        chamMat   = "glow",
        chamR = 255, chamG = 140, chamB = 40,
        chamAlpha = 200,
        chamWalls = true,          -- seen through walls (off: only where the entity is visible)
        -- wallhack on entities picked the same way (right-click a row)
        espBox    = true,
        espName   = true,
        espDist   = true,
        espHealth = true,          -- bar for entities that have health (gRust HP included)
        espLine   = false,         -- line from the bottom of the screen
        espGlow   = false,         -- outline through walls
        espR = 90, espG = 220, espB = 255,
        espMax    = 1000,          -- metres
        searchNW  = false,         -- the list search also looks through NWVar names / values
        showPlayers = false,       -- players in the list too (they have their own tab)
    },
    chams = {
        enabled      = false,      -- master switch for every kind of chams below
        players      = true,       -- other players
        edit         = "players",  -- which look the menu sliders edit: players | self
        teamCheck    = false,      -- skip teammates
        material     = "flat",     -- flat | wireframe | shiny | shield
        throughWalls = true,       -- second, always-visible pass in the "hidden" colour
        alpha        = 254,        -- 20..254
        visR = 120, visG = 255, visB = 80,
        hidR = 255, hidG = 60,  hidB = 60,
        self         = false,      -- your own model (third person only)
        selfMaterial = "shield",
        selfAlpha    = 200,
        selfR = 90, selfG = 160, selfB = 255,
        hands        = false,      -- first person arms
        weapon       = false,      -- first person weapon (viewmodel); shares the hands' look
        handMaterial = "glow",
        handAlpha    = 254,
        handR = 255, handG = 140, handB = 60,
    },
    bagspam = {                    -- presses use on the nearest item bag, every tick
        enabled = false,
        class   = "rust_itembag",  -- change with the console command  nyx_bag_class <class>
        range   = 80,              -- units, the game's use reach is about 80
        aim     = true,            -- also turn (silently) onto the bag
        mode    = "rate",          -- none | rate (cl_cmdrate 128) | burst (cl_cmdrate low: uses go out in clumps) | net
        burstRate = 10,            -- cl_cmdrate while bursting
        netCount  = 10,            -- net mode: gRust.Interact messages sent in one frame
        netWait   = 1.0,           -- net mode: seconds before the same bag gets another burst
    },
    netlog = {                     -- logs the net messages you send (to see what a menu really sends)
        enabled  = false,
        print    = true,           -- every message to the console as it goes out
        incoming = false,          -- also server -> you (name, size and every value the receiver reads)
    },
    removals = {                   -- things the game draws / does to your screen, switched off
        enabled    = false,        -- master switch: nothing below applies while it is off
        shake      = true,         -- screen shake (explosions, env_shake)
        punch      = true,         -- view punch: the recoil kick of the camera
        bob        = false,        -- viewmodel bob / sway
        viewmodel  = false,        -- the weapon and hands in first person
        fog        = false,
        hudDamage  = true,         -- red damage indicator
        hudCrosshair = false,
        hudHealth  = false,        -- health + suit
        hudAmmo    = false,
        hudWeapons = false,        -- weapon selection
        hudPickup  = false,        -- pickup history
        hudKillfeed = false,
        motionBlur = false,
        decals     = false,
        shells     = false,        -- ejected brass
        ragdolls   = false,
    },
    killfx = {                     -- effects on a kill of yours
        enabled  = false,
        ring     = true,           -- shockwave rings on the floor
        burst    = true,           -- glowing sparks thrown up and out
        bolt     = true,           -- lightning strike
        souls    = true,           -- orbs rising from the spot
        text     = true,           -- KILL / DOUBLE KILL ... above the spot
        flash    = false,          -- coloured frame around the screen
        sparks   = true,           -- the engine's own energy explosion
        pillar   = false,          -- column of light shooting up from the spot
        vortex   = false,          -- sparks spiralling in and up, like a small tornado
        fireworks = false,         -- three rockets that burst into coloured stars
        confetti = false,          -- paper bits thrown up, fluttering down
        dome     = false,          -- wireframe dome growing over the spot
        ghost    = false,          -- a see-through copy of the victim floating up
        hitmarker = false,         -- X around your crosshair
        banner   = false,          -- big streak text at the top of the screen
        shake    = false,          -- short screen shake
        scorch   = false,          -- scorch mark on the floor (only you see it)
        sound    = "off",          -- off | a sound file
        ragdoll  = "off",          -- off | gold | ice | color | dissolve | neon | chrome | energy | void | pulse | selfillum
        rainbow  = false,
        r = 255, g = 60, b = 140,
        life     = 2.0,            -- seconds
        count    = 36,             -- sparks in the burst
        scale    = 1,
    },
    hits = {                       -- your hits on players
        marker   = true,           -- X around the crosshair
        world    = true,           -- X where the hit landed
        numbers  = true,           -- the damage rising from that spot
        logs     = true,           -- "Hit X in the head for 34 (66 left)" in the top left
        logMiss  = true,           -- aimbot shots that hit nothing
        logTime  = 5,              -- seconds a line stays
        console  = true,           -- the lines in the console too
        sound    = "off",
        r = 255, g = 255, b = 255, -- marker colour (a kill is red, a headshot orange)
    },
    xind = {                       -- indicators under the crosshair
        enabled  = false,
        name     = "nyx",          -- the title line, shown as written (rename it in the menu)
        offset   = 22,             -- pixels under the crosshair
        state    = true,           -- STAND / MOVE / CROUCH / AIR
        minDamage = true,          -- the rage bot's minimum damage, top right of the crosshair
        features = true,           -- BAIM, AA, FAKELAG ... while they are on
        r = 150, g = 185, b = 255, -- title colour
    },
    tracers = {
        enabled = false,
        life    = 1.5,             -- seconds
        width   = 3,
        r = 255, g = 70, b = 70,
    },
    backtrack = {                  -- both aimbots: shoot at where a player was a moment ago
        enabled = false,
        ms      = 150,             -- how far back, the server accepts about 200 ms
        draw    = true,            -- dots on the records of the aim target
    },
    rage = {
        enabled       = false,
        fov           = 180,       -- degrees around your view, 180 = everything
        drawFov       = false,     -- circle of that fov on the screen (not drawn at 180)
        fovR = 255, fovG = 90, fovB = 90,
        drawTarget    = true,      -- marker on the point the rage bot is shooting at
        maxDist       = 500,       -- metres
        autoFire      = true,
        holdFire      = true,      -- keep IN_ATTACK down every tick (semi-auto guns get re-pressed)
        autoStop      = true,      -- zero the move vector on the shot tick (ground only)
        visOnly       = true,
        autowall      = false,     -- with Visible only: also shoot targets behind walls that go through
        wallPower     = 40,        -- "units of soft wall" a shot can push through
        wallCount     = 2,         -- most walls one shot may cross
        wall = {                   -- which kinds of surface count as shoot-through
            glass = true, wood = true, plastic = true, thin = true, tile = true,
            dirt = true, other = true, concrete = false, metal = false,
        },
        teamCheck     = false,
        ignoreFriends = true,
        targetOnly    = false,     -- only players marked as targets in the Players tab
        priority      = "distance", -- distance | health | fov
        head          = true,
        chest         = true,
        pelvis        = false,
        arms          = false,     -- the model's arm / leg hitboxes (only real hitboxes have these)
        legs          = false,
        -- from ak47hack's rage bot ------------------------------------------------------------
        realHitboxes  = true,      -- aim at the centre of the model's hitbox boxes, not at the bone
        multipoint    = false,     -- also the corners of each hitbox box, pulled in by mpScale
        mpScale       = 0.75,      -- 1 = the box's own corners, 0.5 = halfway to the centre
        mpHead        = true,
        mpBody        = true,      -- chest + pelvis
        mpLimbs       = false,
        weaponWall    = true,      -- SWB / M9K weapons: their own penetration rules decide the autowall
        maxTargets    = 0,         -- scan only the N nearest players each tick (0 = all)
        ignoreBots    = false,
        ignoreAdmins  = false,
        ignoreFrozen  = false,
        ignoreNoclip  = false,
        ignoreGod     = false,     -- spawn protection: GMod fades the model (alpha < 255)
        ignoreVehicle = false,
        ignoreNodraw  = false,
        skipReload    = true,      -- no aiming while the reload animation plays
        autoReload    = false,     -- empty clip + ammo left: press reload
        -- ----------------------------------------------------------------------------------------
        bodyBelow     = 0,         -- target HP at/below which the body is tried before the head (0 = off)
        minDamage     = 0,         -- a hitbox is skipped when the estimated damage is lower (0 = off;
                                   -- a hit that would kill always counts)
        minDmgOverride = false,    -- bind it: while on, the override value is the minimum instead
        minDmgOverrideValue = 1,
        forceBaim     = false,     -- bind it: no head, body hitboxes only
        recoilOn      = true,
        recoil        = 1,
        predictOn     = false,
        predict       = 3,
        extrapOn      = false,     -- extrapolation (settings in cfg.extrap, shared with aim)
    },
    extrap = {                     -- shared by the aimbot and the rage bot (each has its own switch)
        lcBreak     = true,        -- hitscan: lead players who break lag compensation
        projectile  = "auto",      -- off | auto (known weapons) | always
        projSpeed   = 3500,        -- "always": projectile speed, u/s
        projGravity = 0,           -- "always": share of sv_gravity acting on it
        strafe      = true,        -- curve the path by an air strafer's turn
        bhop        = true,        -- a bhopper jumps again when the path lands
        maxTicks    = 32,          -- longest simulated lead
        draw        = false,       -- predicted path + hull on screen
        r = 80, g = 200, b = 255,
    },
    aa = {
        enabled      = false,
        indicator    = true,
        sameForAll   = true,       -- use the "stand" profile everywhere
        sel          = "stand",    -- profile being edited in the menu
        realOnShoot  = true,       -- real view while IN_ATTACK is held
        onShot       = false,      -- real view only on the tick a shot really goes out
        hideShots    = false,      -- lower cl_cmdrate while shooting: the shot tick shares a packet
        hideRate     = 20,         --   with anti-aim ticks after it (cl_cmdrate used meanwhile)
        fakelag      = false,      -- fake lag through cl_cmdrate (bind it)
        flMode       = "adaptive", -- static | adaptive | jitter | air | moving
        flChoke      = 6,          -- ticks held back per packet (at most)
        flOffShooting = true,      -- no fake lag while firing (hide shots takes over if on)
        -- module only: what the others see is the last command of each packet
        desync       = false,      -- real view on choked ticks, anti-aim on the ones that are sent
        lby          = false,      -- "LBY breaker": the sent yaw jumps by lbyDelta now and then
        lbyDelta     = 120,
        lbyInterval  = 1.1,        -- seconds between jumps
        offOnUse     = true,       -- real view while IN_USE is held
        offWithTools = true,       -- physgun / toolgun / camera need the real view
        manualLeft   = false,      -- bind these three (right-click) for manual yaw
        manualRight  = false,
        manualBack   = false,
        states = {
            stand = AAState(),
            move  = AAState(),
            air   = AAState(),
        },
    },
    menu = {
        anim  = true,              -- fade / slide / eased widgets
        speed = 1,                 -- animation speed multiplier
        w     = 660,               -- window size, changed by dragging the bottom-right corner
        h     = 520,
        x     = -1,                -- where the window was last (-1: centred)
        y     = -1,
    },
    indicator = {                  -- speed number + short names of the active binds, under the crosshair
        enabled   = true,
        speed     = true,
        binds     = true,
        yPct      = 72,            -- height in % of the screen
        scale     = 1,             -- speed number size multiplier
        bindScale = 1,             -- bind names size multiplier
        r = 170, g = 110, b = 255, -- speed colour
        gainColor = false,         -- green while speeding up, red while losing speed
        allBinds  = false,         -- every active bind, not only the movement ones
    },
    keylist = {                    -- HUD list of the active binds
        enabled      = true,
        xPct         = 1,          -- position in % of the screen
        yPct         = 35,
        showInactive = false,      -- also list binds whose feature is currently off
    },
    speclist = {                   -- HUD list of the players spectating you
        enabled = true,
        xPct    = 1,
        yPct    = 22,
    },
    bg = {                         -- animated picture behind the menu
        enabled = false,           -- off until switched on (or a picture is picked) in the menu
        file    = "nyx_wave.jpg",  -- a file in data/nyx/bg/
        opacity = 0.45,
        mode    = "both",          -- static | drift | pulse | both
        speed   = 1,
        twinkle = true,
        r = 255, g = 255, b = 255, -- tint
    },
    watermark = {
        enabled    = true,
        style      = "bar",        -- bar | skeet
        corner     = "tr",         -- tl | tr | bl | br
        name       = "nyx",
        info       = false,        -- second panel: angle difference, loss, ping / tickrate
        showUser   = true,
        showServer = true,
        showFps    = true,
        showPing   = true,
        showTick   = true,
        showTime   = true,
        r = 149, g = 184, b = 6,   -- accent
    },
    misc = {
        antiSS = true,             -- hide every cheat visual from screengrabs
        ssAlert   = true,          -- notice when the server grabs your screen
        ssSound   = true,          -- shutter sound on a grab
        ssPreview = true,          -- save the grab to data/nyx/grabs/ and show it on screen
    },
}

-- Anti-target list ("friends"): players the aimbots never pick. Keyed by SteamID64 (the nick for
-- bots); everything lives in data/nyx/players.json and is managed by the Players tab.
local FR = {
    list = {},           -- friends:   key -> {name}   never targeted
    targets = {},        -- targets:   key -> {name}   red, preferred, the only ones in "target only"
    over = {},           -- resolver overrides: key -> {name, on, yaw, pitchOn, pitch}
    color = Color(90, 255, 130, 255),
    targetColor = Color(255, 60, 60, 255),
}

function FR.Key(ent)
    return ent:SteamID64() or ent:Nick()
end

function FR.Is(ent)
    return IsValid(ent) and FR.list[FR.Key(ent)] ~= nil
end

function FR.IsTarget(ent)
    return IsValid(ent) and FR.targets[FR.Key(ent)] ~= nil
end

local function IsBindDown(key)
    if key >= MOUSE_FIRST and key <= MOUSE_LAST then
        return input.IsMouseDown(key)
    end
    return input.IsKeyDown(key)
end

-- ---------------------------------------------------------------------------
-- aim helpers
-- ---------------------------------------------------------------------------

local HITBOX_BONE = {
    head   = "ValveBiped.Bip01_Head1",
    chest  = "ValveBiped.Bip01_Spine2",
    pelvis = "ValveBiped.Bip01_Pelvis",
}

-- ---------------------------------------------------------------------------
-- resolver: only the player the aimbot is working on, +step degrees on his yaw pose after every
-- shot of yours, so a head that sits off to the side of the body gets scanned around
-- ---------------------------------------------------------------------------

local aimTargetEnt, aimTargetTime = nil, 0                  -- last player an aimbot picked

-- Per player: step = shots since the last reset, misses = shots since the last confirmed hit,
-- brute = the offset currently applied, shotBrute / shotTime = what the latest shot went out at.
local resolverState = setmetatable({}, {__mode = "k"})

-- Memory resolver: the offset that last produced a confirmed hit, per player (by SteamID64), so a
-- target met again - another round, another place - is shot at the right angle straight away.
-- RS also carries the helpers so the file doesn't spend a local on each of them.
local RS = {mem = {}}          -- RS.mem[key] = {brute, hits, time}

function RS.State(ent)
    local st = resolverState[ent]
    if not st then
        st = {step = 0, last = 0, misses = 0, brute = 0, shotBrute = 0, shotTime = -10}
        resolverState[ent] = st
    end
    return st
end

function RS.Key(ent)
    return ent:SteamID64() or ent:Nick()
end

-- the remembered offset for ent, nil when there is none, it expired, or memory is off
function RS.Memory(ent)
    if not cfg.resolver.memory or not IsValid(ent) then return nil end

    local mem = RS.mem[RS.Key(ent)]
    if mem and CurTime() - mem.time <= cfg.resolver.memoryTime then return mem end
    return nil
end

function RS.Clear()
    table.Empty(RS.mem)
end

-- one short line for the menu
function RS.Status()
    local n = 0
    for _ in pairs(RS.mem) do n = n + 1 end

    local t = aimTargetEnt
    if IsValid(t) and CurTime() - aimTargetTime < 3 then
        local st = resolverState[t]
        return string.format("%d saved | %s %+d%s", n, string.sub(t:Nick(), 1, 9),
            st and st.brute or 0, RS.Memory(t) and " (mem)" or "")
    end

    return n .. " players in memory"
end

-- called whenever a shot of yours goes out
local function NotifyShot()
    if RS.OnShot then RS.OnShot() end          -- hit / miss log (its block is further down;
                                               -- RS because MV is declared after this point)
    if not cfg.resolver.enabled then return end
    if not IsValid(aimTargetEnt) or CurTime() - aimTargetTime > 2 then return end

    local st = RS.State(aimTargetEnt)
    st.step = st.step + 1
    st.misses = st.misses + 1          -- a miss until a hit confirms it
    st.shotBrute = st.brute
    st.shotTime = CurTime()
    st.last = CurTime()
end

-- A hit shortly after a shot: that shot's offset was right, remember it for this player.
gameevent.Listen("player_hurt")

AddHook("player_hurt", "resolvermemory", function(data)
    local r = cfg.resolver
    if not r.enabled then return end

    local me = LocalPlayer()
    if not IsValid(me) or data.attacker ~= me:UserID() or data.userid == data.attacker then return end

    local victim = Player(data.userid)
    local st = IsValid(victim) and resolverState[victim] or nil
    if not st or CurTime() - st.shotTime > 0.6 then return end   -- not a shot the resolver fired

    st.misses = 0
    if not r.memory then return end

    local key = RS.Key(victim)
    local mem = RS.mem[key]

    if mem and mem.brute == st.shotBrute then
        mem.hits = mem.hits + 1
    else
        mem = {brute = st.shotBrute, hits = 1}
        RS.mem[key] = mem
    end

    mem.time = CurTime()
end)

-- yaw offsets tried one after another in "list" mode (one per shot)
local BRUTE_YAW = {-180, -120, -60, 0, 60, 120, 180}

-- Rotates the target's whole model (render angles, which the bones are built from) and the yaw
-- pose parameters by the current brute offset, then rebuilds the bones. Runs every frame for the
-- aim target (PrePlayerDraw) and right before the aimbots read bone positions.
local function ApplyResolver(ent)
    if not IsValid(ent) then return end

    -- Per-player manual override (Players tab): applied every frame to that player whatever the
    -- aimbots are doing, with a fixed yaw (and optionally pitch) instead of the brute / memory.
    local ov = FR.over[FR.Key(ent)]
    if ov and ov.on then
        local yaw = math.NormalizeAngle(ent:EyeAngles().y + ov.yaw)

        ent:SetRenderAngles(Angle(0, yaw, 0))
        ent:SetPoseParameter("body_yaw", (yaw + 180) / 360)
        ent:SetPoseParameter("aim_yaw", math.NormalizeAngle(ov.yaw))

        if ov.pitchOn then
            ent:SetPoseParameter("aim_pitch", ov.pitch)
            ent:SetPoseParameter("head_pitch", ov.pitch)
        end

        ent.ChatGestureWeight = 0
        ent:InvalidateBoneCache()
        ent:SetupBones()
        return
    end

    local r = cfg.resolver
    if not r.enabled or ent ~= aimTargetEnt then return end
    if CurTime() - aimTargetTime > 2 then return end

    local st = RS.State(ent)
    if CurTime() - st.last > r.reset then
        st.step = 0
        st.misses = 0
    end

    local brute
    local mem = RS.Memory(ent)

    if mem and st.misses < r.memoryMisses then
        brute = mem.brute                                   -- what worked on him before
    elseif r.mode == "list" then
        brute = BRUTE_YAW[st.step % #BRUTE_YAW + 1]
    else
        brute = (st.step * r.step) % 360                    -- 0, +step, +2*step, ...
    end

    brute = math.NormalizeAngle(brute)
    st.brute = brute

    local eyeYaw = ent:EyeAngles().y
    local yaw = math.NormalizeAngle(eyeYaw + brute)

    ent:SetRenderAngles(Angle(0, yaw, 0))
    ent:SetPoseParameter("body_yaw", (yaw + 180) / 360)
    ent:SetPoseParameter("aim_yaw", brute)

    -- pitch resolver: a pitch pinned at the limits is treated as fake, the real one is "up"
    if r.pitch and math.abs(ent:EyeAngles().p) >= 80 then
        ent:SetPoseParameter("aim_pitch", -89)
        ent:SetPoseParameter("head_pitch", -89)
    end

    ent.ChatGestureWeight = 0      -- the chat gesture layer would drag the bones around

    ent:InvalidateBoneCache()
    ent:SetupBones()
end

local function GetAimPos(ent, hitbox, bonesReady)
    if not bonesReady then
        ApplyResolver(ent)      -- no-op unless ent is the resolver's current target
        ent:SetupBones()
    end

    -- T-pose is a purely visual override: bones would be nowhere near the real hitboxes
    if cfg.tpose.enabled and ent:IsPlayer() then
        if hitbox == "head" then return ent:EyePos() end
        local center = ent:LocalToWorld(ent:OBBCenter())
        if hitbox == "pelvis" then return center - Vector(0, 0, 10) end
        return center
    end

    local bone = ent:LookupBone(HITBOX_BONE[hitbox] or HITBOX_BONE.head)
    if bone then
        local pos = ent:GetBonePosition(bone)
        if pos and pos ~= ent:GetPos() then return pos end
    end

    -- models without a Valve skeleton
    if hitbox == "head" then return ent:EyePos() end
    local center = ent:LocalToWorld(ent:OBBCenter())
    if hitbox == "pelvis" then return center - Vector(0, 0, 10) end
    return center
end

local visTrace = {mask = MASK_SHOT}
local function IsVisible(ply, ent, from, to)
    visTrace.start = from
    visTrace.endpos = to
    visTrace.filter = {ply, ent}
    return not util.TraceLine(visTrace).Hit
end

-- backtrack ------------------------------------------------------------------
-- Every tick the hitbox positions of every player are written down together with the tick they
-- were on screen at. The server lag-compensates by the tick a command carries (it puts players
-- back to where this client saw them at that tick), so a shot that carries an older tick is a
-- shot at the old position. The server accepts roughly 200 ms beyond the normal lerp.
local BT = {recs = setmetatable({}, {__mode = "k"}), lastTick = -1}

-- native module ---------------------------------------------------------------------------
-- gmcl_nyx (lua/bin/gmcl_nyx_win64.dll or _win32.dll) is optional. With it: real packet choke
-- (fake lag, desync, LBY breaker, airstuck), tick_count writes and simulation times (backtrack
-- by server tick, fakelag extrapolation). Without it everything falls back to the Lua ways.
-- Each part is checked before use: the CUserCmd layout against what Lua reads from the same
-- command, the net channel by its address, the netvar reader against Health().
-- The state lives in BT.M (the main chunk is at Lua's 200 locals).
if not istable(nyxmod) then
    local installed = not util.IsBinaryModuleInstalled or util.IsBinaryModuleInstalled("nyx")
    if installed then pcall(require, "nyx") end
end

BT.M = {
    cmd = nil, cmdTries = 0, cmdMsg = "not probed",     -- CUserCmd offsets
    net = false, netNext = 0, netMsg = "not checked",   -- CanPacket hook
    ent = nil, entMsg = "not checked",                  -- netvar reader
    stuck = false,
}
BT.simHist = setmetatable({}, {__mode = "k"})          -- player -> {sim, prev}

function BT.HasMod()
    return istable(nyxmod)
end

-- once per command until it works: find tick_count / random_seed inside CUserCmd
function BT.ProbeCmd(cmd)
    local m = BT.M
    if m.cmd ~= nil or not istable(nyxmod) or cmd:CommandNumber() == 0 then return end

    m.cmdTries = m.cmdTries + 1
    local ok, info = nyxmod.CmdProbe(cmd, cmd:CommandNumber(), cmd.TickCount and cmd:TickCount() or nil, cmd:GetForwardMove())

    if ok then
        m.cmd, m.cmdMsg = true, "ok (offset " .. tostring(info) .. ")"
    elseif m.cmdTries >= 30 then
        m.cmd, m.cmdMsg = false, "failed: " .. tostring(info)
    end
end

-- the CanPacket hook, (re)installed every 2 s (a reconnect makes a new net channel)
function BT.NetCheck()
    local m = BT.M
    if not istable(nyxmod) then return false end

    local now = RealTime()
    if now >= m.netNext then
        m.netNext = now + 2
        local ok, msg = nyxmod.NetInit(game.GetIPAddress())
        m.net, m.netMsg = ok and true or false, tostring(msg)
    end

    return m.net
end

function BT.NetReady()
    return istable(nyxmod) and BT.M.net
end

-- true when the command being built now goes out in a packet (always true without the module)
function BT.WillSend()
    if not BT.NetReady() then return true end
    return nyxmod.WillSend()
end

-- tick_count for backtrack: GMod's own setter if this build has one, else the module
function BT.SetTick(cmd, tick)
    if cmd.SetTickCount then
        cmd:SetTickCount(tick)
        return true
    end

    if istable(nyxmod) and BT.M.cmd then return nyxmod.SetTickCount(cmd, tick) end
    return false
end

-- m_flSimulationTime of v (nil without the module / when the reader failed its check), plus
-- {sim, prev}: the last two different values, how far apart his updates are
function BT.SimTime(v)
    local m = BT.M
    if not istable(nyxmod) or m.ent == false then return nil end

    local idx = v:EntIndex()

    if m.ent == nil then
        -- one check before trusting the reader: m_iHealth must read what Lua says
        local off = nyxmod.Netvar(idx, "m_iHealth")
        local hp = off and nyxmod.ReadInt(idx, off)
        if hp == nil then return nil end            -- entity not ready, try again later

        m.ent = hp == v:Health()
        m.entMsg = m.ent and "ok" or string.format("check failed (%s vs %d)", tostring(hp), v:Health())
        if not m.ent then return nil end
    end

    local sim = nyxmod.SimTime(idx)
    if not sim then return nil end

    local h = BT.simHist[v]
    if not h then
        h = {sim = sim, prev = sim}
        BT.simHist[v] = h
    elseif h.sim ~= sim then
        h.prev, h.sim = h.sim, sim
    end

    return sim, h
end

-- the client's lerp the way the server computes it
function BT.Lerp()
    local function F(name, def)
        local cv = GetConVar(name)
        return cv and cv:GetFloat() or def
    end

    return math.max(F("cl_interp", 0.1), F("cl_interp_ratio", 2) / math.max(F("cl_updaterate", 20), 1))
end

-- one-way latency to the server
function BT.Latency(ply)
    local l = BT.NetReady() and nyxmod.Latency(0) or nil
    if l then return l end
    return IsValid(ply) and ply:Ping() / 2000 or 0
end

-- the tick a record from simulation time `sim` has to carry
function BT.SimTick(sim)
    return math.floor((sim + BT.Lerp()) / engine.TickInterval() + 0.5)
end

-- extrapolation -------------------------------------------------------------------------------
-- Where a hitbox has to be aimed so the server finds the target there when it runs the shot:
--   hitscan, lag compensation intact: nothing. The server rewinds the target to the tick the
--     command carries, which is the moment this client is drawing (lerp behind), so the drawn
--     position already is the right one. Leading by ping there only pulls the shot off a mover.
--   hitscan, lag compensation broken: a target that moves more than 64 units between two of his
--     updates (fake lag at speed) can't be rewound; the server gives up and shoots at where he is
--     by then. That is simulated from his newest update, tick by tick (gravity, hull traces against
--     walls and floors, steps, a strafer's turn in the air, bhop landings), and with fake lag in
--     whole chokes: the server moves him a full batch of ticks when his packet arrives.
--   projectile: no lag compensation, and the projectile needs time to get there: lead by the time
--     since his newest update + round trip + flight time (solved a few times over, the flight time
--     depends on the point), plus the drop of a projectile that has gravity.
-- Updates are seen as changes of the networked origin; with gmcl_nyx their server time is the
-- simulation time, without it the arrival time minus the round trip. Velocity comes from two
-- updates, not GetVelocity (for other players that's the client's own estimate, late on turns).
-- The offset is per player (newest update -> predicted position), added to any of his hitboxes.
BT.X = {
    hist  = setmetatable({}, {__mode = "k"}),   -- player -> updates, newest last (4 kept)
    cache = setmetatable({}, {__mode = "k"}),   -- player -> {tick, proj, offset}
    paths = setmetatable({}, {__mode = "k"}),   -- player -> {points, time} for drawing
    lastTick = -1,
    status = "idle",
    tr = {}, out = {},                          -- one trace request / result, reused
    -- projectiles "auto" knows: class -> {speed u/s, share of sv_gravity}
    PROJ = {
        weapon_crossbow = {3500, 0.05},
    },
}

function BT.X.Record(me)
    local X = BT.X
    local tick = engine.TickCount()
    if tick == X.lastTick then return end
    X.lastTick = tick

    local now, ti = CurTime(), engine.TickInterval()
    local rtt = 2 * BT.Latency(me)

    for _, v in ipairs(player.GetAll()) do
        if v == me or not v:Alive() or v:IsDormant() then
            X.hist[v] = nil
            continue
        end

        local list = X.hist[v]
        if not list then
            list = {}
            X.hist[v] = list
        end

        local origin = v:GetNetworkOrigin()
        local last = list[#list]
        local sim = BT.SimTime(v)

        local new
        if sim then new = not last or last.sim ~= sim
        else new = not last or last.origin ~= origin end

        if new then
            local rec = {
                origin = Vector(origin), sim = sim or (now - rtt), real = sim ~= nil, arrive = now,
                ground = v:IsOnGround(), duck = v:Crouching(), ticks = 1, step = 0,
            }

            if last then
                local dt = rec.sim - last.sim
                if dt <= 0 then dt = ti end

                local d = origin - last.origin
                rec.step = d:LengthSqr()
                rec.ticks = math.max(1, math.floor(dt / ti + 0.5))
                rec.vel = d * (1 / dt)

                -- respawn / teleport: nothing before it belongs to this path
                if rec.vel:LengthSqr() > 4000 * 4000 then
                    list = {}
                    X.hist[v] = list
                    rec.vel, rec.step = nil, 0
                end
            end

            list[#list + 1] = rec
            if #list > 4 then table.remove(list, 1) end
        end
    end
end

-- {speed, gravity share} of the projectile your weapon fires, nil for hitscan
function BT.X.Projectile(me)
    local e = cfg.extrap
    if e.projectile == "off" then return nil end
    if e.projectile == "always" then return {e.projSpeed, e.projGravity} end

    local wep = me:GetActiveWeapon()
    return IsValid(wep) and BT.X.PROJ[wep:GetClass()] or nil
end

-- yaw turn per tick of a strafer in the air, from his last three updates (0 when unknown)
function BT.X.Turn(list)
    local a, b = list[#list - 1], list[#list]
    if not (a and b and a.vel and b.vel) or b.ground then return 0 end
    if a.vel:Length2DSqr() < 2500 or b.vel:Length2DSqr() < 2500 then return 0 end

    local d = math.NormalizeAngle(b.vel:Angle().y - a.vel:Angle().y)
    return math.Clamp(d / math.max(b.ticks, 1), -15, 15)
end

-- airborne in most of his recent updates while faster than running: he jumps again on landing
function BT.X.Bhop(v, list)
    local air = 0
    for _, r in ipairs(list) do if not r.ground then air = air + 1 end end

    local b = list[#list]
    return air >= 2 and b.vel and b.vel:Length2D() > v:GetRunSpeed() * 1.05
end

-- Moves v's hull from pos with vel for n ticks the way the engine would without new input.
-- Returns the end position; fills path with every tick's position when given.
function BT.X.Simulate(v, pos, vel, ground, turn, bhop, n, path)
    local X = BT.X
    local ti = engine.TickInterval()
    local gcv = GetConVar("sv_gravity")
    local g = gcv and gcv:GetFloat() or 600
    local jump = v:GetJumpPower()

    local tr, out = X.tr, X.out
    local mins, maxs
    if v:Crouching() then mins, maxs = v:GetHullDuck() else mins, maxs = v:GetHull() end
    tr.mins, tr.maxs, tr.mask, tr.output = mins, maxs, MASK_PLAYERSOLID, out
    tr.filter = {v, LocalPlayer()}

    pos, vel = Vector(pos), Vector(vel)
    local c, s = math.cos(math.rad(turn)), math.sin(math.rad(turn))
    local up, down = Vector(0, 0, 18), Vector(0, 0, -18)

    for _ = 1, n do
        if ground then
            vel.z = 0
        else
            if turn ~= 0 then
                local x, y = vel.x, vel.y
                vel.x, vel.y = x * c - y * s, x * s + y * c
            end
            vel.z = vel.z - g * ti * 0.5
        end

        -- move, sliding along what is hit (a few bumps, like TryPlayerMove)
        local left = ti
        for _ = 1, 3 do
            tr.start, tr.endpos = pos, pos + vel * left
            util.TraceHull(tr)
            if out.StartSolid then break end

            pos = Vector(out.HitPos)
            if not out.Hit then break end

            local nrm = out.HitNormal

            -- a wall while walking: try the same move 18 units up (stairs)
            if ground and nrm.z < 0.7 then
                tr.start, tr.endpos = pos + up, pos + up + vel * (left * (1 - out.Fraction))
                util.TraceHull(tr)
                if not out.StartSolid and out.Fraction > 0 then
                    local p = Vector(out.HitPos)
                    tr.start, tr.endpos = p, p + down
                    util.TraceHull(tr)
                    if out.Hit and out.HitNormal.z >= 0.7 then
                        pos = Vector(out.HitPos)
                        break
                    end
                end
                nrm = Vector(nrm.x, nrm.y, 0)
                nrm:Normalize()
            end

            left = left * (1 - out.Fraction)
            if nrm.z >= 0.7 and vel.z <= 140 then ground = true end
            vel = vel - nrm * vel:Dot(nrm)
            if left <= 0 then break end
        end

        if ground then
            -- still standing on something? (walked off an edge: falling from here on)
            tr.start, tr.endpos = pos, pos + down
            util.TraceHull(tr)

            if out.Hit and not out.StartSolid and out.HitNormal.z >= 0.7 then
                pos = Vector(out.HitPos)
                if bhop then
                    vel.z = jump
                    ground = false
                end
            else
                ground = false
            end
        else
            vel.z = vel.z - g * ti * 0.5
        end

        if path then path[#path + 1] = pos end
    end

    return pos
end

-- Offset to add to any hitbox of v (as drawn now) so the shot from `from` meets him.
-- vector_origin when no lead is needed. Cached per player and tick.
function BT.X.Offset(me, v, from)
    local X, e = BT.X, cfg.extrap
    local tick = engine.TickCount()
    local proj = X.Projectile(me)

    local c = X.cache[v]
    if c and c.tick == tick and c.proj == proj then return c.offset end

    local offset = vector_origin
    local list = X.hist[v]
    local newest = list and list[#list]

    if newest and newest.vel then
        local now, ti = CurTime(), engine.TickInterval()
        local vel = newest.vel

        -- without sim times a player who stopped sends nothing new: his old speed is stale then
        if not newest.real then
            if now - newest.arrive > math.max(0.25, newest.ticks * ti * 3) then vel = vector_origin end
        end

        -- server time from his newest update to when our command runs
        local dt = (now - newest.arrive) + 2 * BT.Latency(me)
        local ticks, label

        if proj then
            ticks = math.floor(dt / ti + 0.5)
            label = "projectile"
        elseif e.lcBreak and newest.step > 64 * 64 then
            -- moved in whole chokes: as many batches as fit in the time
            local choke = math.max(newest.ticks, 1)
            ticks = math.floor(dt / (choke * ti)) * choke
            label = "lc broken, choke " .. choke
        end

        if ticks then
            local turn = e.strafe and X.Turn(list) or 0
            local bhop = e.bhop and X.Bhop(v, list) or false
            local maxT = math.floor(e.maxTicks)
            local start = newest.origin

            local endPos, path, drop

            if proj then
                -- flight time depends on the point: refine it a few times
                local center = v:WorldSpaceCenter() - v:GetPos()
                local flight = 0

                for _ = 1, 3 do
                    local n = math.min(ticks + math.floor(flight / ti + 0.5), maxT)
                    path = e.draw and {} or nil
                    endPos = X.Simulate(v, start, vel, newest.ground, turn, bhop, n, path)
                    flight = (endPos + center):Distance(from) / math.max(proj[1], 1)
                end

                local gcv = GetConVar("sv_gravity")
                drop = 0.5 * (gcv and gcv:GetFloat() or 600) * proj[2] * flight * flight
                label = string.format("%s %.2fs", label, flight)
            else
                path = e.draw and {} or nil
                endPos = X.Simulate(v, start, vel, newest.ground, turn, bhop, math.min(ticks, maxT), path)
            end

            offset = endPos - v:GetPos()
            if drop and drop > 0 then offset.z = offset.z + drop end

            if path then X.paths[v] = {points = path, from = Vector(start), time = RealTime()} end
            X.status = string.format("%s: %s, +%d t", v:Nick(), label, math.min(ticks, maxT))
        end
    end

    X.cache[v] = {tick = tick, proj = proj, offset = offset}
    return offset
end

function BT.X.Status()
    return string.sub(BT.X.status, 1, 44)
end

-- the extrapolated paths of the last moment, ending in the hull where he is expected
AddHook("PostDrawTranslucentRenderables", "extrap", function(depth, skybox)
    if skybox or not cfg.extrap.draw or IsHidden() then return end

    local now = RealTime()
    for v, p in pairs(BT.X.paths) do
        if not IsValid(v) or now - p.time > 0.25 then
            BT.X.paths[v] = nil
        elseif #p.points > 0 then
            local col = Color(cfg.extrap.r, cfg.extrap.g, cfg.extrap.b)
            local prev = p.from

            for _, pt in ipairs(p.points) do
                render.DrawLine(prev, pt, col, false)
                prev = pt
            end

            local mins, maxs = v:GetHull()
            render.DrawWireframeBox(prev, angle_zero, mins, maxs, col, false)
        end
    end
end)

function BT.ModStatus()
    if not istable(nyxmod) then return "module: not installed (lua/bin/gmcl_nyx_*.dll)" end

    local m = BT.M
    return string.format("cmd %s | net %s | netvars %s", m.cmd and "ok" or (m.cmd == false and "FAIL" or "..."),
        m.net and "ok" or "off", m.ent and "ok" or (m.ent == false and "FAIL" or "..."))
end

function BT.NetStatus()
    if not istable(nyxmod) then return "module not installed" end
    return string.sub(BT.M.netMsg, 1, 44)
end

function BT.Record(me)
    local tick = engine.TickCount()
    if tick == BT.lastTick then return end
    BT.lastTick = tick

    if not cfg.backtrack.enabled then
        if next(BT.recs) then BT.recs = setmetatable({}, {__mode = "k"}) end
        return
    end

    local now = CurTime()

    for _, v in ipairs(player.GetAll()) do
        if v ~= me and v:Alive() and not v:IsDormant() then
            local list = BT.recs[v]
            if not list then
                list = {}
                BT.recs[v] = list
            end

            local origin = v:GetPos()
            local last = list[#list]

            -- With the module a record is one server update (a new simulation time), and its tick
            -- is that update's own; without it, one record per client tick.
            local sim = BT.SimTime(v)

            if not (sim and last and last.sim == sim) then
                -- A teleport / respawn: the old records belong to somewhere else. With server
                -- ticks known, 64 units is also where the server's lag compensation gives up
                -- (it won't put a player back across a jump that large).
                local limit = sim and 64 or 300
                if last and last.origin:DistToSqr(origin) > limit * limit then list = {}; BT.recs[v] = list end

                ApplyResolver(v)        -- no-op unless v is the resolver's current target
                v:SetupBones()

                list[#list + 1] = {
                    tick = sim and BT.SimTick(sim) or tick, sim = sim, time = now, origin = origin,
                    head = GetAimPos(v, "head", true),
                    chest = GetAimPos(v, "chest", true),
                    pelvis = GetAimPos(v, "pelvis", true),
                }
            end

            while list[1] and now - list[1].time > 0.5 do table.remove(list, 1) end
        else
            BT.recs[v] = nil
        end
    end
end

-- records of v that are still inside the window, newest first, at most `max` of them spread
-- evenly over it (the current tick is left out: that is the position the aimbot already has)
function BT.List(v, max)
    local out = {}
    local list = BT.recs[v]
    if not list then return out end

    local now, nowTick = CurTime(), engine.TickCount()
    local maxAge = cfg.backtrack.ms / 1000

    -- server-tick records: the server restores a record only while
    -- |(latency + lerp) - (server time - its simulation time)| < 0.2 s
    local newest = list[#list]
    local correct = newest and newest.sim and math.Clamp(BT.Latency(LocalPlayer()) + BT.Lerp(), 0, 1)

    local eligible = {}
    for i = #list, 1, -1 do
        local rec = list[i]
        local ok

        if rec.sim and correct then
            -- the newest one is the live position the aimbot already has
            ok = i < #list and newest.sim - rec.sim <= maxAge and math.abs(correct - (now - rec.sim)) < 0.2
        else
            ok = rec.tick < nowTick and now - rec.time <= maxAge
        end

        if ok then eligible[#eligible + 1] = rec end
    end

    local stride = math.max(1, math.ceil(#eligible / max))
    for i = 1, #eligible, stride do out[#out + 1] = eligible[i] end

    return out
end

-- first record whose `hitbox` is in the open from shootPos and inside fovLimit of fwd:
-- position, tick, angle to the crosshair, distance
function BT.Find(ply, v, hitbox, shootPos, fwd, fovLimit)
    if not cfg.backtrack.enabled then return end

    for _, rec in ipairs(BT.List(v, 6)) do
        local pos = rec[hitbox]
        local dir = pos - shootPos
        local dist = dir:Length()

        if dist >= 1 then
            dir:Mul(1 / dist)

            local angle = math.deg(math.acos(math.Clamp(fwd:Dot(dir), -1, 1)))
            if angle <= fovLimit and IsVisible(ply, v, shootPos, pos) then
                return pos, rec.tick, angle, dist
            end
        end
    end
end

local ALL_HITBOXES = {"head", "chest", "pelvis"}

-- chosen hitbox first, the others only when fallback is on
local function HitboxOrder()
    local list = {cfg.aim.hitbox}
    if cfg.aim.fallback then
        for _, hb in ipairs(ALL_HITBOXES) do
            if hb ~= cfg.aim.hitbox then list[#list + 1] = hb end
        end
    end
    return list
end

-- random wobble of the aim point, re-rolled a few times per second
local humanOffset, humanNext = Vector(0, 0, 0), 0
local function HumanOffset()
    if not cfg.aim.humanizeOn or cfg.aim.humanize <= 0 then return vector_origin end

    local now = CurTime()
    if now >= humanNext then
        humanNext = now + 0.25
        humanOffset = VectorRand() * cfg.aim.humanize
    end
    return humanOffset
end

-- where the target will be in cfg.aim.predict ticks, relative to our own movement
local function Predict(pos, ent, ply)
    local aim = cfg.aim

    if aim.extrapOn then pos = pos + BT.X.Offset(ply, ent, ply:GetShootPos()) end

    local lead = 0
    if aim.predictOn and aim.predict > 0 then lead = aim.predict * engine.TickInterval() end

    if lead <= 0 then return pos end
    return pos + (ent:GetVelocity() - ply:GetVelocity()) * lead
end

-- the tick of the backtrack record EvaluateTarget's last result came from (nil: the live position)
local evalTick = nil

-- aim position, angle to crosshair (deg) and distance (units); nil when v is not a valid target
local function EvaluateTarget(ply, v, shootPos, fwd, fovLimit, order)
    evalTick = nil

    if v == ply or not v:Alive() or v:IsDormant() then return end
    if v:GetObserverMode() ~= OBS_MODE_NONE then return end
    if cfg.aim.teamCheck and v:Team() == ply:Team() then return end
    if FR.Is(v) then return end
    if cfg.aim.targetOnly and not FR.IsTarget(v) then return end
    if cfg.aim.ignoreFriends and v:GetFriendStatus() == "friend" then return end

    if shootPos:Distance(v:GetPos()) * 0.01905 > cfg.aim.maxDist then return end

    for _, hitbox in ipairs(order) do
        local pos = Predict(GetAimPos(v, hitbox), v, ply) + HumanOffset()
        local dir = pos - shootPos
        local dist = dir:Length()
        if dist < 1 then continue end
        dir:Mul(1 / dist)

        local angle = math.deg(math.acos(math.Clamp(fwd:Dot(dir), -1, 1)))
        if angle > fovLimit then continue end

        if cfg.aim.visCheck and not IsVisible(ply, v, shootPos, pos) then
            -- hidden now: maybe he was in the open a moment ago
            local bpos, btick, bangle, bdist = BT.Find(ply, v, hitbox, shootPos, fwd, fovLimit)
            if bpos then
                evalTick = btick
                return bpos, bangle, bdist
            end

            continue
        end

        return pos, angle, dist
    end
end

local lockedTarget = nil

-- best player inside the FOV cone around viewAng, plus the point to aim at
local function FindTarget(ply, viewAng)
    local aim = cfg.aim
    local shootPos = ply:GetShootPos()
    local fwd = viewAng:Forward()
    local order = HitboxOrder()

    -- keep the current target while it stays valid (wider cone so it doesn't flip-flop)
    if aim.sticky and IsValid(lockedTarget) then
        local pos = EvaluateTarget(ply, lockedTarget, shootPos, fwd, aim.fov * 1.5, order)
        if pos then return lockedTarget, pos, evalTick end
    end
    lockedTarget = nil

    local bestEnt, bestPos, bestScore, bestTick = nil, nil, math.huge, nil

    for _, v in ipairs(player.GetAll()) do
        local pos, angle, dist = EvaluateTarget(ply, v, shootPos, fwd, aim.fov, order)
        if not pos then continue end
        local tick = evalTick

        local score
        if aim.priority == "distance" then
            score = dist
        elseif aim.priority == "health" then
            score = v:Health()
        else
            score = angle
        end

        -- players marked as targets are picked first whenever one of them is in range
        if FR.IsTarget(v) then score = score * 0.1 end

        if score < bestScore then
            bestScore = score
            bestEnt = v
            bestPos = pos
            bestTick = tick
        end
    end

    lockedTarget = bestEnt
    if bestEnt then aimTargetEnt, aimTargetTime = bestEnt, CurTime() end
    return bestEnt, bestPos, bestTick
end

-- ---------------------------------------------------------------------------
-- CreateMove: movement first, then aim (aim rotates the final move vector)
-- ---------------------------------------------------------------------------

-- silent aim state
--   realAng     : where you are actually looking (what your screen shows)
--   sentAng     : last angle we wrote into a usercmd
--   silentDirty : the engine view currently holds an injected angle, not realAng
local realAng = Angle(0, 0, 0)
local sentAng = Angle(0, 0, 0)
local silentDirty = false
local menu = nil        -- menu frame, assigned in BuildMenu
local IsHidden         -- "a screengrab is being taken", defined with the anti-screengrab block

local cvAirAccel = GetConVar("sv_airaccelerate")

local function AutoStrafe(cmd, ply)
    if cfg.move.strafeMode == "mouse" then
        -- legacy: side move follows the mouse direction
        local mx = cmd:GetMouseX()
        if mx ~= 0 then
            cmd:SetForwardMove(0)
            cmd:SetSideMove(mx > 0 and 10000 or -10000)
        end
        return
    end

    -- directional: the heading you ask for with WASD is kept, the move vector is steered
    -- every tick so the air-accel gain is maximal for the current velocity.
    local fm, sm = cmd:GetForwardMove(), cmd:GetSideMove()
    if fm == 0 and sm == 0 then return end

    local yaw = realAng.y                                   -- inputs are relative to what you see
    local wantYaw = yaw + math.deg(math.atan2(-sm, fm))     -- world heading of the pressed keys

    local vel = ply:GetVelocity()
    local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
    local wishYaw = wantYaw

    if speed > 30 then
        local airAccel = cvAirAccel and cvAirAccel:GetFloat() or 10
        if airAccel <= 0 then airAccel = 10 end

        -- best angle between wishdir and velocity: v.w = 30 - (accel gained this tick)
        local step = math.min(30, airAccel * ply:GetMaxSpeed() * engine.TickInterval())
        local ideal = math.deg(math.acos(math.Clamp((30 - step) / speed, -1, 1)))

        local velYaw = math.deg(math.atan2(vel.y, vel.x))
        local diff = math.NormalizeAngle(wantYaw - velYaw)
        wishYaw = velYaw + (diff >= 0 and ideal or -ideal)
    end

    local rel = math.rad(wishYaw - yaw)
    cmd:SetForwardMove(math.cos(rel) * 10000)
    cmd:SetSideMove(-math.sin(rel) * 10000)
end

-- Adaptive circle strafe. The wish direction is rebuilt every tick from the current velocity: the
-- angle off the velocity that gains the most speed, always on the same side, so the velocity keeps
-- curving and the circle's radius follows speed and air acceleration by itself. Too slow to curve
-- yet, it pushes along the view to build speed first; with "flip on walls" a wall in the way
-- turns the circle the other way round.
local circleFlip, circleFlipAt, circleLast = false, 0, 0

local function CircleStrafe(cmd, ply)
    local m = cfg.move
    local now = CurTime()

    if now - circleLast > 0.3 then circleFlip = false end   -- a new jump starts a new circle
    circleLast = now

    local vel = ply:GetVelocity()
    local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)

    if m.circleAvoid and speed > 50 and now - circleFlipAt > 0.5 then
        local dir = Vector(vel.x, vel.y, 0)
        dir:Normalize()

        local pos = ply:GetPos()
        local tr = util.TraceHull({
            start = pos,
            endpos = pos + dir * (40 + speed * 0.07),
            mins = Vector(-16, -16, 8),
            maxs = Vector(16, 16, 60),
            filter = ply,
            mask = MASK_PLAYERSOLID,
        })

        -- walls only: floors and gentle slopes don't count
        if tr.Hit and math.abs(tr.HitNormal.z) < 0.7 then
            circleFlip = not circleFlip
            circleFlipAt = now
        end
    end

    local side = (m.circleSide == "right") and -1 or 1
    if circleFlip then side = -side end

    local yaw = realAng.y
    local wishYaw = yaw

    if speed >= m.circleMinSpeed then
        local airAccel = cvAirAccel and cvAirAccel:GetFloat() or 10
        if airAccel <= 0 then airAccel = 10 end

        local step = math.min(30, airAccel * ply:GetMaxSpeed() * engine.TickInterval())
        local ideal = math.deg(math.acos(math.Clamp((30 - step) / math.max(speed, 1), -1, 1)))

        wishYaw = math.deg(math.atan2(vel.y, vel.x)) + side * ideal
    end

    local rel = math.rad(wishYaw - yaw)
    cmd:SetForwardMove(math.cos(rel) * 10000)
    cmd:SetSideMove(-math.sin(rel) * 10000)
end

local function DoMovement(cmd, ply)
    if ply:GetMoveType() ~= MOVETYPE_WALK or ply:WaterLevel() > 1 or ply:InVehicle() then return end

    -- circle strafe runs in the air whether or not jump is held (bhop still re-presses on landing)
    if cfg.move.circle and not ply:IsOnGround() then
        CircleStrafe(cmd, ply)
        if cfg.move.bhop and cmd:KeyDown(IN_JUMP) then cmd:RemoveKey(IN_JUMP) end
        return
    end

    if not cmd:KeyDown(IN_JUMP) then return end

    -- on the ground the jump goes through; in the air bhop releases it so it re-presses on landing
    if ply:IsOnGround() then return end

    if cfg.move.bhop then
        cmd:RemoveKey(IN_JUMP)
    end

    if cfg.move.autostrafe then
        AutoStrafe(cmd, ply)
    end
end

-- edge bug ---------------------------------------------------------------------------
-- Follows lobotomy (hacks/movement/edgebug.cpp): a few button variants are run through a
-- prediction of the next ticks and the first one that ends a tick at the edge bug signature is
-- replayed tick by tick. The signature: after a tick in the air the vertical speed is exactly
-- -sv_gravity * 0.5 * tick_interval - the move ran into the top of an edge, which clipped the
-- fall to zero (only the second half of the gravity is left), and the ground check after it
-- found nothing below because the rest of that tick's move carried the hull past the edge.
--
-- Lua has no engine prediction, so the ticks are simulated the way Source's FullWalkMove runs
-- them in the air: duck (instant in the air, the feet move by the hull difference), half the
-- gravity, air acceleration from the keys, the hull moved and clipped against what it hits (a
-- few bumps, like TryPlayerMove), the ground check (walkable within 2 units, not while rising
-- faster than 140 u/s), the other half of the gravity.
--
-- Variants, as in lobotomy: 0 stand / 1 duck with no keys; with "advanced" also 2 stand / 3 duck
-- with your keys while the view keeps turning at your current mouse speed (scaled by "turn
-- scale"). Searching every tick while nothing is lined up also covers ducking or standing up at
-- any later tick: the variant "from now on" of a later tick is that switch. A plan is replayed
-- while the player is where the simulation said (2 units); the moment it isn't, it is searched
-- again in the same tick. While a plan runs the mouse is slowed ("mouse lock"), so the turn the
-- plan counted on isn't thrown off, and the predicted path is drawn.
--
-- Cost: the simulation runs on plain numbers with one reused trace request and result table
-- (util.TraceHull's `output`), so a simulated tick allocates nothing unless its path is being
-- recorded for drawing; the ground check only runs on ticks whose move hit something (a tick
-- that hit nothing cannot be the signature, and a landing shows up as a hit on the next one).
local MV = {
    status = "idle", hits = 0, flash = 0,
    tbHits = 0, flashText = "edgebug",
    tbMinHold = 6,                    -- ticks a catch has to hold to be a texture bug
    hang = nil,                       -- texture bug being held: {duck, yaw, mag, wallYaw, miss}
    atRun = 0, runStart = 0,          -- real ticks in a row at the signature, and since when
    plan = nil, duckHold = false,
    prevVz = 0, prevAt = false,
    lastYaw = nil, yawRate = 0,
    preview = nil,                    -- predicted fall path (no plan) for drawing
    lines = nil,                      -- the advanced fan's paths, for drawing
}

do
    local cvGravity = GetConVar("sv_gravity")
    local cvAirAccel = GetConVar("sv_airaccelerate")

    -- one trace request reused for every simulated trace, with its result table
    local tStart, tEnd = Vector(), Vector()
    local tOut = {}
    local tr = {mask = MASK_PLAYERSOLID, start = tStart, endpos = tEnd, output = tOut}

    local function TraceXYZ(ply, sx, sy, sz, ex, ey, ez, mins, maxs)
        tStart.x, tStart.y, tStart.z = sx, sy, sz
        tEnd.x, tEnd.y, tEnd.z = ex, ey, ez
        tr.mins, tr.maxs, tr.filter = mins, maxs, ply
        util.TraceHull(tr)
        return tOut
    end

    local function Gravity(ply)
        local scale = ply:GetGravity()
        if scale == 0 then scale = 1 end
        return (cvGravity and cvGravity:GetFloat() or 600) * scale
    end

    -- the signature speed: -gravity * 0.5 * tick
    local function Target(ply)
        return -Gravity(ply) * 0.5 * engine.TickInterval()
    end

    local function AtTarget(vz, target)
        return math.abs(vz - target) < 0.1
    end

    -- the state one simulation runs on, everything as numbers
    local cvFriction, cvStopSpeed, cvAccel = GetConVar("sv_friction"), GetConVar("sv_stopspeed"), GetConVar("sv_accelerate")

    -- the four quarter hulls TryTouchGroundInQuadrants traces with, made once per hull size
    -- (GetHull hands out new Vectors every call, so the cache goes by the numbers)
    local quadCache = {}

    local function Quadrants(mins, maxs)
        local key = mins.x .. "," .. mins.y .. "," .. mins.z .. "," .. maxs.x .. "," .. maxs.y .. "," .. maxs.z
        local q = quadCache[key]
        if q then return q end

        q = {
            {mins, Vector(math.min(0, maxs.x), math.min(0, maxs.y), maxs.z)},                                   -- -x -y
            {Vector(math.max(0, mins.x), math.max(0, mins.y), mins.z), maxs},                                   -- +x +y
            {Vector(mins.x, math.max(0, mins.y), mins.z), Vector(math.min(0, maxs.x), maxs.y, maxs.z)},         -- -x +y
            {Vector(math.max(0, mins.x), mins.y, mins.z), Vector(maxs.x, math.min(0, maxs.y), maxs.z)},         -- +x -y
        }
        quadCache[key] = q
        return q
    end

    local function NewSim(ply)
        local sMin, sMax = ply:GetHull()
        local dMin, dMax = ply:GetHullDuck()
        local pos, vel = ply:GetPos(), ply:GetVelocity()

        return {
            ply = ply,
            x = pos.x, y = pos.y, z = pos.z,
            vx = vel.x, vy = vel.y, vz = vel.z,
            ducked = ply:Crouching(),
            onGround = ply:IsOnGround(),
            sMin = sMin, sMax = sMax, dMin = dMin, dMax = dMax,
            delta = (sMax.z - sMin.z) - (dMax.z - dMin.z),
            dt = engine.TickInterval(),
            g = Gravity(ply),
            maxSpeed = ply:GetMaxSpeed(),
            duckSpeed = ply:GetCrouchedWalkSpeed(),
            stepSize = ply:GetStepSize(),
            airAccel = cvAirAccel and cvAirAccel:GetFloat() or 10,
            accel = cvAccel and cvAccel:GetFloat() or 10,
            friction = cvFriction and cvFriction:GetFloat() or 8,
            stopSpeed = cvStopSpeed and cvStopSpeed:GetFloat() or 10,
            quads = cfg.move.simQuads,
            qS = Quadrants(sMin, sMax), qD = Quadrants(dMin, dMax),
            planes = {},                       -- TryPlayerMove's plane list, reused
            hitWalk = false, hitSteep = false, -- what the last tick's move ran into
        }
    end

    -- a copy of a sim to run another candidate from the same state: plain fields copied, the
    -- hulls / quarter hulls / plane list shared (sims run one after another), one table made
    local function CloneSim(b)
        return {
            ply = b.ply, x = b.x, y = b.y, z = b.z, vx = b.vx, vy = b.vy, vz = b.vz,
            ducked = b.ducked, onGround = b.onGround,
            sMin = b.sMin, sMax = b.sMax, dMin = b.dMin, dMax = b.dMax, delta = b.delta,
            dt = b.dt, g = b.g, maxSpeed = b.maxSpeed, duckSpeed = b.duckSpeed, stepSize = b.stepSize,
            airAccel = b.airAccel, accel = b.accel, friction = b.friction, stopSpeed = b.stopSpeed,
            quads = b.quads, qS = b.qS, qD = b.qD, planes = b.planes,
            hitWalk = false, hitSteep = false,
        }
    end

    -- TryPlayerMove: up to 4 bumps. Moving any distance clears the plane list; one plane is
    -- clipped against; with more, each is tried in turn and kept if the result doesn't run
    -- into any of the others; if none works, two planes leave only their crease (velocity
    -- along their cross product) and three or more stop the move; a result turned against
    -- the tick's first velocity stops it too. Moves s, returns the new velocity or nil (stuck).
    local function TryPlayerMove(s, vx, vy, vz, mins, maxs)
        local ply = s.ply
        local px, py, pz, left = s.x, s.y, s.z, s.dt
        local ox, oy, oz = vx, vy, vz              -- original_velocity
        local pvx, pvy, pvz = vx, vy, vz           -- primal_velocity
        local planes, np = s.planes, 0
        local hitWalk, hitSteep = false, false

        for _ = 1, 4 do
            if vx == 0 and vy == 0 and vz == 0 then break end

            local t = TraceXYZ(ply, px, py, pz, px + vx * left, py + vy * left, pz + vz * left, mins, maxs)
            if t.StartSolid then return nil end

            if t.Fraction > 0 then
                local hp = t.HitPos
                px, py, pz = hp.x, hp.y, hp.z
                ox, oy, oz = vx, vy, vz
                np = 0
            end

            if not t.Hit then break end

            left = left * (1 - t.Fraction)

            local n = t.HitNormal
            if n.z >= 0.7 then
                hitWalk = true
            else
                hitSteep = true
                s.wallNx, s.wallNy = n.x, n.y
            end

            np = np + 1
            local pl = planes[np]
            if not pl then
                pl = {}
                planes[np] = pl
            end
            pl[1], pl[2], pl[3] = n.x, n.y, n.z

            if np == 1 then
                local d = ox * n.x + oy * n.y + oz * n.z
                vx, vy, vz = ox - n.x * d, oy - n.y * d, oz - n.z * d
                ox, oy, oz = vx, vy, vz
            else
                local ok = false

                for i = 1, np do
                    local a = planes[i]
                    local d = ox * a[1] + oy * a[2] + oz * a[3]
                    vx, vy, vz = ox - a[1] * d, oy - a[2] * d, oz - a[3] * d

                    local good = true
                    for j = 1, np do
                        if j ~= i then
                            local b = planes[j]
                            if vx * b[1] + vy * b[2] + vz * b[3] < 0 then
                                good = false
                                break
                            end
                        end
                    end

                    if good then
                        ok = true
                        break
                    end
                end

                if not ok then
                    if np ~= 2 then
                        vx, vy, vz = 0, 0, 0
                        break
                    end

                    -- the crease of the two planes
                    local a, b = planes[1], planes[2]
                    local cx = a[2] * b[3] - a[3] * b[2]
                    local cy = a[3] * b[1] - a[1] * b[3]
                    local cz = a[1] * b[2] - a[2] * b[1]
                    local len = math.sqrt(cx * cx + cy * cy + cz * cz)
                    if len > 0 then cx, cy, cz = cx / len, cy / len, cz / len end

                    local d = cx * vx + cy * vy + cz * vz
                    vx, vy, vz = cx * d, cy * d, cz * d
                end

                if vx * pvx + vy * pvy + vz * pvz <= 0 then
                    vx, vy, vz = 0, 0, 0
                    break
                end
            end

            if left <= 0 then break end
        end

        s.x, s.y, s.z = px, py, pz
        s.hitWalk, s.hitSteep = hitWalk, hitSteep
        return vx, vy, vz
    end

    -- CategorizePosition: not while rising faster than 140; a walkable plane within 2 units
    -- below. Optionally (simQuads) the SDK 2013 extra: when the plane there is too steep, any
    -- of the four quarter hulls touching a walkable one (TryTouchGroundInQuadrants). GMod's
    -- movement doesn't seem to do that - with it on, the simulation sees landings beside walls
    -- the server never makes - so it is off by default. The quarter hulls are parts of the
    -- full one, so they are only traced when the full hull hit something.
    local function Grounded(s, vz, mins, maxs)
        if vz > 140 then return false end

        local ply, x, y, z = s.ply, s.x, s.y, s.z
        local t = TraceXYZ(ply, x, y, z, x, y, z - 2, mins, maxs)
        if not t.Hit then return false end
        if not t.StartSolid and t.HitNormal.z >= 0.7 then return true end
        if not s.quads then return false end

        for _, q in ipairs(s.ducked and s.qD or s.qS) do
            local qt = TraceXYZ(ply, x, y, z, x, y, z - 2, q[1], q[2])
            if qt.Hit and not qt.StartSolid and qt.HitNormal.z >= 0.7 then return true end
        end

        return false
    end

    -- one tick of FullWalkMove; returns "air" | "land" | "ground" | "stuck"
    -- In the air: half the gravity, air acceleration, TryPlayerMove, CategorizePosition, the
    -- other half. On the ground: no vertical speed, friction, Accelerate, the walk
    -- (TryPlayerMove flat), StayOnGround, CategorizePosition - losing the ground there leaves
    -- exactly -half gravity after FinishGravity, the texture bug's usual way out.
    local function SimTick(s, duck, fm, sm, yaw)
        local ply = s.ply

        -- duck: instant in the air (the feet come up); on the ground the hull only changes once
        -- ducking finishes, which takes longer than a tick, so it is left as it is there
        if duck ~= s.ducked and not s.onGround then
            if duck then
                s.z, s.ducked = s.z + s.delta, true
            else
                local t = TraceXYZ(ply, s.x, s.y, s.z, s.x, s.y, s.z - s.delta, s.sMin, s.sMax)
                if not t.StartSolid and not t.Hit then s.z, s.ducked = s.z - s.delta, false end
            end
        end

        local mins, maxs = s.sMin, s.sMax
        if s.ducked then mins, maxs = s.dMin, s.dMax end

        local hg = s.g * 0.5 * s.dt
        local vx, vy, vz

        -- wish direction and speed from the keys
        local wx, wy, ws = 0, 0, 0
        if fm ~= 0 or sm ~= 0 then
            local r = math.rad(yaw)
            local c, sn = math.cos(r), math.sin(r)
            wx, wy = c * fm + sn * sm, sn * fm - c * sm
            ws = math.sqrt(wx * wx + wy * wy)
            if ws > 0 then wx, wy = wx / ws, wy / ws end
        end

        if s.onGround then
            vx, vy, vz = s.vx, s.vy, 0

            -- Friction
            local speed = math.sqrt(vx * vx + vy * vy)
            if speed >= 0.1 then
                local control = speed < s.stopSpeed and s.stopSpeed or speed
                local ns = math.max(speed - control * s.friction * s.dt, 0) / speed
                vx, vy = vx * ns, vy * ns
            end

            -- Accelerate (ducked: walking at the crouched speed)
            if ws > 0 then
                local w = math.min(ws, s.maxSpeed)
                if s.ducked then w = w * s.duckSpeed end

                local add = w - (vx * wx + vy * wy)
                if add > 0 then
                    local a = math.min(s.accel * s.dt * w, add)
                    vx, vy = vx + wx * a, vy + wy * a
                end
            end

            if vx * vx + vy * vy < 1 then vx, vy = 0, 0 end

            vx, vy, vz = TryPlayerMove(s, vx, vy, 0, mins, maxs)
            if not vx then return "stuck" end

            -- StayOnGround: from 2 up, down by a step, onto a walkable floor
            local up = TraceXYZ(ply, s.x, s.y, s.z, s.x, s.y, s.z + 2, mins, maxs)
            local sz = up.HitPos.z
            local dn = TraceXYZ(ply, s.x, s.y, sz, s.x, s.y, s.z - s.stepSize, mins, maxs)
            if dn.Fraction > 0 and dn.Fraction < 1 and not dn.StartSolid and dn.HitNormal.z >= 0.7 then
                s.z = dn.HitPos.z
            end

            if Grounded(s, 0, mins, maxs) then
                s.vx, s.vy, s.vz = vx, vy, 0
                return "ground"
            end

            -- the ground is gone: only the second half of the gravity this tick
            s.onGround = false
            s.vx, s.vy, s.vz = vx, vy, -hg
            return "air"
        end

        vx, vy, vz = s.vx, s.vy, s.vz - hg

        -- AirAccelerate: wish speed capped at 30 for the gain, the full one for the rate
        if ws > 0 then
            local w = math.min(ws, s.maxSpeed)
            local add = math.min(w, 30) - (vx * wx + vy * wy)
            if add > 0 then
                local a = math.min(s.airAccel * w * s.dt, add)
                vx, vy = vx + wx * a, vy + wy * a
            end
        end

        vx, vy, vz = TryPlayerMove(s, vx, vy, vz, mins, maxs)
        if not vx then return "stuck" end

        -- CategorizePosition, every tick (a hull beside a brush finds its top without hitting it)
        if Grounded(s, vz, mins, maxs) then
            s.vx, s.vy, s.vz = vx, vy, 0
            s.onGround = true
            return "land"
        end

        -- FinishGravity
        s.vx, s.vy, s.vz = vx, vy, vz - hg
        return "air"
    end

    -- move keys relative to one yaw, re-expressed against another
    local function Rotate(fm, sm, fromYaw, toYaw)
        local d = math.rad(toYaw - fromYaw)        -- same convention as Inject
        local c, s = math.cos(d), math.sin(d)
        return fm * c - sm * s, fm * s + sm * c
    end

    -- lobotomy's variants; turn = degrees the view keeps turning per tick
    local VARIANTS = {
        {duck = false, keys = false}, {duck = true, keys = false},
        {duck = false, keys = true}, {duck = true, keys = true},
    }

    -- One candidate, at most `ticks` ticks: keysAt(k) gives that tick's fm, sm and yaw. Returns
    -- a plan {steps = {{duck, fm, sm, yaw, origin}}, k, contact} when it edge bugs; the path it
    -- flew goes into `path` when one is given (only then are Vectors made for every tick).
    local function Simulate(ply, ticks, duck, keysAt, target, path)
        local s = NewSim(ply)
        local steps = {}
        if path then path[1] = Vector(s.x, s.y, s.z) end

        for k = 1, ticks do
            if s.vz > 0 then break end

            local fm, sm, yaw = keysAt(k)
            local prevVz = s.vz
            steps[k] = {duck, fm, sm, yaw, s.x, s.y, s.z}

            local r = SimTick(s, duck, fm, sm, yaw)
            if path then path[#path + 1] = Vector(s.x, s.y, s.z) end
            if r ~= "air" then return end

            if prevVz < target and AtTarget(s.vz, target) then
                -- only a plan that is kept gets real step tables
                local out = {}
                for i, st in ipairs(steps) do
                    out[i] = {duck = st[1], fm = st[2], sm = st[3], yaw = st[4], origin = Vector(st[5], st[6], st[7])}
                end
                return {steps = out, k = k, hits = 0, contact = Vector(s.x, s.y, s.z)}
            end
        end
    end

    -- the first of lobotomy's variants that edge bugs; the no-keys fall with your current duck
    -- state doubles as the drawn preview
    local function FindEdgebug(ply, cmd, ticks, count, turn, preview)
        local target = Target(ply)
        local fm0, sm0, yaw0 = cmd:GetForwardMove(), cmd:GetSideMove(), realAng.y
        local ducked = ply:Crouching()

        local function NoKeys() return 0, 0, yaw0 end
        local function Keys(k) return fm0, sm0, yaw0 + turn * (k - 1) end

        for vi = 1, count do
            local var = VARIANTS[vi]
            local path = (preview and not var.keys and var.duck == ducked) and preview or nil

            local plan = Simulate(ply, ticks, var.duck, var.keys and Keys or NoKeys, target, path)
            if plan then
                plan.variant = tostring(vi - 1)
                return plan
            end
        end
    end

    -- Advanced edge bug: a fan of air-strafe directions around where you fly, each ducked and
    -- standing. Air acceleration only adds speed along the wish direction up to 30, so any
    -- direction within acos(30 / speed) of the flight changes nothing (at 250 u/s that is +-83
    -- degrees); the lines go over the part of the fan that does steer, from that angle out to
    -- `spread` on each side, plus one straight line with no keys. The edge bug reached soonest
    -- wins, on a tie the one turning least; replaying it strafes you onto that edge.
    -- Once one is found the others only run up to its tick: they can't beat it after that.
    local function FindSteered(ply, ticks, lines, spread, paths)
        local target = Target(ply)
        local vel = ply:GetVelocity()
        local speed = vel:Length2D()
        local base = speed > 30 and math.deg(math.atan2(vel.y, vel.x)) or realAng.y
        local yaw0 = realAng.y
        local best

        local dead = speed > 30 and math.deg(math.acos(math.Clamp(30 / speed, 0, 1))) or 0
        local from = math.min(dead, spread)
        local perSide = math.max(1, math.floor(lines / 2))

        -- offsets, nearest to the flight first: 0 (no keys), then outwards on both sides
        local offsets = {false}
        for n = 0, perSide - 1 do
            local a = perSide > 1 and (from + (spread - from) * n / (perSide - 1)) or (from + spread) / 2
            offsets[#offsets + 1] = a
            offsets[#offsets + 1] = -a
        end

        for _, duck in ipairs({ply:Crouching(), not ply:Crouching()}) do
            for _, o in ipairs(offsets) do
                local off, fm, sm = 0, 0, 0
                if o then
                    off = o
                    local rot = math.rad(base + off - yaw0)
                    fm, sm = math.cos(rot) * 10000, -math.sin(rot) * 10000
                end

                local limit = best and best.k or ticks
                local path = paths and {} or nil
                local plan = Simulate(ply, limit, duck, function() return fm, sm, yaw0 end, target, path)
                if path then paths[#paths + 1] = path end

                if plan and (not best or plan.k < best.k
                    or (plan.k == best.k and math.abs(off) < math.abs(best.offset))) then
                    plan.offset = off
                    plan.variant = string.format("steer %+d%s", math.floor(off + 0.5), duck and " ducked" or "")
                    best = plan
                end
            end
        end

        return best
    end

    -- texture bug -----------------------------------------------------------------------
    -- Port of the CS:GO texturebug.cpp from hackvshack (texture_bug + texturebug_v2), with the
    -- engine prediction replaced by SimTick. The bug: the game treats the hull as resting on a
    -- brush it is actually beside / inside of, so after the tick the vertical speed is half the
    -- gravity either way - -hg (like a pixel surf) or +hg (it put you "on top") - and you stay on
    -- the wall. It only happens with almost no speed into the wall, which is why it is searched
    -- with tiny presses (0.5 .. 30) at small angles to the wall. Left out of the port: packet
    -- choke (Lua can't hold packets), airstuck and the headsurf that rewrote sv_gravity.
    local TB = {scan = 0, status = "idle", scanV2 = 0}
    MV.TB = TB

    local wallTr = {mask = MASK_PLAYERSOLID_BRUSHONLY}

    -- either sign of the half gravity
    local function TBHit(vz, target)
        return AtTarget(vz, target) or AtTarget(vz, -target)
    end

    -- keys toward a world yaw with some strength, as seen from the real view
    local function KeysToward(yaw, mag)
        local rot = math.rad(yaw - realAng.y)
        return math.cos(rot) * mag, -math.sin(rot) * mag
    end

    -- detect_wall: 16 directions from the origin, a line every `zStep` units over the hull's
    -- height reaching 2 units past the hull; a face with |n.z| <= maxNz that faces the ray.
    -- The scan starts at the direction found last (kept per feature in S.scan).
    -- anyWall also sees entity walls (props, doors, func_brush ...): what the player collides
    -- with, not only the world's brushes
    local function DetectWall(S, ply, pos, mins, maxs, zStep, maxNz, anyWall, extra)
        local hx = math.max(math.abs(mins.x), math.abs(maxs.x))
        local hy = math.max(math.abs(mins.y), math.abs(maxs.y))
        local step = math.pi * 2 / 16
        wallTr.mask = anyWall and MASK_PLAYERSOLID or MASK_PLAYERSOLID_BRUSHONLY
        wallTr.filter = ply

        for n = 0, 15 do
            local a = ((S.scan or 0) + n * step) % (math.pi * 2)
            local dx, dy = math.cos(a), math.sin(a)
            local reach = math.min(hx / math.max(math.abs(dx), 1e-6), hy / math.max(math.abs(dy), 1e-6)) + (extra or 2)
            local best

            for z = pos.z + mins.z, pos.z + maxs.z, zStep do
                wallTr.start = Vector(pos.x, pos.y, z)
                wallTr.endpos = Vector(pos.x + dx * reach, pos.y + dy * reach, z)
                local t = util.TraceLine(wallTr)

                if t.Hit and math.abs(t.HitNormal.z) <= maxNz and t.HitNormal.x * dx + t.HitNormal.y * dy <= -0.1 then
                    if not best or t.Fraction < best.Fraction then best = t end
                end
            end

            if best then
                S.scan = a
                return best.HitNormal.x, best.HitNormal.y, best.HitPos.z
            end
        end

        S.scan = 0
    end

    -- the plane the hull itself touches (hull traces 2 units out in 16 directions), for walls
    -- a line from the centre doesn't see right - on a diagonal the box touches with a corner
    local function TouchedWall(S, ply, pos, mins, maxs)
        local step = math.pi * 2 / 16
        local best, bestF

        for n = 0, 15 do
            local a = ((S.scan or 0) + n * step) % (math.pi * 2)
            local t = TraceXYZ(ply, pos.x, pos.y, pos.z, pos.x + math.cos(a) * 2, pos.y + math.sin(a) * 2, pos.z, mins, maxs)

            if t.Hit and not t.StartSolid and t.HitNormal.z < 0.7 and (not best or t.Fraction < bestF) then
                best, bestF = {t.HitNormal.x, t.HitNormal.y, a}, t.Fraction
            end
        end

        if best then
            S.scan = best[3]
            return best[1], best[2], pos.z + (mins.z + maxs.z) / 2
        end
    end

    -- The press list (rebuilt only when its settings change): press strength x angle to the
    -- wall x side x duck state; with `axes` also the four map axes x strength x duck state
    -- (only the ones pointing into the wall are tried). Both sides are always in it, so the
    -- scores survive the side changing.
    local function CandidateList(S, m, ducks, axes)
        local key = table.concat({m.tbFwd1, m.tbFwd2, m.tbAngleStart, m.tbAngleEnd, m.tbWiggle,
            #ducks, tostring(ducks[1]), tostring(axes)}, "|")
        if S.listKey == key then return S.list end

        local list = {}
        local forwards = {m.tbFwd1, m.tbFwd2, 0.75, 0.5, 1, 2.125, 2.875, 5, 15, 30}
        local wiggle = math.max(m.tbWiggle, 0.1)

        -- any wall: also strong presses, a box edge on a diagonal can need more than 30 to pin
        if axes then
            forwards[#forwards + 1] = 60
            forwards[#forwards + 1] = 120
            forwards[#forwards + 1] = 250
        end

        for _, duck in ipairs(ducks) do
            if axes then
                for axis = 0, 3 do
                    for _, f in ipairs(forwards) do
                        list[#list + 1] = {duck = duck, f = f, axis = axis * 90, score = 0}
                    end
                end
            end

            for _, f in ipairs(forwards) do
                for a = m.tbAngleStart, m.tbAngleEnd - 1e-4, wiggle do
                    list[#list + 1] = {duck = duck, f = f, a = a, side = 1, score = 0}
                    list[#list + 1] = {duck = duck, f = f, a = a, side = -1, score = 0}
                end
            end
        end

        S.list, S.listKey, S.cursor, S.dirty = list, key, 0, false
        return list
    end

    -- The catch, shared by the texture bug and the wall hang (S = their state, anyWall = the
    -- wall hang's extras). Your keys first ("natural hit"), then the press that caught last
    -- time, then the presses next to it, then the scored bruteforce; failing that, the press
    -- that leaves the hull closest to the wall (wall hug) when that gap is under the
    -- threshold. While really caught and nothing simulated keeps it, the last press is kept.
    -- Every press is held for up to `tbAhead` ticks: one that catches a few ticks from now
    -- counts and is then held through S.last until it does. The state is read once per tick
    -- and every candidate runs on a cheap copy of it; only `tbBudget` list candidates run per
    -- tick, the next tick carrying on; presses that caught gain a point and the list is
    -- re-sorted now and then. On the ground it only runs right after a catch.
    -- anyWall: slanted walls count (|n.z| up to 0.7 instead of 0.1), a wall the lines don't
    -- find is looked for by what the hull touches, and the map axes join the list.
    -- Returns true when it set the keys.
    local function CatchCore(S, cmd, ply, onGround, vz, anyWall)
        local m = cfg.move
        local target = Target(ply)
        local now = engine.TickCount()
        if not onGround and TBHit(vz, target) then S.catchTick = now end

        if onGround and now - (S.catchTick or -100) > 8 then
            S.status = "on the ground"
            return false
        end

        local pos, mins, maxs = ply:GetPos(), ply:OBBMins(), ply:OBBMaxs()
        -- any wall looks a little further out, so it can close in on a wall it isn't touching yet
        local nx, ny, wz = DetectWall(S, ply, pos, mins, maxs, math.Clamp(m.tbZStep, 1, 16), anyWall and 0.7 or 0.1, anyWall,
            anyWall and math.Clamp(m.whApproach, 0, 16) + 2 or 2)
        if not nx and anyWall then nx, ny, wz = TouchedWall(S, ply, pos, mins, maxs) end

        if not nx then
            S.status = "no wall"
            S.last = nil
            return false
        end

        local nl = math.sqrt(nx * nx + ny * ny)
        if nl < 1e-4 then return false end
        nx, ny = nx / nl, ny / nl

        local curDuck = cmd:KeyDown(IN_DUCK)
        local view = realAng.y
        local caught = TBHit(vz, target)
        local ahead = math.Clamp(math.floor(m.tbAhead), 1, 8)
        local base = NewSim(ply)

        local function Apply(fm, sm, duck)
            cmd:SetForwardMove(fm)
            cmd:SetSideMove(sm)
            if duck then cmd:AddKey(IN_DUCK) else cmd:RemoveKey(IN_DUCK) end
        end

        -- support distance: the gap left between the hull and the wall, at the wall's height
        local hx = math.max(math.abs(mins.x), math.abs(maxs.x))
        local hy = math.max(math.abs(mins.y), math.abs(maxs.y))
        local halfN = math.abs(nx) * hx + math.abs(ny) * hy

        local function Gap(sim)
            wallTr.start = Vector(sim.x, sim.y, wz)
            wallTr.endpos = Vector(sim.x - nx * 32, sim.y - ny * 32, wz)
            return util.TraceLine(wallTr).Fraction * 32 - halfN
        end

        -- one press held for up to `ticks` ticks: the tick it catches on (nil if none) and the
        -- gap after the first tick (nil if that tick didn't stay in the air)
        local function Attempt(fm, sm, duck, ticks, wantGap)
            local s = CloneSim(base)
            if SimTick(s, duck, fm, sm, view) ~= "air" then return nil, nil end
            if TBHit(s.vz, target) then return 1, nil end

            local gap = wantGap and Gap(s) or nil
            for k = 2, ticks do
                if SimTick(s, duck, fm, sm, view) ~= "air" then break end
                if TBHit(s.vz, target) then return k, gap end
            end

            return nil, gap
        end

        -- your own keys already catch it (this tick)
        if Attempt(cmd:GetForwardMove(), cmd:GetSideMove(), curDuck, 1, false) == 1 then
            S.status = "natural hit"
            return true
        end

        local wallYaw = math.deg(math.atan2(-ny, -nx))

        -- the press that caught (or is about to) last time, kept as a world direction so turning
        -- doesn't matter; then the presses next to it
        local last = S.last
        if last then
            local fm, sm = KeysToward(last.yaw, last.f)
            local k = Attempt(fm, sm, last.duck, ahead, false)

            if k then
                Apply(fm, sm, last.duck)
                S.status = k == 1 and string.format("holding (%.3g)", last.f)
                    or string.format("holding, hit in %d (%.3g)", k, last.f)
                return true
            end

            local h = math.max(m.tbWiggle, 0.1) / 2
            for _, df in ipairs({1, 0.5, 2}) do
                for _, da in ipairs({0, -h, h, -2 * h, 2 * h}) do
                    if df ~= 1 or da ~= 0 then
                        local yaw, f = last.yaw + da, last.f * df
                        local fm2, sm2 = KeysToward(yaw, f)
                        local k2 = Attempt(fm2, sm2, last.duck, ahead, false)

                        if k2 then
                            Apply(fm2, sm2, last.duck)
                            S.last = {yaw = yaw, f = f, duck = last.duck}
                            S.status = string.format("refined, hit in %d (%.3g)", k2, f)
                            return true
                        end
                    end
                end
            end
        end

        -- angles go to the side away from where you fly along the wall; flying nearly straight
        -- at it, that side is a coin flip, so both are tried
        local vel = ply:GetVelocity()
        local rel = math.NormalizeAngle(math.deg(math.atan2(vel.y, vel.x)) - wallYaw)
        local sign = rel >= 0 and -1 or 1
        local bothSides = anyWall or vel:Length2D() < 30 or math.abs(math.abs(rel) - 180) < 20 or math.abs(rel) < 20

        local ducks = {curDuck}
        if m.tbBothDuck and not onGround then ducks[2] = not curDuck end

        local list = CandidateList(S, m, ducks, anyWall)

        -- what caught before goes first (re-sorted at most twice a second)
        if S.dirty and now - (S.sortTick or 0) > 33 then
            table.sort(list, function(p, q) return p.score > q.score end)
            S.cursor, S.dirty, S.sortTick = 0, false, now
        end

        local n = #list
        -- the any-wall list is longer (axes, both sides, strong presses): a bigger share per
        -- tick so a full round still takes about as long
        local budget = math.min(n, math.max(10, math.floor(m.tbBudget * (anyWall and 1.5 or 1))))
        local start = (S.cursor or 0) % n
        local bestGap, best = anyWall and math.huge or 1, nil

        local i, done = 0, 0
        while done < budget and i < n do
            local idx = (start + i) % n
            local c = list[idx + 1]
            i = i + 1

            local yaw
            if c.axis then
                -- a map axis, only when it points into the wall
                local r = math.rad(c.axis)
                if math.cos(r) * -nx + math.sin(r) * -ny > 0.05 then yaw = c.axis end
            elseif bothSides or c.side == 1 then
                yaw = wallYaw + c.a * sign * c.side
            end

            if yaw then
                done = done + 1

                local fm, sm = KeysToward(yaw, c.f)
                local k, gap = Attempt(fm, sm, c.duck, ahead, true)

                if k then
                    Apply(fm, sm, c.duck)
                    c.score = c.score + 1
                    S.dirty = true
                    S.last = {yaw = yaw, f = c.f, duck = c.duck}
                    S.cursor = idx                     -- start there next time
                    S.status = string.format("%s hit in %d (%.3g @ %s%s)", c.axis and "axis" or "bruteforce", k, c.f,
                        c.axis and (c.axis .. " deg world") or string.format("%.1f deg", c.a), c.duck and ", ducked" or "")
                    return true
                end

                if gap and gap < bestGap then bestGap, best = gap, {fm, sm, c.duck} end
            end
        end

        S.cursor = (start + i) % n

        -- really caught but nothing simulated keeps it: stay on what worked
        if caught and last then
            local fm, sm = KeysToward(last.yaw, last.f)
            Apply(fm, sm, last.duck)
            S.status = "caught, keeping the last press"
            return true
        end

        if best and bestGap < m.tbHug then
            Apply(best[1], best[2], best[3])
            S.status = string.format("wall hug, gap %.3f", bestGap)
            return true
        end

        -- any wall: still a few units off - close in with the press that gets nearest, so the
        -- next ticks have contact to catch with
        if anyWall and best and bestGap < m.whApproach then
            Apply(best[1], best[2], best[3])
            S.status = string.format("closing in, gap %.2f", bestGap)
            return true
        end

        S.status = string.format("searching (%d/%d)", S.cursor, n)
        return false
    end

    local WH = {status = "idle"}
    MV.WH = WH

    local function RunTextureBug(cmd, ply, onGround, vz)
        if not cfg.move.texturebug then
            TB.status, TB.last = "idle", nil
            return false
        end
        return CatchCore(TB, cmd, ply, onGround, vz, false)
    end

    -- wall hang: the same catch on any wall (see anyWall above)
    local function RunWallHang(cmd, ply, onGround, vz)
        if not cfg.move.wallhang then
            WH.status, WH.last = "idle", nil
            return false
        end
        return CatchCore(WH, cmd, ply, onGround, vz, true)
    end

    function MV.WHStatus()
        return WH.status
    end

    function MV.TBStatus()
        return TB.status
    end

    local function Search(cmd, ply, m)
        local ticks = math.Clamp(math.floor(m.ebTicks), 2, 64)
        local turn = 0
        if m.ebAdvanced then turn = MV.yawRate * m.ebTurnScale end

        local preview = m.ebDraw and {} or nil
        MV.plan = FindEdgebug(ply, cmd, ticks, m.ebAdvanced and 4 or 2, turn, preview)
        MV.preview = (not MV.plan and preview and #preview > 1) and preview or nil

        -- nothing with your own keys: the advanced fan, every `ebFanEvery` ticks (the fan is the
        -- expensive part; between runs the last lines stay on screen)
        if not MV.plan and m.ebSteer then
            local every = math.Clamp(math.floor(m.ebFanEvery), 1, 8)

            if engine.TickCount() % every == 0 then
                local paths = m.ebDraw and {} or nil
                MV.plan = FindSteered(ply, ticks, math.Clamp(math.floor(m.ebLines), 2, 64), math.Clamp(m.ebSpread, 5, 180), paths)
                MV.lines = paths
            end
        elseif not MV.plan then
            MV.lines = nil
        end
    end

    local function RunEdgebug(cmd, ply, onGround, vz)
        local m = cfg.move

        -- the advanced one works on its own bind as well
        if not (m.edgebug or m.ebSteer) then
            MV.plan, MV.duckHold, MV.lines, MV.preview = nil, false, nil, nil
            return
        end

        -- lobotomy keeps duck after a ducked edge bug until the fall picks up again
        if onGround then MV.duckHold = false end
        if MV.duckHold and not MV.plan and vz < -40 then MV.duckHold = false end
        if MV.duckHold then cmd:AddKey(IN_DUCK) end

        if onGround then
            MV.plan, MV.lines, MV.preview = nil, nil, nil
            MV.status = "on the ground"
            return
        end

        if vz >= 0 then
            MV.preview = nil
            MV.status = "rising"
            return
        end

        -- a running plan whose next step no longer matches where we are is dropped and the
        -- search is done again right away
        local plan = MV.plan
        if plan then
            local st = plan.steps[plan.hits + 1]
            if not st or ply:GetPos():DistToSqr(st.origin) > 4 then MV.plan = nil end
        end

        if not MV.plan then Search(cmd, ply, m) end

        plan = MV.plan
        if not plan then
            MV.status = "searching"
            return
        end

        local i = plan.hits + 1
        local st = plan.steps[i]

        if st.duck then
            cmd:AddKey(IN_DUCK)
            MV.duckHold = true
        else
            cmd:RemoveKey(IN_DUCK)
        end

        -- the keys the simulation used, turned to the view you have now (silent)
        local fm, sm = Rotate(st.fm, st.sm, st.yaw, realAng.y)
        cmd:SetForwardMove(fm)
        cmd:SetSideMove(sm)

        plan.hits = i
        MV.status = string.format("edge bug in %d ticks (%s)", plan.k - i + 1, plan.variant)

        if i >= plan.k then MV.plan = nil end
    end

    function MV.Status()
        return string.format("%s | eb %d  tb %d", MV.status, MV.hits, MV.tbHits)
    end

    function MV.Run(cmd, ply)
        -- mouse turn per tick, for the advanced variants
        local yaw = realAng.y
        if MV.lastYaw then MV.yawRate = math.NormalizeAngle(yaw - MV.lastYaw) end
        MV.lastYaw = yaw

        if ply:GetMoveType() ~= MOVETYPE_WALK or ply:WaterLevel() > 1 or ply:InVehicle() then
            MV.plan, MV.duckHold, MV.preview, MV.lines = nil, false, nil, nil
            MV.prevVz, MV.prevAt = 0, false
            return
        end

        local onGround = ply:IsOnGround()
        local vz = ply:GetVelocity().z
        local target = Target(ply)

        -- a real edge bug: at the signature after a faster fall, still in the air (+hg too:
        -- the texture bug can come out on that side)
        local at = not onGround and (AtTarget(vz, target) or AtTarget(vz, -target))
        -- a run of ticks at it: short = edge bug (counted when the run ends), MV.tbMinHold or
        -- more = texture bug (counted when it gets there, the time shown while it lasts)
        if at then
            if MV.atRun == 0 then
                if MV.prevVz < target - 0.5 then
                    MV.atRun, MV.runStart = 1, CurTime()
                end
            else
                MV.atRun = MV.atRun + 1
            end

            if MV.atRun == MV.tbMinHold then
                MV.tbHits = MV.tbHits + 1
                MV.flashText = "texturebug"
            end
            if MV.atRun >= MV.tbMinHold then MV.flash = CurTime() end
        else
            if MV.atRun > 0 and MV.atRun < MV.tbMinHold then
                MV.hits = MV.hits + 1
                MV.flashText = "edgebug"
                MV.flash = CurTime()
            end
            MV.atRun = 0
        end
        MV.prevVz, MV.prevAt = vz, at

        -- texture bug first: when it set the keys it owns the tick
        if RunWallHang(cmd, ply, onGround, vz) or RunTextureBug(cmd, ply, onGround, vz) then
            MV.plan, MV.lines, MV.preview = nil, nil, nil
            return
        end

        RunEdgebug(cmd, ply, onGround, vz)
    end
end

-- mouse lock: while a plan runs the view turns slower, so the turn it counted on holds
do
    local cvMYaw, cvMPitch = GetConVar("m_yaw"), GetConVar("m_pitch")

    AddHook("InputMouseApply", "edgebuglock", function(cmd, x, y, ang)
        local lock = cfg.move.ebLock
        if not MV.plan or lock <= 0 then return end

        local f = 1 - math.Clamp(lock, 0, 0.95)

        ang.p = math.Clamp(ang.p + y * cvMPitch:GetFloat() * f, -89, 89)
        ang.y = math.NormalizeAngle(ang.y - x * cvMYaw:GetFloat() * f)
        cmd:SetViewAngles(ang)
        return true
    end)
end

do
    -- a path as one polyline; `stride` skips points (the fan has many, faint ones need few)
    local function DrawPath(pts, stride)
        local n = #pts
        if n < 2 then return end

        local prev = pts[1]:ToScreen()
        local i = 1

        while i < n do
            i = math.min(i + stride, n)
            local cur = pts[i]:ToScreen()
            if prev.visible and cur.visible then surface.DrawLine(prev.x, prev.y, cur.x, cur.y) end
            prev = cur
        end
    end

    AddHook("HUDPaint", "edgebug", function()
        if IsHidden() then return end
        local m = cfg.move

        if (m.edgebug or m.ebSteer) and m.ebDraw then
            local plan = MV.plan

            -- the advanced fan, faint, every third point
            if MV.lines then
                surface.SetDrawColor(255, 255, 255, 35)
                for _, path in ipairs(MV.lines) do DrawPath(path, 3) end
            end

            if plan then
                local pts = {}
                for _, st in ipairs(plan.steps) do pts[#pts + 1] = st.origin end
                pts[#pts + 1] = plan.contact

                -- green for an edge bug, cyan for a texture bug
                local r, g, b = 149, 184, 6
                if plan.kind == "tb" then r, g, b = 90, 200, 255 end

                surface.SetDrawColor(r, g, b, 230)
                DrawPath(pts, 1)

                local c = plan.contact:ToScreen()
                if c.visible then surface.DrawCircle(c.x, c.y, 6, r, g, b, 255) end
            elseif MV.preview then
                surface.SetDrawColor(255, 255, 255, 90)
                DrawPath(MV.preview, 2)
            end
        end

        if not m.ebIndicator then return end

        local age = CurTime() - MV.flash
        if age > 1.2 then return end

        local a = 255 * (1 - age / 1.2)
        local y = ScrH() / 2 + 60 - age * 12

        local tb = MV.flashText == "texturebug"
        local col = tb and Color(90, 200, 255, a) or Color(149, 184, 6, a)

        -- while still hanging, how long so far
        local text = MV.flashText
        if tb and MV.atRun >= MV.tbMinHold then
            text = string.format("%s %.1fs", cfg.move.wallhang and "wallhang" or "texturebug", CurTime() - MV.runStart)
        end

        draw.SimpleTextOutlined(text, "NyxKillFxSmall", ScrW() / 2, y, col,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, a))
        draw.SimpleTextOutlined("x" .. (tb and MV.tbHits or MV.hits), "NyxESP", ScrW() / 2, y + 14, Color(225, 225, 225, a),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, a))
    end)
end

local lastAimPos, lastAimTime = nil, 0   -- for the target marker
local lastAimWall = false                -- the last rage target was shot through a wall
local lastAimBT = nil                    -- ms the last target was shot back in time, nil = not at all
local lastAimRage = false                -- lastAimPos came from the rage bot (it has its own marker switch)

local NO_AUTOFIRE = {
    weapon_physgun = true, weapon_physcannon = true, gmod_tool = true, gmod_camera = true,
}

-- the weapon can actually shoot right now (clip, next-fire time) and isn't a tool
local function WeaponReady(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or NO_AUTOFIRE[wep:GetClass()] then return false end
    if wep:Clip1() == 0 then return false end
    return wep:GetNextPrimaryFire() <= CurTime()
end

-- usable weapon with ammo, no next-fire gating: used for hold-fire where the key stays down
local function WeaponUsable(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or NO_AUTOFIRE[wep:GetClass()] then return false end
    return wep:Clip1() ~= 0
end

-- semi-automatic guns only fire on a fresh press, so hold-fire has to release every other tick
local fireFlip = false
local function HoldFireKey(cmd, ply)
    local wep = ply:GetActiveWeapon()
    local primary = IsValid(wep) and wep.Primary
    local semi = primary and primary.Automatic == false

    if semi then
        fireFlip = not fireFlip
        if fireFlip then cmd:AddKey(IN_ATTACK) else cmd:RemoveKey(IN_ATTACK) end
    else
        cmd:AddKey(IN_ATTACK)
    end
end

-- put the real angle back if an injected one is still in the engine view
local function Restore(cmd)
    if not silentDirty then return end

    cmd:SetViewAngles(realAng)
    sentAng = Angle(realAng.p, realAng.y, 0)
    silentDirty = false
end

-- write ang into the sent cmd only; the move vector is rotated by the yaw difference so you keep
-- walking where your screen says
local function Inject(cmd, ang)
    local d = math.rad(ang.y - realAng.y)
    local c, s = math.cos(d), math.sin(d)
    local fm, sm = cmd:GetForwardMove(), cmd:GetSideMove()
    cmd:SetForwardMove(fm * c - sm * s)
    cmd:SetSideMove(fm * s + sm * c)

    cmd:SetViewAngles(ang)
    sentAng = ang
    silentDirty = true
end

-- Weapons whose recoil does not go through the view punch (from ak47hack's no-recoil): M9K and
-- a few other bases turn the eye angles themselves, the HL2 pistol's punch doesn't move its
-- bullets. Taking the punch off for them would pull the shot off the target. (On RS: a helper
-- table declared above, so no new local.)
function RS.NoPunch(ply)
    if not cfg.norecoil.exceptions then return false end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return false end

    local cls = wep:GetClass()
    return cls == "weapon_pistol" or string.StartWith(cls, "m9k_") or string.StartWith(cls, "bb_")
        or string.StartWith(cls, "unclen8_")
end

-- ang with the view punch taken off (scaled), the way the server adds it to the shot
function RS.Unpunch(ply, ang, scale)
    if scale <= 0 or RS.NoPunch(ply) then return ang end

    local punch = ply:GetViewPunchAngles()
    local out = Angle(ang.p - punch.p * scale, ang.y - punch.y * scale, 0)
    out.p = math.Clamp(math.NormalizeAngle(out.p), -89, 89)
    out.y = math.NormalizeAngle(out.y)
    return out
end

-- view angle that puts the shot on pos (optionally against view-punch recoil)
local function AimAngleTo(ply, pos, recoilOn, recoil)
    local ang = (pos - ply:GetShootPos()):Angle()

    if recoilOn and recoil > 0 and not RS.NoPunch(ply) then
        local punch = ply:GetViewPunchAngles()
        ang.p = ang.p - punch.p * recoil
        ang.y = ang.y - punch.y * recoil
    end

    ang.p = math.Clamp(math.NormalizeAngle(ang.p), -89, 89)
    ang.y = math.NormalizeAngle(ang.y)
    ang.r = 0
    return ang
end

-- ---------------------------------------------------------------------------
-- no spread for the default HL2 weapons
--   The native weapons (weapon_pistol, weapon_smg1, weapon_ar2) get their bullet spread from
--   Valve's seeded random stream, seeded with the prediction seed of the command the shot is in
--   (MD5_PseudoRandom of the command number, low byte). That makes the offset of this very shot
--   computable here, and the view angle is rotated against it on the shot tick (sent silently,
--   like the aimbot's angle). .357 / crossbow / rpg are exact already; the shotgun fires several
--   pellets with a seed each, which one view angle cannot align, so it is left alone.
-- ---------------------------------------------------------------------------

local NS = {
    cones = {                       -- tangent of the cone, like VECTOR_CONE_xDEGREES
        weapon_pistol = 0.00873,    -- 1 degree
        weapon_smg1   = 0.04362,    -- 5 degrees
        weapon_ar2    = 0.02618,    -- 3 degrees
    },
    status = "idle",
}

function NS.StatusLine()
    return NS.status
end

do
    local IA, IM, IQ, IR, NTAB = 16807, 2147483647, 127773, 2836, 32
    local NDIV = 1 + math.floor((IM - 1) / NTAB)
    local RNMX = 1 - 1.2e-7

    -- CUniformRandomStream (Valve's ran1): seed it, then call it as RandomFloat(lo, hi)
    local function Stream(seed)
        local idum = seed < 0 and seed or -seed
        local iy = 0
        local iv = {}

        local function generate()
            local j, k

            if idum <= 0 or iy == 0 then
                if -idum < 1 then idum = 1 else idum = -idum end

                for jj = NTAB + 7, 0, -1 do
                    k = math.floor(idum / IQ)
                    idum = IA * (idum - k * IQ) - IR * k
                    if idum < 0 then idum = idum + IM end
                    if jj < NTAB then iv[jj] = idum end
                end

                iy = iv[0]
            end

            k = math.floor(idum / IQ)
            idum = IA * (idum - k * IQ) - IR * k
            if idum < 0 then idum = idum + IM end

            j = math.floor(iy / NDIV)
            iy = iv[j]
            iv[j] = idum

            return iy
        end

        return function(lo, hi)
            local fl = generate() / IM
            if fl > RNMX then fl = RNMX end
            return fl * (hi - lo) + lo
        end
    end

    -- MD5_PseudoRandom: md5 of the 4 byte little endian number, 4 bytes from offset 6, little endian
    function NS.PseudoRandom(n)
        local s = string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
        local hex = util.MD5(s)

        local function byte(i)
            return tonumber(string.sub(hex, i * 2 + 1, i * 2 + 2), 16) or 0
        end

        return byte(6) + byte(7) * 256 + byte(8) * 65536 + byte(9) * 16777216
    end

    -- offsets along the view's right and up vectors that the engine adds to the shot
    function NS.Offset(seed, cone)
        local rnd = Stream(seed)

        local x = rnd(-0.5, 0.5) + rnd(-0.5, 0.5)
        local y = rnd(-0.5, 0.5) + rnd(-0.5, 0.5)

        return x * cone, y * cone
    end

    -- A view angle F such that F + a*right(F) + b*up(F) points along ang (the engine adds the
    -- spread to the view direction in the view's own frame). Solved by a few fixed-point steps.
    function NS.Compensate(ang, a, b)
        local D = ang:Forward()
        local F = D

        for _ = 1, 4 do
            local fa = F:Angle()
            local lateral = fa:Right() * a + fa:Up() * b

            local dl = D:Dot(lateral)
            local c = dl + math.sqrt(math.max(dl * dl - lateral:LengthSqr() + 1, 0))

            F = D * c - lateral
            F:Normalize()
        end

        local out = F:Angle()
        out.p = math.Clamp(math.NormalizeAngle(out.p), -89, 89)
        out.y = math.NormalizeAngle(out.y)
        out.r = 0
        return out
    end

    -- ang with the spread cancelled when a supported weapon fires in this command, else ang itself
    function NS.Fix(cmd, ply, ang, shooting)
        local n = cfg.nospread
        if not n.enabled then return ang end

        if shooting == nil then shooting = cmd:KeyDown(IN_ATTACK) end
        if not shooting then return ang end

        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then return ang end

        local cone = NS.cones[wep:GetClass()]
        if not cone then
            if n.bases then return NS.Base(cmd, ply, wep, ang) end
            return ang
        end

        local num = cmd:CommandNumber()
        local seed = (NS.PseudoRandom(num) % 2147483648) % 256 + n.seedOffset

        -- the status line shows our seed next to the one the engine put in the command, so the
        -- formula can be checked against the real thing
        -- (this GMod build has no CUserCmd:GetRandomSeed, so it is only read when it exists)
        local engineSeed = cmd.GetRandomSeed and cmd:GetRandomSeed()
            or (istable(nyxmod) and BT.M.cmd and nyxmod.GetRandomSeed(cmd)) or nil
        NS.status = string.format("#%d  seed %d  engine %s", num % 100000, seed - n.seedOffset,
            engineSeed and engineSeed ~= 0 and tostring((engineSeed % 2147483648) % 256) or "?")

        local a, b = NS.Offset(seed, cone * n.scale)
        return NS.Compensate(ang, a, b)
    end

    -- SWB / CW 2.0 (ported from ak47hack): the weapon's current cone (CurCone, in radians-ish
    -- units the bases scale by 25 into degrees), the random offset rolled from the command number
    -- and taken off the angle. Only right when the base rolls its spread the same way, so it is a
    -- separate, experimental switch. The global RNG is reseeded afterwards.
    function NS.Base(cmd, ply, wep, ang)
        local base = string.match(wep:GetClass(), "^(%w+)_")
        if base ~= "swb" and base ~= "cw" then return ang end

        local cone = wep.CurCone
        if not isnumber(cone) or cone <= 0 then return ang end
        if base == "swb" and ply:Crouching() then cone = cone * 0.85 end

        math.randomseed(cmd:CommandNumber())
        local out = ang - Angle(math.Rand(-cone, cone), math.Rand(-cone, cone), 0) * 25 * cfg.nospread.scale
        math.randomseed(SysTime() * 1000)

        out.p = math.Clamp(math.NormalizeAngle(out.p), -89, 89)
        out.y = math.NormalizeAngle(out.y)
        out.r = 0
        NS.status = string.format("%s cone %.4f", base, cone)
        return out
    end

    -- A plain shot of yours (no aimbot involved): the recoil (no recoil) and the spread (no
    -- spread) are taken out of the angle the shot goes out at, silently - your screen keeps the
    -- real view. True when anything was changed.
    function NS.Manual(cmd, ply, inject)
        if not cmd:KeyDown(IN_ATTACK) then return false end

        local nr = cfg.norecoil
        local ang = realAng
        if nr.enabled then ang = RS.Unpunch(ply, realAng, nr.scale) end

        local fixed = cfg.nospread.enabled and NS.Fix(cmd, ply, ang, true) or ang
        if fixed == realAng then return false end    -- nothing to correct for this weapon

        inject(cmd, fixed)
        return true
    end
end

-- returns true when it wrote an angle into the cmd this tick
local function DoAim(cmd, ply)
    local aim = cfg.aim
    local aimPos

    local active = aim.enabled and IsBindDown(aim.key)
        and not gui.IsGameUIVisible() and not IsValid(menu)

    if not active then lockedTarget = nil end

    local shooting = cmd:KeyDown(IN_ATTACK)
    local autoFire = active and aim.autoFire and WeaponReady(ply)

    -- silent + fire-only only touches the angles on ticks where a shot goes out
    local aimTick

    if active and (shooting or autoFire or not (aim.silent and aim.fireOnly)) then
        local target, pos, tick = FindTarget(ply, realAng)
        if IsValid(target) then aimPos, aimTick = pos, tick end
    end

    if not aimPos then return false end

    lastAimPos, lastAimTime = aimPos, CurTime()
    lastAimWall, lastAimRage = false, false

    -- a record from the past: the shot carries that tick, so the server aims at that moment
    lastAimBT = nil
    if aimTick and (shooting or autoFire) and BT.SetTick(cmd, aimTick) then
        lastAimBT = (engine.TickCount() - aimTick) * engine.TickInterval() * 1000
    end

    local aimAng = AimAngleTo(ply, aimPos, aim.recoilOn, aim.recoil)

    if aim.silent then
        Inject(cmd, NS.Fix(cmd, ply, aimAng, shooting or autoFire))

        if autoFire and not shooting then cmd:AddKey(IN_ATTACK) end
    else
        -- exponential approach: 1 = instant, 30 = slow, frame-rate independent
        local smooth = math.Clamp(aim.smooth, 1, 30)
        local t = 1
        if smooth > 1 then t = 1 - math.exp(-FrameTime() * 120 / smooth) end

        local newAng = LerpAngle(t, realAng, aimAng)
        cmd:SetViewAngles(newAng)
        sentAng = newAng
        silentDirty = false

        -- only pull the trigger once the crosshair is actually on target
        if autoFire and not shooting then
            local off = math.abs(math.NormalizeAngle(newAng.p - aimAng.p))
                + math.abs(math.NormalizeAngle(newAng.y - aimAng.y))
            if off < 2 then cmd:AddKey(IN_ATTACK) end
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- rage aimbot: whole-map scan, always silent, shoots for you
-- ---------------------------------------------------------------------------

-- autowall -------------------------------------------------------------------
-- GMod does not tell the client how far a bullet gets through a surface (that is the weapon's
-- own code), so this is an estimate: every wall on the line costs thickness * its material's
-- hardness, and the shot "goes through" when the total stays inside cfg.rage.wallPower and the
-- wall count stays inside cfg.rage.wallCount. Which materials count at all is the checkbox list.
local AW = {}

AW.classes = {
    {key = "glass",    cost = 0.25, mats = {"GLASS"}},
    {key = "wood",     cost = 0.5,  mats = {"WOOD"}},
    {key = "plastic",  cost = 0.4,  mats = {"PLASTIC", "COMPUTER"}},
    {key = "thin",     cost = 0.3,  mats = {"VENT", "GRATE", "FOLIAGE", "EGGSHELL"}},
    {key = "tile",     cost = 1.0,  mats = {"TILE"}},
    {key = "dirt",     cost = 1.0,  mats = {"DIRT", "SAND", "SNOW", "GRASS"}},
    {key = "concrete", cost = 1.8,  mats = {"CONCRETE"}},
    {key = "metal",    cost = 2.2,  mats = {"METAL"}},
    {key = "other",    cost = 1.0,  mats = {"DEFAULT", "SLOSH", "CLIP", "WARPSHIELD"}},
}

AW.byMat = {}
for _, c in ipairs(AW.classes) do
    if c.key == "other" then AW.other = c end

    for _, name in ipairs(c.mats) do
        local code = _G["MAT_" .. name]
        if code then AW.byMat[code] = c end
    end
end

local awLine = {mask = MASK_SHOT}
local awProbe = {mask = MASK_SHOT}

-- the cost of the walls between from and to (a number, 0 = a clear line), or nil when the shot
-- cannot get through; ply and victim are never walls
function AW.Cost(ply, victim, from, to)
    local r = cfg.rage

    -- SWB / M9K: the weapon's own penetration rules instead of the estimate (a nominal cost for
    -- the damage estimate when it gets through)
    if r.weaponWall then
        local ok = AW.WeaponPen(ply, victim, from, to)
        if ok ~= nil then return ok and r.wallPower * 0.5 or nil end
    end

    local dir = to - from
    local total = dir:Length()
    if total < 1 then return 0 end
    dir:Mul(1 / total)

    local filter = {ply, victim}
    local start = from
    local cost, walls = 0, 0

    for _ = 1, r.wallCount + 8 do
        awLine.start = start
        awLine.endpos = to
        awLine.filter = filter

        local tr = util.TraceLine(awLine)
        if not tr.Hit then return cost end
        if tr.HitSky then return nil end

        local ent = tr.Entity

        -- someone else standing in the line is not a wall; the line just goes on past them
        if IsValid(ent) and (ent:IsPlayer() or ent:IsNPC()) then
            filter[#filter + 1] = ent
            start = tr.HitPos
        else
            local class = AW.byMat[tr.MatType] or AW.other
            if not r.wall[class.key] then return nil end

            -- how deep the wall is: a trace that starts inside it reports where it leaves it
            local entry = tr.HitPos
            local reach = math.min(96, entry:Distance(to))

            awProbe.start = entry + dir * 0.5
            awProbe.endpos = entry + dir * reach
            awProbe.filter = filter

            local p = util.TraceLine(awProbe)
            if p.AllSolid then return nil end        -- it does not end within reach

            local thick = 1
            if p.StartSolid and p.FractionLeftSolid > 0 then
                thick = 0.5 + p.FractionLeftSolid * (reach - 0.5)
            end

            walls = walls + 1
            cost = cost + thick * class.cost

            if walls > r.wallCount or cost > r.wallPower then return nil end

            start = entry + dir * (thick + 1)
            if start:DistToSqr(from) >= total * total then return cost end
        end
    end

    return nil
end

-- ported from ak47hack's rage bot --------------------------------------------------------------
-- (its own code needs the zxcmodule binary for spread prediction, tick writes and simulation;
-- these parts are plain Lua. Two of its bugs are fixed on the way: the hitgroup checks
-- "group == 4 or group == 5 and not cfg" always skipped arms / legs, and its M9K penetration
-- returned before the per-material damage loss was ever applied.)

-- Weapon penetration, the way the two big bases do it. true / false = gets to victim or not,
-- nil = the active weapon is neither (the estimate in AW.Cost is used then).
AW.tr = {}
AW.SWB_NORMAL = bit.bor(CONTENTS_SOLID, CONTENTS_OPAQUE, CONTENTS_MOVEABLE, CONTENTS_DEBRIS, CONTENTS_MONSTER,
    CONTENTS_HITBOX, 402653442, CONTENTS_WATER)
AW.SWB_WALL = bit.bor(CONTENTS_TESTFOGVOLUME, CONTENTS_EMPTY, CONTENTS_MONSTER, CONTENTS_HITBOX)
AW.SWB_PEN = {[MAT_SAND] = 0.5, [MAT_DIRT] = 0.8, [MAT_METAL] = 1.1, [MAT_TILE] = 0.9, [MAT_WOOD] = 1.2}
AW.SWB_NOPEN = {swb_knife = true, swb_knife_m = true}
AW.M9K_PEN = {SniperPenetratedRound = 20, pistol = 9, ["357"] = 12, smg1 = 14, ar2 = 16, buckshot = 5, slam = 5, AirboatGun = 17}
AW.M9K_RICO = {SniperPenetratedRound = 10, pistol = 2, ["357"] = 5, smg1 = 4, ar2 = 5, buckshot = 0, slam = 0, AirboatGun = 9}
AW.M9K_CANRICO = {SniperPenetratedRound = true, pistol = true, buckshot = true, slam = true}
AW.M9K_SOFT = {[MAT_GLASS] = true, [MAT_PLASTIC] = true, [MAT_WOOD] = true, [MAT_FLESH] = true, [MAT_ALIENFLESH] = true}

function AW.WeaponPen(ply, victim, from, to)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return nil end

    local class = wep:GetClass()
    local dir = (to - from):GetNormalized()
    local tr = AW.tr
    tr.filter = ply

    -- SWB: one wall, steep enough (dot > 0.26), at most PenStr x material x PenMod thick
    if string.StartWith(class, "swb_") then
        if AW.SWB_NOPEN[class] or not wep.CanPenetrate or not wep.PenetrativeRange then return false end

        tr.start, tr.endpos, tr.mask = from, from + dir * wep.PenetrativeRange, AW.SWB_NORMAL
        local t = util.TraceLine(tr)
        if t.Entity == victim then return true end
        if not t.Hit or t.HitSky or -dir:Dot(t.HitNormal) <= 0.26 then return false end

        tr.start, tr.mask = t.HitPos, AW.SWB_WALL
        tr.endpos = t.HitPos + dir * (wep.PenStr or 0) * (AW.SWB_PEN[t.MatType] or 1) * (wep.PenMod or 1)
        local inside = util.TraceLine(tr)

        tr.start, tr.endpos, tr.mask = inside.HitPos, inside.HitPos + dir * 0.1, AW.SWB_NORMAL
        local out = util.TraceLine(tr)
        if out.Hit then return false end                -- still in the wall: too thick

        tr.start, tr.endpos, tr.mask = out.HitPos, out.HitPos + dir * 32768, MASK_SHOT
        return util.TraceLine(tr).Entity == victim
    end

    -- M9K: each wall is tried from the far side (depth by ammo, double for soft materials);
    -- every wall costs damage by material; ricochet-capable ammo can't go through metal
    if string.StartWith(class, "m9k_") or string.StartWith(class, "bender_") then
        local cv = GetConVar("M9KDisablePenetration")
        if (cv and cv:GetBool()) or not wep.Penetration then return false end

        local ammo = wep.Primary and wep.Primary.Ammo
        local depth = AW.M9K_PEN[ammo] or 14
        local walls = AW.M9K_RICO[ammo] or 0
        local damage = (wep.Primary and tonumber(wep.Primary.Damage)) or 30

        tr.start, tr.endpos, tr.mask = from, from + dir * 32768, MASK_SHOT
        local t = util.TraceLine(tr)

        for _ = 0, walls do
            if t.Entity == victim then return true end
            if not t.Hit or t.HitSky or t.Fraction <= 0 or damage < 1 then return false end
            if t.MatType == MAT_METAL and AW.M9K_CANRICO[ammo] and ammo ~= "SniperPenetratedRound" then return false end

            local d = depth * (AW.M9K_SOFT[t.MatType] and 2 or 1)
            tr.start, tr.endpos = t.HitPos + t.Normal * d, t.HitPos
            local back = util.TraceLine(tr)
            if back.StartSolid or back.Fraction >= 1 then return false end

            local m = t.MatType
            if ammo == "SniperPenetratedRound" then
                damage = damage * 1
            elseif m == MAT_CONCRETE or m == MAT_METAL then
                damage = damage * 0.3
            elseif m == MAT_WOOD or m == MAT_PLASTIC or m == MAT_GLASS then
                damage = damage * 0.8
            elseif m == MAT_FLESH or m == MAT_ALIENFLESH then
                damage = damage * 0.9
            else
                damage = damage * 0.5
            end

            tr.start, tr.endpos = back.HitPos, back.HitPos + t.Normal * 32768
            t = util.TraceLine(tr)
        end

        return t.Entity == victim and damage >= 1
    end

    return nil
end

-- Points to aim at for one of the hitbox names: the centres of the model's own hitbox boxes in
-- that hitgroup (head 1, chest 2, stomach 3, arms 4/5, legs 6/7), centres first, then with
-- multipoint the eight corners of each box pulled toward its centre by mpScale.
AW.GROUPS = {
    head = {[HITGROUP_HEAD] = true}, chest = {[HITGROUP_CHEST] = true}, pelvis = {[HITGROUP_STOMACH] = true},
    arms = {[HITGROUP_LEFTARM] = true, [HITGROUP_RIGHTARM] = true},
    legs = {[HITGROUP_LEFTLEG] = true, [HITGROUP_RIGHTLEG] = true},
}

function AW.Points(v, hitbox)
    local r = cfg.rage
    local bone = HITBOX_BONE[hitbox]

    -- the old way (bones), and the T-pose override (visual only, the bones are not the hitboxes)
    if (not r.realHitboxes and not r.multipoint and bone) or cfg.tpose.enabled then
        return bone and {GetAimPos(v, hitbox, true)} or {}
    end

    local set = v:GetHitboxSet()
    local want = AW.GROUPS[hitbox]
    if not set or not want then return bone and {GetAimPos(v, hitbox, true)} or {} end

    local mp = r.multipoint and ((hitbox == "head" and r.mpHead) or ((hitbox == "chest" or hitbox == "pelvis") and r.mpBody)
        or ((hitbox == "arms" or hitbox == "legs") and r.mpLimbs))
    local s = math.Clamp(r.mpScale, 0.1, 1)
    local out, corners = {}, {}

    for i = 0, (v:GetHitBoxCount(set) or 0) - 1 do
        if want[v:GetHitBoxHitGroup(i, set)] then
            local b = v:GetHitBoxBone(i, set)
            local mins, maxs = v:GetHitBoxBounds(i, set)
            local bpos, bang = b and v:GetBonePosition(b)

            if bpos and bang and mins and maxs then
                local c = (mins + maxs) * 0.5
                out[#out + 1] = LocalToWorld(c, angle_zero, bpos, bang)

                if mp then
                    for k = 0, 7 do
                        local corner = Vector(bit.band(k, 1) > 0 and maxs.x or mins.x,
                            bit.band(k, 2) > 0 and maxs.y or mins.y, bit.band(k, 4) > 0 and maxs.z or mins.z)
                        corners[#corners + 1] = LocalToWorld(c + (corner - c) * s, angle_zero, bpos, bang)
                    end
                end
            end
        end
    end

    for _, p in ipairs(corners) do out[#out + 1] = p end

    if #out == 0 and bone then return {GetAimPos(v, hitbox, true)} end
    return out
end

-- the reload animation is playing (the viewmodel's activity, not the sequence index ak47hack
-- compared the activities against)
AW.RELOAD_ACTS = {}
for _, name in ipairs({"ACT_VM_RELOAD", "ACT_VM_RELOAD_SILENCED", "ACT_VM_RELOAD_DEPLOYED", "ACT_VM_RELOAD_IDLE",
    "ACT_VM_RELOAD_EMPTY", "ACT_VM_RELOADEMPTY", "ACT_VM_RELOAD_M203", "ACT_VM_RELOAD_INSERT", "ACT_VM_RELOAD_INSERT_PULL",
    "ACT_VM_RELOAD_END", "ACT_VM_RELOAD_END_EMPTY", "ACT_VM_RELOAD_INSERT_EMPTY", "ACT_VM_RELOAD2"}) do
    if _G[name] then AW.RELOAD_ACTS[_G[name]] = true end
end

-- Only a reload that is really still going counts. Many weapons stay on the reload sequence's
-- last frame after it ends (no idle until the next shot), so "the sequence is a reload" alone
-- blocked the rage bot until you fired once yourself. Now it also has to be still playing
-- (cycle < 0.98) and the weapon must not be able to fire yet; and a block that lasts over 4 s
-- while there are bullets in the clip is dropped as stuck.
function AW.Reloading(ply)
    local vm = ply:GetViewModel()
    local wep = ply:GetActiveWeapon()
    if not IsValid(vm) or not IsValid(wep) then
        AW.reloadSince = nil
        return false
    end

    local reload = AW.RELOAD_ACTS[vm:GetSequenceActivity(vm:GetSequence())]
        and vm:GetCycle() < 0.98
        and (wep:Clip1() == 0 or wep:GetNextPrimaryFire() > CurTime())

    if not reload then
        AW.reloadSince = nil
        return false
    end

    local now = CurTime()
    AW.reloadSince = AW.reloadSince or now
    if now - AW.reloadSince > 4 and wep:Clip1() > 0 then return false end

    return true
end

-- the target filters ak47hack has on top of ours
function AW.Ignored(v)
    local r = cfg.rage
    if r.ignoreBots and v:IsBot() then return true end
    if r.ignoreAdmins and v:IsAdmin() then return true end
    if r.ignoreFrozen and v:IsFlagSet(FL_FROZEN) then return true end
    if r.ignoreNoclip and v:GetMoveType() == MOVETYPE_NOCLIP then return true end
    if r.ignoreGod and v:GetColor().a < 255 then return true end
    if r.ignoreVehicle and v:InVehicle() then return true end
    if r.ignoreNodraw and v:IsEffectActive(EF_NODRAW) then return true end
    return false
end

-- hitboxes to try for v, in priority order
local function RageHitboxOrder(v)
    local r = cfg.rage
    local list = {}

    local bodyFirst = r.bodyBelow > 0 and v:Health() <= r.bodyBelow
    if not bodyFirst and r.head then list[#list + 1] = "head" end
    if r.chest then list[#list + 1] = "chest" end
    if r.pelvis then list[#list + 1] = "pelvis" end
    if r.arms then list[#list + 1] = "arms" end
    if r.legs then list[#list + 1] = "legs" end
    if bodyFirst and r.head then list[#list + 1] = "head" end

    -- force body aim: the head is left out (the chest stands in when no body hitbox is on)
    if r.forceBaim then
        local body = {}
        for _, hb in ipairs(list) do
            if hb ~= "head" then body[#body + 1] = hb end
        end
        if #body == 0 then body[1] = "chest" end
        return body
    end

    return list
end

local function DoRage(cmd, ply)
    local r = cfg.rage
    if not r.enabled or gui.IsGameUIVisible() or IsValid(menu) then return false end

    -- empty clip with ammo left: reload instead (ak47hack's auto reload)
    local wep = ply:GetActiveWeapon()
    if r.autoReload and IsValid(wep) and wep:Clip1() == 0 and wep:GetMaxClip1() > 0
        and ply:GetAmmoCount(wep:GetPrimaryAmmoType()) > 0 then
        cmd:AddKey(IN_RELOAD)
        return false
    end

    -- the reload animation is playing: nothing would come out of the gun
    if r.skipReload and AW.Reloading(ply) then return false end

    -- like the legit aimbot: angles are only touched on ticks where a shot goes out
    local shooting = cmd:KeyDown(IN_ATTACK)
    local autoFire = r.autoFire and (r.holdFire and WeaponUsable(ply) or WeaponReady(ply))
    if not (shooting or autoFire) then return false end

    local shootPos = ply:GetShootPos()
    local fwd = realAng:Forward()
    local lead = (r.predictOn and r.predict > 0) and (r.predict * engine.TickInterval()) or 0

    local bestEnt, bestPos, bestScore, bestWall, bestTick = nil, nil, math.huge, false, nil

    -- max targets: only the N nearest are scanned (multipoint makes each one costly)
    local players = player.GetAll()
    if r.maxTargets > 0 then
        table.sort(players, function(a, b) return a:GetPos():DistToSqr(shootPos) < b:GetPos():DistToSqr(shootPos) end)
    end
    local scanned = 0

    for _, v in ipairs(players) do
        if v == ply or not v:Alive() or v:IsDormant() then continue end
        if v:GetObserverMode() ~= OBS_MODE_NONE then continue end
        if r.teamCheck and v:Team() == ply:Team() then continue end
        if FR.Is(v) then continue end
        if r.targetOnly and not FR.IsTarget(v) then continue end
        if r.ignoreFriends and v:GetFriendStatus() == "friend" then continue end
        if AW.Ignored(v) then continue end
        if shootPos:Distance(v:GetPos()) * 0.01905 > r.maxDist then continue end

        scanned = scanned + 1
        if r.maxTargets > 0 and scanned > r.maxTargets then break end

        ApplyResolver(v)        -- no-op unless v is the resolver's current target
        v:SetupBones()

        -- first hitbox in priority order that can be hit; a hitbox behind a wall that goes
        -- through is only kept until a hitbox that is plainly visible turns up
        -- (a record from backtrack beats a wall: it is a clean shot, only at an older moment)
        local pickPos, pickAngle, pickDist, pickWall, pickTick

        -- minimum damage: what a hitbox must take at least (never more than the HP left: a kill
        -- always counts); 0 = no check
        local need = math.min(MV.MinDamage(), v:Health())

        -- the same shift for every point of this player (lead + extrapolation)
        local shift = Vector(0, 0, 0)
        if lead > 0 then shift = shift + (v:GetVelocity() - ply:GetVelocity()) * lead end
        if r.extrapOn then shift = shift + BT.X.Offset(ply, v, shootPos) end

        for _, hitbox in ipairs(RageHitboxOrder(v)) do
            -- this hitbox can't do the minimum damage even in the open: the next one
            if need > 0 and MV.EstDamage(ply, hitbox) < need then continue end

            -- every point of the hitbox (centres, then multipoint corners): the first one in the
            -- open wins; the first that only goes through a wall is kept as a fallback
            local open = false

            for _, base in ipairs(AW.Points(v, hitbox)) do
                local pos = base + shift
                local dir = pos - shootPos
                local dist = dir:Length()

                if dist >= 1 then
                    dir:Mul(1 / dist)
                    local angle = math.deg(math.acos(math.Clamp(fwd:Dot(dir), -1, 1)))

                    if angle <= r.fov then
                        if not r.visOnly or IsVisible(ply, v, shootPos, pos) then
                            pickPos, pickAngle, pickDist, pickWall, pickTick = pos, angle, dist, false, nil
                            open = true
                            break
                        elseif r.autowall and not pickPos then
                            local cost = AW.Cost(ply, v, shootPos, pos)
                            if cost and (need <= 0 or MV.EstDamage(ply, hitbox, cost) >= need) then
                                pickPos, pickAngle, pickDist, pickWall, pickTick = pos, angle, dist, true, nil
                            end
                        end
                    end
                end
            end

            if open then break end

            -- not hittable now: an older position of the same hitbox that was in the open
            -- (backtrack records only head / chest / pelvis)
            if r.visOnly and HITBOX_BONE[hitbox] and (not pickPos or pickWall) then
                local bpos, btick, bangle, bdist = BT.Find(ply, v, hitbox, shootPos, fwd, r.fov)

                if bpos then
                    pickPos, pickAngle, pickDist, pickWall, pickTick = bpos, bangle, bdist, false, btick
                    break
                end
            end
        end

        if pickPos then
            local score
            if r.priority == "health" then
                score = v:Health()
            elseif r.priority == "fov" then
                score = pickAngle
            else
                score = pickDist
            end

            if FR.IsTarget(v) then score = score * 0.1 end

            -- anything that is plainly visible is shot before something behind a wall
            if pickWall then score = score + 1e6 end

            if score < bestScore then
                bestScore, bestEnt, bestPos, bestWall, bestTick = score, v, pickPos, pickWall, pickTick
            end
        end
    end

    if not bestEnt then return false end

    lastAimPos, lastAimTime, lastAimWall, lastAimRage = bestPos, CurTime(), bestWall, true

    -- a record from the past: the shot carries that tick, so the server aims at that moment
    lastAimBT = nil
    if bestTick and BT.SetTick(cmd, bestTick) then
        lastAimBT = (engine.TickCount() - bestTick) * engine.TickInterval() * 1000
    end
    aimTargetEnt, aimTargetTime = bestEnt, CurTime()

    if r.autoStop and ply:IsOnGround() then
        cmd:SetForwardMove(0)
        cmd:SetSideMove(0)
    end

    Inject(cmd, NS.Fix(cmd, ply, AimAngleTo(ply, bestPos, r.recoilOn, r.recoil), true))

    if autoFire then
        if r.holdFire then
            HoldFireKey(cmd, ply)               -- trigger stays down while the target lives
        elseif not shooting then
            cmd:AddKey(IN_ATTACK)
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- anti-aim: the sent angle is replaced on every tick that isn't a shot
-- ---------------------------------------------------------------------------

local aaTick = 0
local aaSpin = 0
local aaRandPitch, aaRandYaw = 0, 0
local aaActive = false      -- an anti-aim angle went out this tick (for the indicator)

local function AAStateName(ply)
    if not ply:IsOnGround() then return "air" end
    if ply:GetVelocity():Length2D() > 10 then return "move" end
    return "stand"
end

local function NearestEnemy(ply)
    local best, bestDist = nil, math.huge
    local pos = ply:GetPos()

    for _, v in ipairs(player.GetAll()) do
        if v ~= ply and v:Alive() and not v:IsDormant() and v:GetObserverMode() == OBS_MODE_NONE
            and not FR.Is(v) then
            local d = pos:DistToSqr(v:GetPos())
            if d < bestDist then best, bestDist = v, d end
        end
    end

    return best
end

local function DoAntiAim(cmd, ply)
    local aa = cfg.aa
    if not aa.enabled or gui.IsGameUIVisible() then return false end

    local mt = ply:GetMoveType()
    if mt == MOVETYPE_NOCLIP or mt == MOVETYPE_LADDER or mt == MOVETYPE_OBSERVER then return false end
    if ply:InVehicle() or ply:WaterLevel() > 1 then return false end

    if aa.offOnUse and cmd:KeyDown(IN_USE) then return false end

    -- On shot: the real view only goes out on the tick the gun really fires (it is ready and
    -- attack is down); every other tick - the trigger held between shots too - keeps the
    -- anti-aim angle, so the model only turns for that one tick. Without it, "real view while
    -- shooting" shows the real view for as long as attack is held.
    if cmd:KeyDown(IN_ATTACK) then
        if aa.onShot then
            if WeaponReady(ply) then return false end
        elseif aa.realOnShoot then
            return false
        end
    end

    if aa.offWithTools then
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and NO_AUTOFIRE[wep:GetClass()] then return false end
    end

    -- Desync (module): the others only ever see the last command of each packet, so the real
    -- view goes on the choked commands and the anti-aim angle only on the one that is sent.
    -- (The cl_cmdrate manager keeps at least one tick choked while this is on.)
    local willSend = BT.WillSend()
    if aa.desync and BT.NetReady() and not willSend then
        aaActive = true                -- still on for the indicator; the caller puts the real view back
        return false
    end

    local s = aa.sameForAll and aa.states.stand or aa.states[AAStateName(ply)]

    aaTick = aaTick + 1
    local interval = math.max(1, math.floor(s.modInterval))
    local flip = (math.floor(aaTick / interval) % 2) == 0
    local reroll = (aaTick % interval) == 0

    -- pitch
    local pitch = realAng.p
    local pm = s.pitchMode
    if pm == "down" then
        pitch = 89
    elseif pm == "up" then
        pitch = -89
    elseif pm == "zero" then
        pitch = 0
    elseif pm == "custom" then
        pitch = s.pitchValue
    elseif pm == "jitter" then
        pitch = flip and 89 or -89
    elseif pm == "random" then
        if reroll then aaRandPitch = math.Rand(-89, 89) end
        pitch = aaRandPitch
    end

    -- yaw base
    local base = realAng.y
    if s.yawBase == "static" then
        base = 0
    elseif s.yawBase == "target" then
        local t = NearestEnemy(ply)
        if t then base = (t:GetPos() - ply:GetPos()):Angle().y end
    end

    local yaw = base + s.yawOffset

    -- manual overrides (bind them with right-click)
    if aa.manualLeft then
        yaw = base + 90
    elseif aa.manualRight then
        yaw = base - 90
    elseif aa.manualBack then
        yaw = base + 180
    end

    -- yaw modifier
    local mod = s.yawMod
    if mod == "jitter" then
        yaw = yaw + (flip and s.modRange or -s.modRange)
    elseif mod == "random" then
        if reroll then aaRandYaw = math.Rand(-s.modRange, s.modRange) end
        yaw = yaw + aaRandYaw
    elseif mod == "spin" then
        aaSpin = (aaSpin + s.modSpeed * FrameTime()) % 360
        yaw = yaw + aaSpin
    elseif mod == "sway" then
        yaw = yaw + math.sin(CurTime() * math.rad(s.modSpeed)) * s.modRange
    elseif mod == "switch" then
        if not flip then yaw = base + s.switchOffset end
    end

    if s.noise > 0 then yaw = yaw + math.Rand(-s.noise, s.noise) end

    -- "LBY breaker": GMod has no lower body yaw, but each client turns a model's feet after its
    -- head with a lag; one sent command with the yaw thrown by lbyDelta now and then makes them
    -- turn away from where the head ends up. Only on commands that are really sent (with the
    -- module that is known; without it every command counts as sent).
    if aa.lby and willSend then
        local now = CurTime()
        if now >= (MV.lbyNext or 0) then
            MV.lbyNext = now + math.max(aa.lbyInterval, 0.1)
            yaw = yaw + aa.lbyDelta
        end
    end

    MV.aaYaw = math.NormalizeAngle(yaw)

    Inject(cmd, Angle(
        math.Clamp(pitch, -89, 89),
        math.NormalizeAngle(yaw),
        math.Clamp(s.roll, -50, 50)
    ))

    aaActive = true
    return true
end

-- cl_cmdrate manager: hide shots + fake lag. Lua can't hold packets back (no bSendPacket, and
-- net_fakelag needs sv_cheats); the one lever is cl_cmdrate, how often the client sends a
-- packet. Commands are made every frame and wait for the next packet, so a low rate sends
-- them in clumps: other players see the model jump from packet to packet, and since a model
-- shows the last command the server ran for it in a tick, it shows the last of the clump.
--  * hide shots: while firing, so the shot command is followed in its packet by anti-aim ones;
--  * fake lag: "choke" N = about N+1 ticks per packet, rate = tickrate / (N + 1), by mode.
-- The server clamps the rate to sv_mincmdrate / sv_maxcmdrate, and it only clumps when there
-- are more frames than packets. The original value is put back when neither wants it (and
-- on Unload); the item bag spam has its own cl_cmdrate use and wins while it runs.

-- item bag spam state; declared here because the Think hook below checks BAG.rate
-- (declared further down it was a nil global inside that hook)
local BAG = {flip = false, rate = nil, orig = nil}

do
    local orig, applied = nil, nil
    local jitterFlip, jitterNext = false, 0

    local function SetRate(rate)
        if rate == applied then return end

        if rate then
            if not applied then
                local cv = GetConVar("cl_cmdrate")
                orig = cv and cv:GetString() or nil
            end
            pcall(RunConsoleCommand, "cl_cmdrate", tostring(rate))
        elseif orig then
            pcall(RunConsoleCommand, "cl_cmdrate", orig)
            orig = nil
        end

        applied = rate
    end

    function MV.HideShotsRestore()
        SetRate(nil)
    end

    -- the choke fake lag wants right now (0 = none)
    local function FakeLagChoke(ply)
        local fl = cfg.aa
        if not fl.fakelag or not IsValid(ply) or not ply:Alive() then return 0 end

        local limit = math.Clamp(math.floor(fl.flChoke), 1, 14)
        local speed = ply:GetVelocity():Length2D()
        local mode = fl.flMode

        if mode == "air" then
            return ply:IsOnGround() and 0 or limit
        elseif mode == "moving" then
            return speed > 10 and limit or 0
        elseif mode == "adaptive" then
            -- about 64 units of movement per packet
            local perTick = speed * engine.TickInterval()
            if perTick < 0.5 then return 1 end
            return math.Clamp(math.ceil(64 / perTick) - 1, 1, limit)
        elseif mode == "jitter" then
            if CurTime() >= jitterNext then
                jitterFlip = not jitterFlip
                jitterNext = CurTime() + math.Rand(0.15, 0.45)
            end
            return jitterFlip and limit or 1
        end

        return limit
    end

    function MV.FakeLagStatus()
        if BT.NetReady() then
            local held, holdMax = nyxmod.Held()
            if held > 0 then return string.format("module: airstuck %d / %d ticks", held, holdMax) end
            return string.format("module: choked %d  (limit %d)", nyxmod.Choked(), MV.modChoke or 0)
        end

        if not applied then return "off (cl_cmdrate untouched)" end

        local tick = 1 / engine.TickInterval()
        return string.format("cl_cmdrate %d  (~%d ticks per packet)", applied, math.max(1, math.floor(tick / applied + 0.5)))
    end

    AddHook("Think", "cmdrate", function()
        local aa = cfg.aa
        local ply = LocalPlayer()
        local free = not IsValid(menu) and not gui.IsGameUIVisible()

        -- the item bag spam is using cl_cmdrate itself
        if BAG.rate then
            if applied then applied, orig = nil, nil end
            return
        end

        local shooting = input.IsMouseDown(MOUSE_LEFT) or (lastAimRage and CurTime() - lastAimTime < 0.1)
        local rate

        -- Module: the choke is real (CanPacket says no), so cl_cmdrate goes the other way - up to
        -- the tickrate while choking, because the engine only asks CanPacket on ticks the rate
        -- allows a packet at all.
        if BT.NetCheck() then
            local choke = 0
            if not (aa.flOffShooting and shooting) then choke = FakeLagChoke(ply) end
            if aa.enabled and aa.desync and choke < 1 then choke = 1 end

            MV.modChoke = choke
            nyxmod.SetChoke(choke)

            local wants = choke > 0 or cfg.move.airstuck
            SetRate(wants and math.floor(1 / engine.TickInterval() + 0.5) or nil)
            return
        end

        if aa.enabled and aa.hideShots and free and shooting then
            rate = math.floor(aa.hideRate)
        else
            local choke = 0
            if not (aa.flOffShooting and shooting) then choke = FakeLagChoke(ply) end

            if choke > 0 then
                local tick = 1 / engine.TickInterval()
                rate = math.max(1, math.floor(tick / (choke + 1)))
            end
        end

        SetRate(rate)
    end)
end

-- ---------------------------------------------------------------------------
-- real view recovery
--   While an injected angle sits in the engine view, how far the player turned this tick comes
--   from the mouse. Reading it back from the engine angle is exact until that angle is pinned at
--   +-89 pitch (anti-aim "down"/"up" does exactly that: looking down/up then got swallowed by the
--   engine's pitch clamp and the camera froze), so each axis uses the engine delta only when it
--   agrees with the raw mouse movement and falls back to the raw mouse otherwise.
-- ---------------------------------------------------------------------------

local cvMYaw   = GetConVar("m_yaw")
local cvMPitch = GetConVar("m_pitch")

-- Degrees one mouse count turns the view (negative: yaw drops as the mouse goes right).
-- CUserCmd mouse deltas are already multiplied by the in-game sensitivity (and zoom), so the
-- starting guess is m_yaw alone; it is then refined from ticks where the engine delta is
-- trustworthy. Multiplying by `sensitivity` again made high-sens setups turn far too fast.
local yawPerCount = nil

-- the engine delta is believed when it is small and matches the raw mouse movement
local function Plausible(engineDelta, rawDelta)
    return math.abs(engineDelta) <= 30 and math.abs(engineDelta - rawDelta) <= 0.3 + 0.6 * math.abs(rawDelta)
end

local function RecoverRealView(cmd, ply, cmdAng)
    if not silentDirty then
        -- nothing injected last tick: the engine view is the real view
        realAng = Angle(cmdAng.p, cmdAng.y, 0)
        return
    end

    local mYaw = math.abs(cvMYaw and cvMYaw:GetFloat() or 0.022)
    if mYaw == 0 then mYaw = 0.022 end
    local mPitch = cvMPitch and cvMPitch:GetFloat() or mYaw

    local defaultScale = -mYaw
    yawPerCount = yawPerCount or defaultScale

    local mx, my = cmd:GetMouseX(), cmd:GetMouseY()
    local dy = math.NormalizeAngle(cmdAng.y - sentAng.y)
    local dp = cmdAng.p - sentAng.p

    -- learn the real degrees-per-count from ticks with a clear, unclamped yaw movement
    if math.abs(mx) >= 3 and math.abs(dy) <= 30 then
        local s = dy / mx
        local ratio = s / defaultScale
        if ratio > 0.1 and ratio < 10 then
            yawPerCount = yawPerCount + (s - yawPerCount) * 0.1
        end
    end

    -- Source: yaw -= m_yaw * x, pitch += m_pitch * y (same count scale on both axes)
    local rawYaw = mx * yawPerCount
    local rawPitch = my * mPitch * (-yawPerCount / mYaw)

    local yawTurn = Plausible(dy, rawYaw) and dy or rawYaw

    -- near +-89 the engine clamps pitch, so only trust its delta away from the boundary
    local pitchTurn = rawPitch
    if math.abs(sentAng.p) < 80 and Plausible(dp, rawPitch) then pitchTurn = dp end

    realAng.p = math.Clamp(realAng.p + pitchTurn, -89, 89)
    realAng.y = math.NormalizeAngle(realAng.y + yawTurn)
end

-- ---------------------------------------------------------------------------
-- free camera: the body stays where it is (angle included), only the view flies
-- ---------------------------------------------------------------------------

-- what the last CalcView decided, for the RenderScene override below
local camZNear, camZFar = nil, nil
local camDrawViewer, camDrawViewModel = false, true

local freeActive = false
local freePos = Vector(0, 0, 0)
local freeAng = Angle(0, 0, 0)
local frozenAng = Angle(0, 0, 0)     -- the angle the body keeps while the camera is free

local function Sign(n)
    if n > 0 then return 1 end
    if n < 0 then return -1 end
    return 0
end

-- true while the free camera owns the tick: no aiming, anti-aim or body movement then
local function UpdateFreecam(cmd, ply)
    local f = cfg.free

    if not f.enabled or not ply:Alive() then
        freeActive = false
        return false
    end

    if not freeActive then
        freeActive = true
        freePos = ply:EyePos()
        freeAng = Angle(realAng.p, realAng.y, 0)
        frozenAng = Angle(realAng.p, realAng.y, 0)
    end

    -- what the mouse did to the (recovered) real view this tick moves the camera instead
    freeAng.p = math.Clamp(freeAng.p + (realAng.p - frozenAng.p), -89, 89)
    freeAng.y = math.NormalizeAngle(freeAng.y + math.NormalizeAngle(realAng.y - frozenAng.y))

    -- fly with the movement keys; jump = up, duck = down
    local dir = freeAng:Forward() * Sign(cmd:GetForwardMove()) + freeAng:Right() * Sign(cmd:GetSideMove())
    if cmd:KeyDown(IN_JUMP) then dir = dir + Vector(0, 0, 1) end
    if cmd:KeyDown(IN_DUCK) then dir = dir - Vector(0, 0, 1) end

    local speed = f.speed * (cmd:KeyDown(IN_SPEED) and f.boost or 1)
    freePos = freePos + dir * speed * FrameTime()

    -- the body does nothing
    cmd:SetForwardMove(0)
    cmd:SetSideMove(0)
    cmd:SetUpMove(0)
    cmd:RemoveKey(IN_JUMP)
    cmd:RemoveKey(IN_DUCK)

    -- the engine view stays on the frozen angle; next tick's mouse delta lands on top of it
    realAng = Angle(frozenAng.p, frozenAng.y, 0)
    cmd:SetViewAngles(frozenAng)
    sentAng = Angle(frozenAng.p, frozenAng.y, 0)
    silentDirty = true

    return true
end

local TrackShots   -- assigned in the tracer block further down

-- item bag spam ---------------------------------------------------------------
-- The use key is pressed on every tick the function is on (it is released on the tick between,
-- the server only reacts to a fresh press), at the nearest entity of the configured class.
-- Bind the check to "hold" (right-click it) to have it run while a key is held.
-- A press needs a command with the key up before it, so the most a single entity can be used
-- is every second command. One command is built per frame and the client sends them in packets
-- at cl_cmdrate; cl_cmdrate is changed only while the spam runs and put back afterwards (the
-- server clamps it to its own limits).
--
-- The two send modes pull in opposite directions:
--   rate  : cl_cmdrate up, so the presses are spread over as many server ticks as possible
--   burst : cl_cmdrate down, so the client chokes its commands and sends up to 15 of them in one
--           packet; the server runs the whole packet inside a single tick, i.e. several uses land
--           on the bag before the server has got round to removing it (entity removal is only
--           carried out when the frame ends). Whether that gives anything depends entirely on how
--           the server's bag code is written.
-- (BAG itself is declared above the cl_cmdrate manager, which reads BAG.rate)

-- value for cl_cmdrate (a string), or nil to put the original back. (fps_max is on GMod's blocked
-- list for RunConsoleCommand; every set goes through pcall so a refused command never throws.)
function BAG.SetRate(value)
    if value == BAG.rate then return end
    BAG.rate = value

    if value then
        if BAG.orig == nil then
            local cv = GetConVar("cl_cmdrate")
            if cv then BAG.orig = cv:GetString() end
        end

        pcall(RunConsoleCommand, "cl_cmdrate", value)
    elseif BAG.orig then
        pcall(RunConsoleCommand, "cl_cmdrate", BAG.orig)
        BAG.orig = nil
    end
end

-- one short line for the menu: what the current mode comes to
-- net mode ---------------------------------------------------------------------
-- gRust takes an interaction two ways: releasing the use key (KeyRelease hook, 0.2 s cooldown per
-- player through pl.NextInteract) and the net message gRust.Interact, whose server handler only
-- checks distance and line of sight - no cooldown. n copies sent in one frame go out in one
-- packet, so the server runs ent:Interact n times inside a single frame, before an entity that
-- removes itself is actually gone (Remove() is carried out when the frame ends). Whether that
-- duplicates anything depends on the bag's own Interact. The checks below copy the server's.
BAG.netLast = setmetatable({}, {__mode = "k"})     -- ent -> CurTime before which it is skipped
BAG.netStatus = "waiting for a bag in reach"

function BAG.CanInteract(ply, ent)
    if not IsValid(ent) or not ent.Interact then return false end
    if ent.GetInteractable and not ent:GetInteractable() then return false end
    if ent:GetPos():DistToSqr(ply:GetPos()) > 20000 then return false end

    local tr = util.TraceLine({start = ply:EyePos(), endpos = ent:LocalToWorld(ent:OBBCenter()), filter = ply})
    return tr.Entity == ent
end

function BAG.Burst(ent, n)
    for _ = 1, n do
        net.Start("gRust.Interact")
        net.WriteEntity(ent)
        net.SendToServer()
    end

    BAG.netStatus = string.format("sent %d x interact -> %s #%d", n, ent:GetClass(), ent:EntIndex())
end

-- one burst per frame at most, at the first bag of the class that passes the checks
function BAG.NetRun(ply)
    local b = cfg.bagspam
    local now = CurTime()

    for _, ent in ipairs(ents.FindByClass(b.class)) do
        if not ent:IsDormant() and now >= (BAG.netLast[ent] or 0) and BAG.CanInteract(ply, ent) then
            BAG.netLast[ent] = now + b.netWait
            BAG.Burst(ent, math.Clamp(math.floor(b.netCount), 1, 50))
            return
        end
    end
end

-- nyx_interact_burst [n]: one burst at whatever you are looking at, any class (for testing)
concommand.Add("nyx_interact_burst", function(ply, cmd, args)
    local me = LocalPlayer()
    if not IsValid(me) then return end

    local ent = me:GetEyeTrace().Entity
    if not BAG.CanInteract(me, ent) then
        print("[nyx] nothing interactable in reach under the crosshair")
        return
    end

    BAG.Burst(ent, math.Clamp(tonumber(args[1]) or math.floor(cfg.bagspam.netCount), 1, 50))
    print("[nyx] " .. BAG.netStatus)
end)

function BAG.Status()
    local b = cfg.bagspam
    if b.mode == "net" then return BAG.netStatus end

    local fps = 1 / math.max(FrameTime(), 0.001)

    if b.mode == "burst" then
        local per = math.Clamp(math.floor(fps / math.max(b.burstRate, 1)), 1, 15)
        return string.format("%d fps: ~%d uses per packet", fps, math.max(math.floor(per / 2), 1))
    end

    return string.format("%d fps: ~%d uses / s", fps, fps / 2)
end

function BAG.Run(cmd, ply)
    local b = cfg.bagspam
    if not b.enabled or gui.IsGameUIVisible() or IsValid(menu) then
        BAG.SetRate(nil)
        return false
    end

    -- net mode needs no use key, no angle and no cmdrate change
    if b.mode == "net" then
        BAG.SetRate(nil)
        BAG.NetRun(ply)
        return false
    end

    local eye = ply:GetShootPos()
    local best, bestPoint, bestDist = nil, nil, b.range * b.range

    for _, ent in ipairs(ents.FindByClass(b.class)) do
        if IsValid(ent) and not ent:IsDormant() then
            -- the game's use search measures to the nearest point of the entity
            local point = ent:NearestPoint(eye)
            local d = point:DistToSqr(eye)

            if d <= bestDist then best, bestPoint, bestDist = ent, point, d end
        end
    end

    if not best then
        BAG.SetRate(nil)
        return false
    end

    if b.mode == "burst" then
        BAG.SetRate(tostring(math.floor(b.burstRate)))
    elseif b.mode == "rate" then
        BAG.SetRate("128")
    else
        BAG.SetRate(nil)
    end

    if b.aim then
        Inject(cmd, AimAngleTo(ply, bestPoint, false, 0))
    end

    BAG.flip = not BAG.flip
    if BAG.flip then cmd:AddKey(IN_USE) else cmd:RemoveKey(IN_USE) end

    return b.aim
end

concommand.Add("nyx_bag_class", function(ply, cmd, args)
    if args[1] and args[1] ~= "" then
        cfg.bagspam.class = args[1]
        print("[nyx] item bag class: " .. args[1])
    else
        print("[nyx] item bag class: " .. cfg.bagspam.class .. "   (nyx_bag_class <class>)")
    end
end)

-- net logger -------------------------------------------------------------------
-- Every net message this client sends is written down: its name, each value written into it in
-- order (with the net.Write* function that wrote it), its size, reliable or not, and the Lua file
-- + line that called net.Start. That shows what a gamemode's menu really sends, e.g. when an item
-- is taken out of a bag. Incoming messages get the same from the other side: every net.Read* the
-- receiver does, with what it returned. Any sent record can be copied as a ready-to-run Lua
-- snippet or sent again value for value (replay), from the log window (nyx_net_menu) or console.
-- The net functions are only wrapped while the logger is on. Lua Write* / Read* functions that
-- call other ones inside (WriteTable, WriteEntity, WriteType) are recorded once, at the outermost
-- call, so a replay calls the same function. Code that cached a function at load time
-- (local Start = net.Start) goes around the wrapper.
-- Lives in BAG.Log: the main chunk is at Lua's limit of 200 locals.
BAG.Log = {list = {}, count = 0, nOut = 0, nIn = 0}

-- a function of its own, not a bare do block: its locals would count against the main chunk's 200
do
local function Build()
    local NETLOG = BAG.Log
    local MAX = 2000
    local orig = nil           -- name -> original net function, while wrapped
    local cur = nil            -- outgoing message being built
    local curIn = nil          -- incoming message whose receiver is running: its reads are recorded
    local replayOf = nil       -- id of the record being sent again right now
    local depth = 0            -- > 0 while inside a wrapped Write* / Read* (nested calls are skipped)
    local ignore = {}          -- lower-case names that are not recorded
    local nextId = 1
    local W = {lastId = 0, MAX = 1000, nextRefresh = 0}    -- log window

    -- value formatting --------------------------------------------------------------

    local function Num(v)
        if v ~= v then return "(0/0)" end
        if v == math.huge then return "math.huge" end
        if v == -math.huge then return "-math.huge" end

        local s = tostring(v)
        if tonumber(s) == v then return s end
        return string.format("%.17g", v)        -- tostring keeps only 14 digits
    end

    -- a Lua string literal; binary escapes bytes >= 127 too (net.WriteData payloads)
    local function Str(s, binary)
        local pat = binary and "[%z\1-\31\"\\\127-\255]" or "[%z\1-\31\"\\\127]"

        return '"' .. (string.gsub(s, pat, function(c)
            if c == '"' then return '\\"' end
            if c == "\\" then return "\\\\" end
            if c == "\n" then return "\\n" end
            if c == "\t" then return "\\t" end
            return string.format("\\%03d", string.byte(c))
        end)) .. '"'
    end

    local function EntLabel(v)
        if v == game.GetWorld() then return "world" end
        if not IsValid(v) then return "NULL" end
        if v:IsPlayer() then return string.format("player '%s' #%d", v:Nick(), v:EntIndex()) end
        return string.format("%s #%d", v:GetClass(), v:EntIndex())
    end

    -- v as Lua source that evaluates to the same value (as far as the client can rebuild it)
    local function Lit(v, bin, d)
        d = d or 0

        if isstring(v) then return Str(v, bin) end
        if isnumber(v) then return Num(v) end
        if isbool(v) or v == nil then return tostring(v) end
        if isvector(v) then return string.format("Vector(%s, %s, %s)", Num(v.x), Num(v.y), Num(v.z)) end
        if isangle(v) then return string.format("Angle(%s, %s, %s)", Num(v.p), Num(v.y), Num(v.r)) end
        if IsColor(v) then return string.format("Color(%d, %d, %d, %d)", v.r, v.g, v.b, v.a) end

        if IsEntity(v) then
            if v == game.GetWorld() then return "game.GetWorld()" end
            if not IsValid(v) then return "NULL" end
            return string.format("Entity(%d) --[[ %s ]]", v:EntIndex(), EntLabel(v))
        end

        if ismatrix(v) then return "Matrix(" .. Lit(v:ToTable(), bin, d + 1) .. ")" end

        if istable(v) then
            if d > 8 then return "{ --[[ too deep ]] }" end

            local parts, n = {}, #v
            for i = 1, n do parts[#parts + 1] = Lit(v[i], bin, d + 1) end

            for k, val in pairs(v) do
                if not (isnumber(k) and k >= 1 and k <= n and k == math.floor(k)) then
                    local key = (isstring(k) and string.match(k, "^[%a_][%w_]*$")) and k or ("[" .. Lit(k, bin, d + 1) .. "]")
                    parts[#parts + 1] = key .. " = " .. Lit(val, bin, d + 1)
                end
            end

            return "{" .. table.concat(parts, ", ") .. "}"
        end

        return "nil --[[ " .. type(v) .. " ]]"
    end

    -- short form for log lines
    local function Fmt(fn, v)
        if isstring(v) then
            if fn == "Data" then
                local hex = {}
                for i = 1, math.min(#v, 24) do hex[i] = string.format("%02X", string.byte(v, i)) end
                return string.format("<%d bytes> %s%s", #v, table.concat(hex, " "), #v > 24 and " ..." or "")
            end

            local s = Str(string.sub(v, 1, 80))
            return #v > 80 and (s .. "..(" .. #v .. ")") or s
        end

        if IsEntity(v) then return EntLabel(v) end

        if istable(v) and not IsColor(v) then
            local json = util.TableToJSON(v) or "{?}"
            return #json > 120 and (string.sub(json, 1, 120) .. "...") or json
        end

        if isvector(v) then return string.format("[%.1f %.1f %.1f]", v.x, v.y, v.z) end
        if isangle(v) then return string.format("{%.1f %.1f %.1f}", v.p, v.y, v.r) end
        return Lit(v)
    end

    -- recorded values are copies: vectors, angles and tables are mutable and get reused
    local function Snap(v)
        if isvector(v) then return Vector(v) end
        if isangle(v) then return Angle(v) end
        if ismatrix(v) then return Matrix(v:ToTable()) end
        if istable(v) then return table.Copy(v) end
        return v
    end

    function NETLOG.Summary(m, maxLen)
        local parts = {}
        for i, a in ipairs(m.args) do
            local vals = {}
            for j = 1, a.v.n do vals[j] = Fmt(a.fn, a.v[j]) end
            parts[i] = a.fn .. "(" .. table.concat(vals, ", ") .. ")" .. (a.read and ("=" .. Fmt(a.fn, a.ret)) or "")
        end

        local s = table.concat(parts, " | ")
        return (maxLen and #s > maxLen) and (string.sub(s, 1, maxLen) .. "...") or s
    end

    function NETLOG.Format(m)
        if m.dir == "mark" then return string.format("%8.2f  ---------------- marker %d ----------------", m.time, m.n) end

        local sum = NETLOG.Summary(m)
        return string.format("#%-5d %8.2f  %s %s  (%d B)%s%s", m.id or 0, m.time, m.dir == "in" and "<-" or "->",
            m.name, m.bytes or 0, sum ~= "" and ("  " .. sum) or "", m.src and ("   @ " .. m.src) or "")
    end

    -- sent: a snippet that sends the same message again; received: the receiver's reads, in order
    function NETLOG.ToLua(m)
        if m.dir == "mark" then return "" end
        local out = {}

        if m.dir == "out" then
            out[1] = string.format("net.Start(%s%s)", Str(m.name), m.unreliable and ", true" or "")

            for _, a in ipairs(m.args) do
                local vals = {}
                for i = 1, a.v.n do vals[i] = Lit(a.v[i], a.fn == "Data") end
                out[#out + 1] = string.format("net.Write%s(%s)", a.fn, table.concat(vals, ", "))
            end

            out[#out + 1] = "net.SendToServer()"
        else
            out[1] = string.format("-- net.Receive(%s, function(len) ...  reads, in order:", Str(m.name))

            for _, a in ipairs(m.args) do
                local vals = {}
                for i = 1, a.v.n do vals[i] = Lit(a.v[i]) end
                out[#out + 1] = string.format("net.Read%s(%s)  --> %s", a.fn, table.concat(vals, ", "), Lit(a.ret, a.fn == "Data"))
            end

            if #m.args == 0 then
                out[#out + 1] = m.handled and "-- (no reads seen: it reads nothing, or uses net.Read* cached as locals)"
                    or "-- (no receiver on the client for this one)"
            end
        end

        return table.concat(out, "\n")
    end

    function NETLOG.Detail(m)
        if m.dir == "mark" then return NETLOG.Format(m) end

        return string.format("#%d  %s %s   %d bytes%s   t = %.2f\n%s\n%s", m.id, m.dir == "in" and "<-" or "->",
            m.name, m.bytes or 0, m.dir == "out" and (m.unreliable and ", unreliable" or ", reliable") or "",
            m.time, m.src and ("from  " .. m.src .. "\n") or "", NETLOG.ToLua(m))
    end

    -- recording ---------------------------------------------------------------------

    local function Push(m)
        m.id = nextId
        nextId = nextId + 1

        local list = NETLOG.list
        list[#list + 1] = m
        if #list > MAX then table.remove(list, 1) end

        NETLOG.count = NETLOG.count + 1
        if m.dir == "out" then NETLOG.nOut = NETLOG.nOut + 1 elseif m.dir == "in" then NETLOG.nIn = NETLOG.nIn + 1 end

        if cfg.netlog.print then
            local col = m.dir == "in" and Color(90, 200, 255) or (m.dir == "mark" and Color(255, 220, 60) or Color(149, 184, 6))
            MsgC(col, "[nyx net] ", Color(225, 225, 225), NETLOG.Format(m), "\n")
        end
    end

    function NETLOG.Find(id)
        local list = NETLOG.list
        for i = #list, 1, -1 do
            if list[i].id == id then return list[i] end
        end
    end

    local function Wrap()
        if orig then return end
        orig = {}

        for name, fn in pairs(net) do
            if isfunction(fn) and (name == "Start" or name == "SendToServer" or name == "Incoming"
                or string.sub(name, 1, 5) == "Write" or string.sub(name, 1, 4) == "Read") then
                orig[name] = fn
            end
        end

        for name, fn in pairs(orig) do
            if string.sub(name, 1, 5) == "Write" then
                local short = string.sub(name, 6)

                net[name] = function(...)
                    if cur and depth == 0 then
                        local v = {n = select("#", ...), ...}
                        for i = 1, v.n do v[i] = Snap(v[i]) end
                        cur.args[#cur.args + 1] = {fn = short, v = v}
                    end

                    depth = depth + 1
                    local ok, a, b = pcall(fn, ...)
                    depth = depth - 1

                    if not ok then error(a, 2) end
                    return a, b
                end
            elseif string.sub(name, 1, 4) == "Read" and name ~= "ReadHeader" then
                local short = string.sub(name, 5)

                net[name] = function(...)
                    local rec = curIn
                    if not rec or depth > 0 then return fn(...) end

                    depth = depth + 1
                    local ok, a, b, c = pcall(fn, ...)
                    depth = depth - 1

                    if not ok then error(a, 2) end
                    rec.args[#rec.args + 1] = {fn = short, v = {n = select("#", ...), ...}, ret = Snap(a), read = true}
                    return a, b, c
                end
            end
        end

        net.Start = function(name, unreliable, ...)
            cur = nil
            local r = orig.Start(name, unreliable, ...)     -- an unpooled name errors here, nothing recorded

            if isstring(name) and not ignore[string.lower(name)] then
                local src
                if replayOf then
                    src = "replay of #" .. replayOf
                else
                    local info = debug.getinfo(2, "Sl")
                    src = info and (info.short_src .. ":" .. (info.currentline or 0)) or "?"
                end

                cur = {dir = "out", name = name, unreliable = unreliable and true or false,
                       args = {}, time = CurTime(), src = src}
            end

            return r
        end

        net.SendToServer = function(...)
            local c = cur
            cur = nil

            if c then
                c.bytes = net.BytesWritten and net.BytesWritten() or 0
                Push(c)
            end

            return orig.SendToServer(...)
        end

        -- same as GMod's own net.Incoming, plus the record; the header can only be read once,
        -- so the original can't be called after peeking at it
        if orig.Incoming then
            net.Incoming = function(len, client)
                if not cfg.netlog.incoming then return orig.Incoming(len, client) end

                local name = util.NetworkIDToString(net.ReadHeader())
                if not name then return end

                local func = net.Receivers[string.lower(name)]
                local rec

                if not ignore[string.lower(name)] then
                    rec = {dir = "in", name = name, args = {}, time = CurTime(),
                           bytes = math.floor((len - 16) / 8), handled = func ~= nil}
                end

                if not func then
                    if rec then Push(rec) end
                    return
                end

                curIn = rec
                local ok, err = pcall(func, len - 16, client)
                curIn = nil

                if rec then Push(rec) end
                if not ok then ErrorNoHalt("[nyx net] receiver of " .. name .. " errored: " .. tostring(err) .. "\n") end
            end
        end
    end

    function NETLOG.Restore()
        if not orig then return end

        for name, fn in pairs(orig) do net[name] = fn end
        orig, cur, curIn, depth = nil, nil, nil, 0
    end

    AddHook("Think", "netlog", function()
        if cfg.netlog.enabled then Wrap() else NETLOG.Restore() end

        if RealTime() >= W.nextRefresh then
            W.nextRefresh = RealTime() + 0.2
            NETLOG.RefreshWindow()
        end
    end)

    -- sends a recorded outgoing message again, value for value (works with the logger off too)
    function NETLOG.Replay(m, times)
        if not m then return false, "no such record" end
        if m.dir ~= "out" then return false, "only sent messages can be replayed" end

        times = math.Clamp(math.floor(times or 1), 1, 100)
        replayOf = m.id

        local ok, err = pcall(function()
            for _ = 1, times do
                net.Start(m.name, m.unreliable)
                for _, a in ipairs(m.args) do
                    net["Write" .. a.fn](unpack(a.v, 1, a.v.n))
                end
                net.SendToServer()
            end
        end)

        replayOf = nil
        local msg = ok and string.format("sent %s x%d", m.name, times) or tostring(err)
        print("[nyx net] replay #" .. m.id .. ": " .. msg)
        return ok, msg
    end

    -- the newest sent message that isn't itself a replay
    function NETLOG.ReplayLast()
        local list = NETLOG.list
        for i = #list, 1, -1 do
            local m = list[i]
            if m.dir == "out" and not string.find(m.src or "", "^replay") then return NETLOG.Replay(m, 1) end
        end
        print("[nyx net] nothing sent yet")
    end

    function NETLOG.Mark()
        NETLOG.marks = (NETLOG.marks or 0) + 1
        Push({dir = "mark", n = NETLOG.marks, time = CurTime(), args = {}})
    end

    function NETLOG.Dump(n)
        local list = NETLOG.list
        n = math.min(n or 40, #list)

        print(string.format("[nyx net] last %d of %d:", n, NETLOG.count))
        for i = #list - n + 1, #list do print(NETLOG.Format(list[i])) end
    end

    function NETLOG.Clear()
        NETLOG.list = {}
        NETLOG.count, NETLOG.nOut, NETLOG.nIn = 0, 0, 0
        W.dirtyAll = true
        if W.Select then W.Select(nil) end
    end

    -- every record, and under each one its Lua form
    function NETLOG.Save()
        local out = {}
        for _, m in ipairs(NETLOG.list) do
            out[#out + 1] = NETLOG.Format(m)
            if m.dir ~= "mark" then out[#out + 1] = "    " .. string.gsub(NETLOG.ToLua(m), "\n", "\n    ") end
        end

        file.CreateDir("nyx")
        file.Write("nyx/netlog.txt", table.concat(out, "\n"))
        print("[nyx net] saved " .. #NETLOG.list .. " records to data/nyx/netlog.txt")
    end

    function NETLOG.ToggleIgnore(name)
        local k = string.lower(name)
        ignore[k] = not ignore[k] or nil
        print("[nyx net] " .. name .. (ignore[k] and " ignored" or " logged again"))
    end

    -- the name of the newest message that isn't a marker goes on the ignore list
    function NETLOG.IgnoreLast()
        for i = #NETLOG.list, 1, -1 do
            local m = NETLOG.list[i]
            if m.dir ~= "mark" then
                ignore[string.lower(m.name)] = true
                print("[nyx net] ignoring " .. m.name)
                return
            end
        end
    end

    function NETLOG.Status()
        local last = NETLOG.list[#NETLOG.list]
        local ign = table.Count(ignore)
        return string.format("%d out / %d in%s%s", NETLOG.nOut, NETLOG.nIn,
            ign > 0 and (" | " .. ign .. " ignored") or "",
            (last and last.dir ~= "mark") and (" | last: " .. string.sub(last.name, 1, 18)) or "")
    end

    -- log window ---------------------------------------------------------------------
    -- A Derma frame of its own (the skeet menu is for settings): the list on top, the selected
    -- record below with its Lua form, replay / copy / ignore buttons. Opens with nyx_net_menu or
    -- the button in Misc > Net logger.

    local COL = {
        bg = Color(17, 17, 17), panel = Color(24, 24, 24), line = Color(45, 45, 45),
        text = Color(220, 220, 220), dim = Color(140, 140, 140), accent = Color(149, 184, 6),
        incoming = Color(90, 200, 255), mark = Color(255, 220, 60), sel = Color(40, 48, 20),
    }

    local function Match(m, filter)
        if m.dir == "mark" then return true end
        if m.dir == "in" and W.hideIn then return false end
        return filter == "" or string.find(string.lower(m.name), filter, 1, true) ~= nil
    end

    local function AddRow(m)
        local line = W.list:AddLine(m.id, string.format("%.2f", m.time),
            m.dir == "in" and "<-" or (m.dir == "out" and "->" or "--"),
            m.dir == "mark" and ("marker " .. m.n) or m.name,
            m.bytes or "", m.dir == "mark" and "" or NETLOG.Summary(m, 140), m.src or "")
        line.rec = m

        local col = m.dir == "in" and COL.incoming or (m.dir == "mark" and COL.mark or COL.text)
        for _, c in pairs(line.Columns) do c:SetTextColor(col) end

        line.Paint = function(s, w, h)
            if s:IsLineSelected() then
                surface.SetDrawColor(COL.sel)
                surface.DrawRect(0, 0, w, h)
            elseif s:IsHovered() then
                surface.SetDrawColor(30, 30, 30)
                surface.DrawRect(0, 0, w, h)
            end
        end
    end

    -- rows for records newer than the last one shown; the whole list again when the filter changed
    function NETLOG.RefreshWindow()
        local f = W.frame
        if not IsValid(f) or not f:IsVisible() then return end

        local lv = W.list
        local bar = lv.VBar
        local atBottom = not bar.Enabled or bar:GetScroll() >= bar.CanvasSize - 4

        local filter = string.lower(W.filter:GetValue() or "")
        local list = NETLOG.list
        local add = {}

        if W.dirtyAll or #lv:GetLines() > W.MAX * 1.5 then
            lv:Clear()
            for i = #list, 1, -1 do
                if Match(list[i], filter) then
                    add[#add + 1] = list[i]
                    if #add >= W.MAX then break end
                end
            end
            W.dirtyAll = false
        else
            for i = #list, 1, -1 do
                if list[i].id <= W.lastId then break end
                if Match(list[i], filter) then add[#add + 1] = list[i] end
            end
        end

        for i = #add, 1, -1 do AddRow(add[i]) end
        if list[#list] then W.lastId = list[#list].id end

        if #add > 0 and atBottom then
            lv:InvalidateLayout(true)
            bar:SetScroll(bar.CanvasSize)
        end

        W.status:SetText(string.format("%s   |   %s%s",
            cfg.netlog.enabled and "logging" or "logger OFF (Misc > Net logger)", NETLOG.Status(),
            W.msg and ("   |   " .. W.msg) or ""))
    end

    local function Check(parent, text, get, set)
        local c = vgui.Create("DCheckBoxLabel", parent)
        c:Dock(LEFT)
        c:DockMargin(10, 5, 0, 0)
        c:SetText(text)
        c:SetTextColor(COL.text)
        c:SetValue(get())
        c:SizeToContents()
        c.OnChange = function(_, v) set(v) end
        return c
    end

    local function Button(parent, text, dock, fn)
        local b = vgui.Create("DButton", parent)
        b:Dock(dock)
        b:DockMargin(4, 0, 0, 0)
        b:SetText(text)
        b:SetTextColor(COL.text)
        b:SizeToContentsX(18)
        b.DoClick = fn
        b.Paint = function(s, w, h)
            surface.SetDrawColor(s:IsHovered() and Color(38, 38, 38) or COL.panel)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(COL.line)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
        return b
    end

    -- dark background + text drawn by the entry itself
    local function DarkEntry(e)
        e.Paint = function(s, w, h)
            surface.SetDrawColor(COL.panel)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(COL.line)
            surface.DrawOutlinedRect(0, 0, w, h)
            s:DrawTextEntryText(COL.text, COL.accent, COL.text)
        end
    end

    function W.Select(m)
        W.sel = m
        if IsValid(W.detail) then W.detail:SetText(m and NETLOG.Detail(m) or "") end
    end

    local function Selected(sent)
        local m = W.sel
        if not m or m.dir == "mark" then W.msg = "select a record first" return end
        if sent and m.dir ~= "out" then W.msg = "only sent messages can be replayed" return end
        return m
    end

    local function CopyLua(m)
        SetClipboardText(NETLOG.ToLua(m))
        W.msg = "copied #" .. m.id .. " as Lua"
    end

    function NETLOG.OpenWindow()
        if IsValid(W.frame) then
            W.frame:SetVisible(true)
            W.frame:MakePopup()
            W.dirtyAll = true
            return
        end

        local f = vgui.Create("DFrame")
        f:SetSize(math.min(ScrW() - 40, 1100), math.min(ScrH() - 40, 680))
        f:Center()
        f:SetTitle("nyx  -  net log")
        f:SetSizable(true)
        f:SetDeleteOnClose(false)
        f:MakePopup()
        f.Paint = function(_, w, h)
            surface.SetDrawColor(COL.bg)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(COL.accent)
            surface.DrawRect(0, 0, w, 2)
            surface.SetDrawColor(COL.line)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
        W.frame = f

        -- top bar: filter, toggles, list actions
        local top = vgui.Create("DPanel", f)
        top:Dock(TOP)
        top:SetTall(26)
        top:SetPaintBackground(false)

        W.filter = vgui.Create("DTextEntry", top)
        W.filter:Dock(LEFT)
        W.filter:SetWide(220)
        W.filter:SetPlaceholderText("filter by name")
        W.filter.OnChange = function() W.dirtyAll = true end
        DarkEntry(W.filter)

        local nl = cfg.netlog
        Check(top, "Logging", function() return nl.enabled end, function(v) nl.enabled = v end)
        Check(top, "Record incoming", function() return nl.incoming end, function(v) nl.incoming = v end)
        Check(top, "Hide incoming", function() return W.hideIn or false end, function(v) W.hideIn = v; W.dirtyAll = true end)
        Check(top, "Console", function() return nl.print end, function(v) nl.print = v end)

        Button(top, "Save", RIGHT, NETLOG.Save)
        Button(top, "Clear", RIGHT, NETLOG.Clear)
        Button(top, "Marker", RIGHT, NETLOG.Mark)

        W.status = vgui.Create("DLabel", f)
        W.status:Dock(BOTTOM)
        W.status:SetTall(18)
        W.status:SetTextColor(COL.dim)

        -- list on top, the selected record below
        local lv = vgui.Create("DListView")
        lv:SetMultiSelect(false)
        lv:SetHeaderHeight(18)
        lv.Paint = function(_, w, h)
            surface.SetDrawColor(COL.panel)
            surface.DrawRect(0, 0, w, h)
        end

        local cols = {{"#", 48, true}, {"time", 64, true}, {"", 22, true}, {"name", 200},
                      {"bytes", 44, true}, {"values", 460}, {"source", 220}}
        for _, c in ipairs(cols) do
            local col = lv:AddColumn(c[1])
            if c[3] then col:SetFixedWidth(c[2]) else col:SetWidth(c[2]) end
            col.Header:SetTextColor(COL.dim)
            col.Header.Paint = function(_, w, h)
                surface.SetDrawColor(30, 30, 30)
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(COL.line)
                surface.DrawRect(w - 1, 0, 1, h)
            end
        end

        lv.OnRowSelected = function(_, _, line) W.Select(line.rec) end
        lv.DoDoubleClick = function(_, _, line)
            if line.rec.dir ~= "mark" then CopyLua(line.rec) end
        end
        lv.OnRowRightClick = function(_, _, line)
            local m = line.rec
            if m.dir == "mark" then return end

            local dm = DermaMenu()
            dm:AddOption("Copy as Lua", function() CopyLua(m) end)
            dm:AddOption("Copy name", function() SetClipboardText(m.name) end)
            dm:AddOption((ignore[string.lower(m.name)] and "Stop ignoring " or "Ignore ") .. m.name,
                function() NETLOG.ToggleIgnore(m.name) end)
            if m.dir == "out" then
                dm:AddOption("Replay", function() local _, msg = NETLOG.Replay(m, 1); W.msg = msg end)
            end
            dm:Open()
        end
        W.list = lv

        local bottom = vgui.Create("DPanel")
        bottom:SetPaintBackground(false)

        local actions = vgui.Create("DPanel", bottom)
        actions:Dock(TOP)
        actions:SetTall(24)
        actions:DockMargin(0, 4, 0, 4)
        actions:SetPaintBackground(false)

        local times = vgui.Create("DNumberWang", actions)
        times:Dock(LEFT)
        times:SetWide(48)
        times:SetMinMax(1, 100)
        times:SetValue(1)

        Button(actions, "Replay", LEFT, function()
            local m = Selected(true)
            if m then local _, msg = NETLOG.Replay(m, times:GetValue()); W.msg = msg end
        end)
        Button(actions, "Copy as Lua", LEFT, function()
            local m = Selected()
            if m then CopyLua(m) end
        end)
        Button(actions, "Ignore name", LEFT, function()
            local m = Selected()
            if m then NETLOG.ToggleIgnore(m.name) end
        end)

        W.detail = vgui.Create("DTextEntry", bottom)
        W.detail:Dock(FILL)
        W.detail:SetMultiline(true)
        W.detail:SetVerticalScrollbarEnabled(true)
        W.detail:SetFont("BudgetLabel")
        DarkEntry(W.detail)

        local div = vgui.Create("DVerticalDivider", f)
        div:Dock(FILL)
        div:SetTop(lv)
        div:SetBottom(bottom)
        div:SetTopHeight(f:GetTall() * 0.55)
        div:SetDividerHeight(6)

        W.dirtyAll = true
        NETLOG.RefreshWindow()
    end

    function NETLOG.ToggleWindow()
        if IsValid(W.frame) and W.frame:IsVisible() then W.frame:Close() else NETLOG.OpenWindow() end
    end

    function NETLOG.CloseWindow()
        if IsValid(W.frame) then W.frame:Remove() end
    end

    concommand.Add("nyx_net_menu", NETLOG.ToggleWindow)
    concommand.Add("nyx_net_dump", function(ply, cmd, args) NETLOG.Dump(tonumber(args[1])) end)
    concommand.Add("nyx_net_clear", function() NETLOG.Clear() end)
    concommand.Add("nyx_net_save", function() NETLOG.Save() end)
    concommand.Add("nyx_net_mark", function() NETLOG.Mark() end)

    -- nyx_net_replay <id> [times]: the id is the # in the log
    concommand.Add("nyx_net_replay", function(ply, cmd, args)
        local m = NETLOG.Find(tonumber(args[1] or ""))
        if not m then print("[nyx net] no record #" .. tostring(args[1])) return end
        NETLOG.Replay(m, tonumber(args[2]))
    end)

    -- nyx_net_lua <id>: prints the record as Lua and copies it
    concommand.Add("nyx_net_lua", function(ply, cmd, args)
        local m = NETLOG.Find(tonumber(args[1] or ""))
        if not m then print("[nyx net] no record #" .. tostring(args[1])) return end
        print(NETLOG.ToLua(m))
        SetClipboardText(NETLOG.ToLua(m))
    end)

    -- nyx_net_ignore <name>: toggles a name on the ignore list; no name lists it
    concommand.Add("nyx_net_ignore", function(ply, cmd, args)
        local name = args[1]

        if not name or name == "" then
            print("[nyx net] ignored: " .. table.concat(table.GetKeys(ignore), ", "))
            return
        end

        NETLOG.ToggleIgnore(name)
    end)
end
Build()
end

-- lua dump ---------------------------------------------------------------------
-- Copies the source of client Lua files the server sent (gamemode, addons) into data/nyx/dump/,
-- to read them outside the game. The path can be given the way debug info prints it
-- (gamemodes/rust/gamemode/x.lua) or relative to lua/ (rust/gamemode/x.lua); several search
-- paths are tried, since the files can come from the server's download or a local copy.
--   nyx_dump_lua <file>          one file
--   nyx_dump_lua_dir <folder>    every .lua under the folder, recursively
do
    local OUT = "nyx/dump"

    -- relative path variants x search paths, in the order they are tried
    local function Candidates(path)
        path = string.gsub(string.gsub(string.Trim(path or ""), "\"", ""), "\\", "/")
        local rel = string.gsub(path, "^gamemodes/", "")
        rel = string.gsub(rel, "^lua/", "")

        return {
            {rel, "LUA"}, {rel, "lsv"}, {rel, "lcl"},
            {"gamemodes/" .. rel, "GAME"}, {"lua/" .. rel, "GAME"}, {path, "GAME"},
        }
    end

    -- source text and the search path it came from, or nil
    local function ReadLua(path)
        for _, c in ipairs(Candidates(path)) do
            local ok, src = pcall(file.Read, c[1], c[2])
            if ok and isstring(src) and #src > 0 then return src, c[2] .. ":" .. c[1] end
        end
    end

    -- data/ only accepts a few extensions, so every dump is a flat .txt
    local function Save(path, src)
        local name = string.gsub(string.gsub(path, "^gamemodes/", ""), "[^%w_%-%.]", "_")
        name = string.gsub(name, "%.lua$", "") .. ".txt"

        file.CreateDir("nyx")
        file.CreateDir(OUT)
        file.Write(OUT .. "/" .. name, src)

        return "data/" .. OUT .. "/" .. name
    end

    concommand.Add("nyx_dump_lua", function(ply, cmd, args, argStr)
        local path = string.Trim(argStr or "")
        if path == "" then print("usage: nyx_dump_lua <path to a .lua file>") return end

        local src, from = ReadLua(path)
        if not src then
            print("[nyx dump] not readable: " .. path .. "  (tried LUA, lsv, lcl, GAME)")
            return
        end

        print(string.format("[nyx dump] %s  (%d bytes, %s) -> %s", path, #src, from, Save(path, src)))
    end)

    -- every .lua under dir, found through the first search path that lists anything
    concommand.Add("nyx_dump_lua_dir", function(ply, cmd, args, argStr)
        local dir = string.gsub(string.Trim(argStr or ""), "/+$", "")
        if dir == "" then print("usage: nyx_dump_lua_dir <folder>") return end

        local saved, failed = 0, 0

        for _, c in ipairs(Candidates(dir .. "/x")) do
            local base = string.gsub(c[1], "/x$", "")
            local found = false

            local function Walk(d, depth)
                if depth > 12 then return end

                local files, dirs = file.Find(d .. "/*", c[2])

                for _, f in ipairs(files or {}) do
                    if string.sub(f, -4) == ".lua" then
                        found = true

                        local ok, src = pcall(file.Read, d .. "/" .. f, c[2])
                        if ok and isstring(src) and #src > 0 then
                            Save(d .. "/" .. f, src)
                            saved = saved + 1
                        else
                            failed = failed + 1
                        end
                    end
                end

                for _, sub in ipairs(dirs or {}) do Walk(d .. "/" .. sub, depth + 1) end
            end

            Walk(base, 0)

            if found then
                print(string.format("[nyx dump] %s via %s: %d saved, %d unreadable -> data/%s/",
                    base, c[2], saved, failed, OUT))
                return
            end
        end

        print("[nyx dump] nothing found under " .. dir)
    end)
end

local function MainMove(cmd)
    if cmd:CommandNumber() == 0 then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local cmdAng = cmd:GetViewAngles()
    RecoverRealView(cmd, ply, cmdAng)

    -- module: CUserCmd layout check (before anything has changed the command)
    BT.ProbeCmd(cmd)

    -- Airstuck (module): every command is held back, so the server gets nothing to simulate you
    -- with and leaves you hanging where you are; after asMax seconds it lets go (the last 15
    -- commands go out and you carry on) until the key is pressed again. Movement is zeroed so
    -- your own prediction doesn't wander off meanwhile.
    if BT.NetReady() then
        local stuck = cfg.move.airstuck and ply:Alive()
        if stuck ~= BT.M.stuck then
            nyxmod.SetHold(stuck, math.floor(math.Clamp(cfg.move.asMax, 0.2, 20) / engine.TickInterval()))
            BT.M.stuck = stuck
        end

        if stuck then
            cmd:SetForwardMove(0)
            cmd:SetSideMove(0)
            cmd:SetUpMove(0)
        end
    end

    -- angle the previous tick's shot went out on (sentAng is still last tick's here)
    if TrackShots then TrackShots(ply, (silentDirty and sentAng or cmdAng):Forward()) end


    aaActive = false

    if not ply:Alive() then
        freeActive = false
        Restore(cmd)
        return
    end

    if UpdateFreecam(cmd, ply) then return end

    DoMovement(cmd, ply)
    MV.Run(cmd, ply)            -- after bhop / strafes: it may put jump back and zero the strafe

    -- picking the bag up comes first: it sets its own angle and presses use
    if BAG.Run(cmd, ply) then return end

    -- priority: rage shot > legit aimbot > anti-aim > real view
    if DoRage(cmd, ply) or DoAim(cmd, ply) then return end

    -- your own shot with no aimbot: just the spread taken out of it
    if NS.Manual(cmd, ply, Inject) then return end

    if DoAntiAim(cmd, ply) then return end

    Restore(cmd)
end

-- true while a taunt is playing and the view is first person: the gamemode would then swing the
-- camera out to look at the model, which "hide taunts in first person" prevents
local function HideTaunt(ply)
    return cfg.taunt.hideFirst and IsValid(ply) and ply:IsPlayingTaunt()
        and not cfg.view.thirdperson and not freeActive
end

AddHook("CreateMove", "main", function(cmd)
    local ply = LocalPlayer()

    -- positions are written down before the aimbots look at them
    if IsValid(ply) then
        BT.Record(ply)
        if cfg.aim.extrapOn or cfg.rage.extrapOn then BT.X.Record(ply) end
    end

    MainMove(cmd)

    -- While a taunt plays, the gamemode's own CreateMove (the taunt camera) clears all movement
    -- and pins the view. A hook returning a value stops the gamemode function from running at
    -- all, so returning true here is what lets you keep walking and aiming during taunts.
    if IsValid(ply) and ply:IsPlayingTaunt()
        and ((cfg.taunt.enabled and cfg.taunt.move) or HideTaunt(ply)) then
        return true
    end
end)

-- the taunt camera also asks for the local model to be drawn; in first person it is not
AddHook("ShouldDrawLocalPlayer", "tauntfirst", function()
    if HideTaunt(LocalPlayer()) then return false end

    -- a screengrab frame: our third person / free camera never shows your own model in it
    -- (the engine keeps drawviewer from the frame's CalcView, RenderView's alone isn't enough)
    if IsHidden() and (cfg.view.thirdperson or freeActive) then return false end
end)

local tpTrace = {
    mask = MASK_SOLID_BRUSHONLY,
    mins = Vector(-6, -6, -6),
    maxs = Vector(6, 6, 6),
}

-- two jobs: keep the screen on the real view while an injected angle is in the engine,
-- and move the camera behind the player for third person
AddHook("CalcView", "view", function(ply, origin, angles, fov, znear, zfar)
    -- The view as the game made it (before third person, FOV changer, removals), kept for the
    -- clean frame a screengrab gets: render.RenderView fills every field it isn't given from the
    -- current view, which is ours - that is how the changed FOV got into grabs.
    MV.cam = {origin = Vector(origin), angles = Angle(angles.p, angles.y, angles.r), fov = fov, time = RealTime()}

    -- a jpeg / screenshot frame: none of the camera changes, only the real view (with silent aim
    -- or anti-aim the engine's angle is the injected one)
    if IsHidden() then
        if silentDirty then return {origin = origin, angles = realAng, fov = fov, znear = znear, zfar = zfar} end
        return
    end

    -- removals: the shake and the punch are already inside origin / angles here, so they are
    -- taken out again against the player's plain eye position and angles
    local rm = cfg.removals
    local rmOn = rm.enabled
    local cleaned = false

    if rmOn and (rm.shake or rm.punch) and IsValid(ply) and ply:Alive()
        and not ply:InVehicle() and ply:GetViewEntity() == ply then
        local punch = ply.GetViewPunchAngles and ply:GetViewPunchAngles() or Angle(0, 0, 0)
        local a = Angle(angles.p, angles.y, angles.r)

        if rm.shake then
            a = a - (angles - ply:EyeAngles() - punch)      -- what is left over is the shake
            origin = ply:EyePos()
        end

        if rm.punch then a = a - punch end

        a:Normalize()
        angles = a
        cleaned = true
    end

    local viewAng = silentDirty and realAng or angles

    local third = cfg.view.thirdperson
        and IsValid(ply) and ply:Alive()
        and not ply:InVehicle() and ply:GetViewEntity() == ply

    camZNear, camZFar = znear, zfar
    camDrawViewer, camDrawViewModel = false, true

    -- during a taunt the gamemode would switch to its own third person taunt camera
    local tauntKeep = (cfg.taunt.enabled and cfg.taunt.move and IsValid(ply) and ply:IsPlayingTaunt())
        or HideTaunt(ply)

    if not silentDirty and not third and not freeActive
        and not cfg.view.fovOn and not tauntKeep and not cleaned and not (rmOn and rm.viewmodel) then return end

    local view = {
        origin = origin,
        angles = viewAng,
        fov = cfg.view.fovOn and cfg.view.fov or fov,
        znear = znear,
        zfar = zfar,
    }

    if freeActive then
        view.origin = freePos
        view.angles = freeAng
        view.drawviewer = true
        view.drawviewmodel = false
    elseif third then
        local v = cfg.view
        tpTrace.start = origin
        tpTrace.endpos = origin - viewAng:Forward() * v.distance
            + viewAng:Right() * v.shoulder
            + viewAng:Up() * v.height
        tpTrace.filter = ply

        view.origin = util.TraceHull(tpTrace).HitPos
        view.drawviewer = true
        view.drawviewmodel = false
    end

    if rmOn and rm.viewmodel then view.drawviewmodel = false end

    camDrawViewer = view.drawviewer or false
    camDrawViewModel = view.drawviewmodel ~= false

    return view
end)

-- Aspect ratio and viewmodel FOV are not part of what GM:CalcView can return (CamData has no such
-- fields); only render.RenderView's ViewData has `aspect` and `viewmodelfov`. So when either is
-- on, the scene is rendered here, with the origin / angles / fov CalcView ended up with.
AddHook("RenderScene", "scene", function(origin, angles, fov)
    local v, vmc = cfg.view, cfg.vm
    if not (v.aspectOn or vmc.fovOn) or IsHidden() then return end

    local data = {
        origin = origin,
        angles = angles,
        fov = fov,
        x = 0, y = 0, w = ScrW(), h = ScrH(),
        znear = camZNear,
        zfar = camZFar,
        drawviewer = camDrawViewer,
        drawviewmodel = camDrawViewModel,
        drawmonitors = true,
        dopostprocess = true,
        bloomtone = true,
        -- Returning true from RenderScene skips the engine's whole view pass, HUD included, and
        -- HUDPaint (the ESP, crosshair, indicators and the game's own HUD) is only called from
        -- inside it, so it has to be asked for here.
        drawhud = true,
    }

    if v.aspectOn then data.aspect = v.aspect end
    if vmc.fovOn then data.viewmodelfov = vmc.fov end

    render.RenderView(data)
    return true
end)

-- The viewmodel (hands + weapon) is laid out from the engine's eye angles, which hold the
-- injected angle while silent aim / anti-aim is active, so the hands used to jump around.
-- Re-express whatever the engine computed relative to the real view instead.
AddHook("CalcViewModelView", "viewmodel", function(wep, vm, oldPos, oldAng, pos, ang)
    local vmc = cfg.vm

    -- an earlier version wrote vmc.fov into SWEP.ViewModelFOV; put such a weapon back once
    if IsValid(wep) and wep.nyxVMSaved then
        if wep.nyxVMFov then wep.ViewModelFOV = wep.nyxVMFov end
        wep.nyxVMSaved = nil
    end

    local changed = false

    -- removals: no bob / sway / weapon offsets, the model sits where the eye is
    if cfg.removals.enabled and cfg.removals.bob then
        pos, ang = oldPos, oldAng
        changed = true
    end

    if silentDirty then
        local localPos, localAng = WorldToLocal(pos, ang, oldPos, oldAng)
        pos, ang = LocalToWorld(localPos, localAng, oldPos, realAng)
        changed = true
    end

    -- x = forward, y = right, z = up, relative to the weapon's own orientation
    if vmc.offsetOn and not IsHidden() then
        pos = pos + ang:Forward() * vmc.x + ang:Right() * vmc.y + ang:Up() * vmc.z
        changed = true
    end

    if changed then return pos, ang end
end)

-- ---------------------------------------------------------------------------
-- anti screengrab
--   Server-side screengrab tools call render.Capture / render.CapturePixels from PostRender,
--   i.e. after the frame (cheat visuals included) has been drawn. Both are wrapped here: the
--   frame is re-rendered with every cheat visual switched off, then the real call reads that.
--   The `jpeg` / `screenshot` console commands are covered by render.IsTakingScreenshot().
-- ---------------------------------------------------------------------------

local ssHidden = false          -- true while a clean frame is being produced

-- screengrab alert: every capture is counted, its picture saved to data/nyx/grabs/ and shown
-- in a corner with a shutter sound. One table instead of new locals (the chunk is at 200).
local SSG = {
    hidden  = 0,                -- captures that got the clean frame
    grabs   = 0,                -- captures seen at all
    mat     = nil,              -- the latest grab as a material
    file    = "",
    src     = "",               -- Lua file:line that called the capture
    time    = -100,             -- RealTime() of the latest grab
    soundAt = 0,
    SHOW    = 6,                -- seconds the preview stays
}

-- night mode / sky changes live in material parameters, so a grab needs them put back and
-- re-applied afterwards; the real functions are assigned in the world visuals block below
local function NoOp() end
local WorldMaterialsNeutral, WorldMaterialsRestore = NoOp, NoOp

local origCapture = render.Capture
local origCapturePixels = render.CapturePixels

-- every drawing hook of this script returns early while this is true
function IsHidden()
    if not cfg.misc.antiSS then return false end
    return ssHidden or render.IsTakingScreenshot()
end

local function RenderCleanFrame()
    ssHidden = true
    SSG.hidden = SSG.hidden + 1

    -- missing view fields default to the current view; HUDPaint runs again but IsHidden() skips us
    render.SetLightingMode(0)   -- the grab must not be fullbright either
    WorldMaterialsNeutral()     -- ... nor dark / re-skied

    local view = {
        x = 0, y = 0, w = ScrW(), h = ScrH(),
        drawhud = true, drawviewmodel = true, drawmonitors = true, dopostprocess = true,
    }

    -- Third person, free camera and the FOV changer are cheat visuals too: the grab gets the camera
    -- the game itself made this frame (first person, the weapon's own zoom, vehicles included).
    -- Every field is given, so nothing is taken over from our modified view.
    local ply = LocalPlayer()
    local cam = MV.cam

    if cam and RealTime() - cam.time < 1 then
        view.origin = cam.origin
        view.angles = silentDirty and realAng or cam.angles
        view.fov = cam.fov
    elseif IsValid(ply) then
        view.origin = ply:EyePos()
        view.angles = silentDirty and realAng or ply:EyeAngles()
    end

    if cfg.view.thirdperson or freeActive then view.drawviewer = false end

    -- always the screen's own aspect ratio (without it the one our RenderScene used is kept)
    view.aspect = ScrW() / ScrH()

    if cfg.vm.fovOn and IsValid(ply) then
        local wep = ply:GetActiveWeapon()
        view.viewmodelfov = (IsValid(wep) and wep.ViewModelFOV) or 62
    end

    pcall(render.RenderView, view)
end

-- file:line of whoever called the wrapper (level 1 = this, 2 = the wrapper, 3 = the caller)
function SSG.Caller()
    local info = debug.getinfo(3, "Sl")
    if not info then return "?" end
    return (info.short_src or "?") .. ":" .. (info.currentline or 0)
end

-- A grab happened. data is what the server's tool got (render.Capture), or nil for
-- render.CapturePixels: then the framebuffer is still the one it read, so it is captured again
-- here with the original function (no recursion, nothing reaches the server).
function SSG.Notify(data, params, src)
    local m = cfg.misc
    if not m.ssAlert then return end

    SSG.grabs = SSG.grabs + 1

    local ext = "jpg"
    if data then
        if istable(params) and params.format == "png" then ext = "png" end
    else
        local ok, d = pcall(origCapture, {format = "jpeg", quality = 80, x = 0, y = 0, w = ScrW(), h = ScrH()})
        data = ok and d or nil
    end

    if m.ssPreview and data and #data > 0 then
        file.CreateDir("nyx/grabs")
        local name = os.date("%Y%m%d_%H%M%S") .. "_" .. SSG.grabs .. "." .. ext
        file.Write("nyx/grabs/" .. name, data)

        -- unique name per grab: Material() caches by path
        local mat = Material("../data/nyx/grabs/" .. name, "smooth")
        SSG.mat = (mat and not mat:IsError()) and mat or nil
        SSG.file = "data/nyx/grabs/" .. name
    end

    SSG.src, SSG.time = src, RealTime()

    -- some tools capture in bursts; one shutter per half second
    if m.ssSound and RealTime() - SSG.soundAt > 0.5 then
        SSG.soundAt = RealTime()
        surface.PlaySound("npc/scanner/scanner_photo1.wav")
    end

    MsgC(Color(255, 80, 80), "[nyx] screengrab ", color_white, "#" .. SSG.grabs .. " from " .. src
        .. (SSG.file ~= "" and ("  ->  " .. SSG.file) or "") .. "\n")
end

render.Capture = function(...)
    local src = SSG.Caller()

    if not cfg.misc.antiSS then
        local data = origCapture(...)
        SSG.Notify(data, (...), src)
        return data
    end

    RenderCleanFrame()
    local ok, data = pcall(origCapture, ...)
    ssHidden = false
    WorldMaterialsRestore()

    if not ok then error(data, 0) end
    SSG.Notify(data, (...), src)
    return data
end

render.CapturePixels = function(...)
    local src = SSG.Caller()

    if not cfg.misc.antiSS then
        origCapturePixels(...)
        SSG.Notify(nil, nil, src)
        return
    end

    RenderCleanFrame()
    local ok, err = pcall(origCapturePixels, ...)

    -- re-capture before the world looks get re-applied: the framebuffer still holds the clean frame
    if ok then SSG.Notify(nil, nil, src) end

    ssHidden = false
    WorldMaterialsRestore()

    if not ok then error(err, 0) end
end

-- the latest grab in the top right corner, fading out; never part of a clean frame
AddHook("HUDPaint", "ssgrab", function()
    if IsHidden() or not cfg.misc.ssAlert then return end

    local age = RealTime() - SSG.time
    if age > SSG.SHOW then return end

    local a = math.Clamp((SSG.SHOW - age) / 0.6, 0, 1) * 255
    local w = 320
    local h = SSG.mat and math.floor(w * ScrH() / ScrW()) or 0
    local x, y = ScrW() - w - 16, 16

    surface.SetDrawColor(15, 15, 15, a * 0.9)
    surface.DrawRect(x - 4, y - 4, w + 8, h + 46)
    surface.SetDrawColor(255, 70, 70, a)
    surface.DrawOutlinedRect(x - 4, y - 4, w + 8, h + 46)

    draw.SimpleText("SCREENGRAB  #" .. SSG.grabs, "DermaDefaultBold", x, y, Color(255, 80, 80, a))
    draw.SimpleText(SSG.src, "DermaDefault", x, y + 16, Color(220, 220, 220, a))

    if SSG.mat then
        surface.SetDrawColor(255, 255, 255, a)
        surface.SetMaterial(SSG.mat)
        surface.DrawTexturedRect(x, y + 36, w, h)
    end
end)

-- ---------------------------------------------------------------------------
-- ESP
-- ---------------------------------------------------------------------------

surface.CreateFont("NyxESP", {
    font = "Verdana",
    size = 12,
    weight = 500,
    antialias = false,
})

local COL_WHITE = Color(255, 255, 255, 255)
local COL_BLACK = Color(0, 0, 0, 255)
local COL_BOXBG = Color(0, 0, 0, 200)

-- 2D screen rectangle around the entity's OBB, nil if any corner is off-screen
local function GetScreenBox(ent)
    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge

    for i = 0, 7 do
        local corner = ent:LocalToWorld(Vector(
            bit.band(i, 1) > 0 and maxs.x or mins.x,
            bit.band(i, 2) > 0 and maxs.y or mins.y,
            bit.band(i, 4) > 0 and maxs.z or mins.z
        ))
        local sp = corner:ToScreen()
        if not sp.visible then return nil end

        minX = math.min(minX, sp.x)
        minY = math.min(minY, sp.y)
        maxX = math.max(maxX, sp.x)
        maxY = math.max(maxY, sp.y)
    end

    return minX, minY, maxX - minX, maxY - minY
end

local function WeaponName(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return nil end

    local name = wep.GetPrintName and wep:GetPrintName()
    if not name or name == "" or name:sub(1, 1) == "#" then
        name = wep:GetClass()
    end
    return name
end

-- ---------------------------------------------------------------------------
-- world visuals: entity ESP / glow over the whole map, fullbright, no fog
-- ---------------------------------------------------------------------------

local WORLD_COLORS = {
    npc     = Color(255, 90, 60, 255),
    weapon  = Color(255, 220, 60, 255),
    prop    = Color(170, 170, 170, 255),
    vehicle = Color(70, 220, 255, 255),
    item    = Color(90, 255, 120, 255),
    door    = Color(190, 130, 70, 255),
    other   = Color(255, 255, 255, 255),
}

-- category of an entity, nil when it isn't something the world ESP cares about
local function WorldCategory(e)
    if e:IsPlayer() then return nil end

    local class = e:GetClass()

    if e:IsNPC() or e:IsNextBot() then return "npc" end

    if e:IsWeapon() then
        if IsValid(e:GetOwner()) then return nil end   -- held weapons belong to their player
        return "weapon"
    end

    if e:IsVehicle() then return "vehicle" end

    if class:sub(1, 5) == "prop_" then
        if class:find("^prop_door") then return "door" end
        if class:find("^prop_physics") or class == "prop_ragdoll" then return "prop" end
        return nil   -- prop_dynamic / prop_static are map decoration
    end

    if class:find("^func_door") then return "door" end
    if class:find("^item_") or class:find("^ammo_") then return "item" end

    if scripted_ents.Get(class) then return "other" end

    return nil
end

local worldCache, worldNext = {}, 0

-- {ent, cat} for every entity of an enabled category; rebuilt twice a second
local function GetWorldList(me)
    local now = CurTime()
    if now < worldNext then return worldCache end
    worldNext = now + 0.5

    local w = cfg.world
    local list = {}

    for _, e in ipairs(ents.GetAll()) do
        if IsValid(e) and e ~= me and not e:GetNoDraw() then
            local cat = WorldCategory(e)
            if cat and w[cat] then
                list[#list + 1] = {ent = e, cat = cat}
            end
        end
    end

    worldCache = list
    return list
end

-- Custom entity names (Entities tab: right-click > Rename), key -> name; kept on MV because the
-- Entities tab further down and the ESP here both read it. Saved in data/nyx/entities.json.
MV.entNames = MV.entNames or {}

-- What makes two entities "the same kind": the class, plus the model when the class alone says
-- nothing (prop_physics, prop_dynamic, model-only entities). nil for players.
function MV.EntKey(e)
    if e:IsPlayer() then return nil end

    local cls = e:GetClass()
    if scripted_ents.GetStored(cls) or e:IsNPC() or e:IsNextBot() or e:IsWeapon() or e:IsVehicle()
        or cls:find("^item_") or cls:find("^ammo_") or cls:find("door") then
        return cls
    end

    return cls .. "|" .. (e:GetModel() or "")
end

local function WorldLabel(e, cat)
    if next(MV.entNames) then
        local key = MV.EntKey(e)
        if key and MV.entNames[key] then return MV.entNames[key] end
    end

    if cat == "weapon" then
        local n = e.GetPrintName and e:GetPrintName()
        if n and n ~= "" and n:sub(1, 1) ~= "#" then return n end
    elseif cat == "prop" then
        local mdl = e:GetModel()
        if mdl then return mdl:match("([^/]+)%.mdl$") or e:GetClass() end
    end

    return e:GetClass()
end

-- glow through walls
AddHook("PreDrawHalos", "worldglow", function()
    local w = cfg.world
    if not w.enabled or not w.glow or IsHidden() then return end

    local me = LocalPlayer()
    if not IsValid(me) then return end

    local myPos = me:GetPos()
    local byCat = {}

    for _, entry in ipairs(GetWorldList(me)) do
        local e = entry.ent
        if IsValid(e) and myPos:Distance(e:GetPos()) * 0.01905 <= w.maxDist then
            local list = byCat[entry.cat]
            if not list then
                list = {}
                byCat[entry.cat] = list
            end
            if #list < 64 then list[#list + 1] = e end
        end
    end

    for cat, list in pairs(byCat) do
        halo.Add(list, WORLD_COLORS[cat], 2, 2, 1, true, true)
    end
end)

-- fullbright: the lighting mode is set around the scene and reset afterwards
AddHook("PreRender", "fullbright", function()
    -- The jpeg / screenshot console commands (and F12) save the frame being drawn: the hooks skip
    -- themselves through IsHidden(), but night mode / the sky live in material parameters, so
    -- for that frame the map's own look goes back on, and ours again after it (PostRender).
    if cfg.misc.antiSS and render.IsTakingScreenshot() and not MV.ssWorld then
        MV.ssWorld = true
        WorldMaterialsNeutral()
    end

    if cfg.world.fullbright and not IsHidden() then
        render.SetLightingMode(1)
    end
end)

AddHook("PostRender", "fullbright", function()
    render.SetLightingMode(0)

    if MV.ssWorld and not render.IsTakingScreenshot() then
        MV.ssWorld = nil
        WorldMaterialsRestore()
    end
end)

-- fog: custom colour / range, or removed completely
local function FogOverride(scale)
    if IsHidden() then return end

    local w = cfg.world
    if w.fogOn then
        render.FogMode(MATERIAL_FOG_LINEAR)
        render.FogStart(w.fogStart * scale)
        render.FogEnd(w.fogEnd * scale)
        render.FogMaxDensity(w.fogDensity)
        render.FogColor(w.fogR, w.fogG, w.fogB)
        return true
    elseif w.noFog or (cfg.removals.enabled and cfg.removals.fog) then
        render.FogMode(MATERIAL_FOG_NONE)
        return true
    end
end

AddHook("SetupWorldFog", "fog", function() return FogOverride(1) end)
AddHook("SetupSkyboxFog", "fogsky", function(scale) return FogOverride(scale or 1) end)

-- night mode + skybox changer: colour / texture parameters of the map's own materials
local SKY_FACES = {"up", "dn", "lf", "rt", "ft", "bk"}

local SKY_PRESETS = {
    {"Map default", "default"},
    {"Day 1", "sky_day01_01"},
    {"Overcast", "sky_day01_09"},
    {"Day 2", "sky_day02_05"},
    {"Dusk", "sky_day03_06"},
    {"Borealis", "sky_borealis01"},
    {"Wasteland", "sky_wasteland02"},
}

-- night mode / skybox / fog helpers live in their own block; the menu only needs WL
local WL = {}

do
local worldMats = nil          -- IMaterial list of the map's brushes (collected on first use)
local skyMats = {}             -- face -> IMaterial of the current sky
local skyOrigTex = {}          -- face -> {texture key -> original ITexture, scale = original $hdrcolorscale}
local skyName = ""
local worldError = nil
local worldSig, worldTouched, worldNext = nil, false, 0

-- sky shader texture slots: HDR is on by default and then the plain $basetexture is ignored,
-- so a skybox swap has to touch the two HDR slots as well
local SKY_TEX_KEYS = {"$basetexture", "$hdrbasetexture", "$hdrcompressedtexture"}

-- Every material the map's brushes use. Lump 43 (TEXDATA_STRING_DATA) of the .bsp is just a run
-- of NUL separated material paths, which is far more dependable than asking the world entity.
local function ReadMapMaterialNames()
    local names = {}

    local f = file.Open("maps/" .. game.GetMap() .. ".bsp", "rb", "GAME")
    if not f then return names end

    f:Seek(8 + 43 * 16)             -- header: ident, version, then 16 byte lump records
    local ofs, len = f:ReadLong(), f:ReadLong()

    if ofs > 0 and len > 0 and len < 8 * 1024 * 1024 then
        f:Seek(ofs)
        local data = f:Read(len)
        if data then
            for name in string.gmatch(data, "([^%z]+)") do
                names[#names + 1] = name
            end
        end
    end

    f:Close()
    return names
end

-- The models of the map's prop_static (houses, trees, crates ...): lump 43 only has the brushes,
-- and on most maps the static props are a big part of what you see. They sit in the game lump
-- (35) under 'sprp': a count, then 128 byte model paths. (On WL: no new local in this block.)
function WL.ReadStaticPropModels()
    local models = {}

    local f = file.Open("maps/" .. game.GetMap() .. ".bsp", "rb", "GAME")
    if not f then return models end

    f:Seek(8 + 35 * 16)
    local ofs = f:ReadLong()

    if ofs and ofs > 0 then
        f:Seek(ofs)
        local count = f:ReadLong() or 0

        for _ = 1, math.min(count, 64) do
            local id = f:ReadLong()
            f:ReadShort()                       -- flags
            f:ReadShort()                       -- version
            local lofs, llen = f:ReadLong(), f:ReadLong()

            -- 'sprp' as a little-endian int
            if id == 0x73707270 and lofs and lofs > 0 and llen and llen > 4 then
                f:Seek(lofs)
                local n = f:ReadLong() or 0

                for _ = 1, math.min(n, 2048) do
                    local raw = f:Read(128)
                    if not raw then break end
                    local name = string.match(raw, "^([^%z]+)")
                    if name then models[#models + 1] = string.lower(name) end
                end
                break
            end
        end
    end

    f:Close()
    return models
end

-- Every material those models use. Read through a short-lived client model (static props are
-- not entities); done once per map. Model materials take their tint from $color2.
function WL.StaticPropMaterials()
    local names, seenModel = {}, {}

    for i, mdl in ipairs(WL.ReadStaticPropModels()) do
        if i > 600 then break end
        if not seenModel[mdl] then
            seenModel[mdl] = true

            local ent = ClientsideModel(mdl, RENDERGROUP_OTHER)
            if IsValid(ent) then
                for _, m in ipairs(ent:GetMaterials() or {}) do names[#names + 1] = m end
                ent:Remove()
            end
        end
    end

    WL.propModels = table.Count(seenModel)
    return names
end

local function CollectWorldMaterials()
    if worldMats then return end

    local list, seen = {}, {}
    local function add(name)
        name = string.lower(name)
        if seen[name] then return end
        seen[name] = true

        local m = Material(name)
        if m and not m:IsError() then list[#list + 1] = m end
    end

    for _, name in ipairs(ReadMapMaterialNames()) do add(name) end
    WL.brushMats = #list

    -- the static props' materials (night mode / custom time darken them as well)
    local ok, propNames = pcall(WL.StaticPropMaterials)
    if ok then
        for _, name in ipairs(propNames) do add(name) end
    end
    WL.propMats = #list - WL.brushMats

    -- plus whatever the world entity itself reports
    local world = game.GetWorld()
    if IsValid(world) then
        local ok, mats = pcall(world.GetMaterials, world)
        if ok and istable(mats) then
            for _, name in ipairs(mats) do add(name) end
        end
    end

    skyMats, skyOrigTex = {}, {}
    local cv = GetConVar("sv_skyname")
    skyName = cv and cv:GetString() or ""

    for _, face in ipairs(SKY_FACES) do
        local m = Material("skybox/" .. skyName .. face)
        if m and not m:IsError() then
            skyMats[face] = m

            -- The map's own textures / brightness are read only the first time this sky material
            -- is seen. Read again later ("Re-apply", a re-collect) they would already be the night
            -- / preset values, "neutral" would put those back, and the darkened sky ended up in
            -- screengrabs and stayed after night mode was switched off.
            WL.skySaved = WL.skySaved or {}
            local orig = WL.skySaved[skyName .. face]

            if not orig then
                orig = {}
                for _, key in ipairs(SKY_TEX_KEYS) do orig[key] = m:GetTexture(key) end

                local scale = m:GetFloat("$hdrcolorscale")
                orig.scale = (scale and scale > 0) and scale or 1

                WL.skySaved[skyName .. face] = orig
            end

            skyOrigTex[face] = orig
        end
    end

    -- nothing found (map not ready yet?): stay unset so the next apply tries again
    if #list > 0 or next(skyMats) then worldMats = list end
end

local function SetMatColor(m, v)
    m:SetVector("$color", v)
    m:SetVector("$color2", v)
    m:Recompute()
end

-- Maps with an env_skypaint (gm_construct, gm_flatgrass, most sandbox maps) never draw the
-- skybox textures: the sky is procedural and driven by that entity's values, so it has to be
-- changed through its setters. That is why swapping skybox materials did nothing there.
local skyPaint = nil
local skyPaintOrig = nil

local SKYPAINT_FIELDS = {
    "TopColor", "BottomColor", "DuskColor", "SunColor", "FadeBias", "HDRScale",
    "DuskIntensity", "DuskScale", "SunSize", "DrawStars", "StarLayers", "SunNormal",
}

-- Custom time: keyframes over the day, blended linearly (24 wraps to 0). world = the map's
-- light colour, sky = the multiplier for skyboxes made of textures, the rest are env_skypaint
-- values. Kept on WL: this block shares the main chunk's 200 locals.
WL.TIME_KEYS = {
    {h = 0,  world = Vector(0.16, 0.18, 0.28), sky = Vector(0.10, 0.12, 0.22),
        top = Vector(0.01, 0.02, 0.06), bottom = Vector(0.03, 0.05, 0.12), dusk = Vector(0, 0, 0), duskI = 0, stars = true},
    {h = 5,  world = Vector(0.30, 0.30, 0.42), sky = Vector(0.30, 0.28, 0.42),
        top = Vector(0.05, 0.07, 0.20), bottom = Vector(0.40, 0.25, 0.30), dusk = Vector(1.0, 0.40, 0.20), duskI = 1.5, stars = true},
    {h = 7,  world = Vector(0.85, 0.70, 0.60), sky = Vector(0.90, 0.72, 0.62),
        top = Vector(0.25, 0.40, 0.80), bottom = Vector(1.00, 0.65, 0.40), dusk = Vector(1.0, 0.50, 0.20), duskI = 2, stars = false},
    {h = 12, world = Vector(1, 1, 1), sky = Vector(1, 1, 1),
        top = Vector(0.20, 0.50, 1.00), bottom = Vector(0.80, 1.00, 1.00), dusk = Vector(1.0, 0.60, 0.30), duskI = 0, stars = false},
    {h = 17, world = Vector(1.00, 0.92, 0.82), sky = Vector(1.00, 0.92, 0.85),
        top = Vector(0.25, 0.45, 0.85), bottom = Vector(0.95, 0.80, 0.60), dusk = Vector(1.0, 0.50, 0.20), duskI = 0.5, stars = false},
    {h = 19, world = Vector(0.80, 0.55, 0.45), sky = Vector(0.95, 0.60, 0.45),
        top = Vector(0.20, 0.15, 0.40), bottom = Vector(1.00, 0.45, 0.20), dusk = Vector(1.0, 0.30, 0.10), duskI = 3, stars = false},
    {h = 21, world = Vector(0.35, 0.33, 0.45), sky = Vector(0.30, 0.28, 0.42),
        top = Vector(0.04, 0.05, 0.15), bottom = Vector(0.20, 0.12, 0.25), dusk = Vector(0.8, 0.30, 0.20), duskI = 1, stars = true},
}

-- the blended look at hour h, plus the sun's direction (east at 6, overhead at 12, west at 18,
-- under the horizon at night)
function WL.TimeLook(h)
    local keys = WL.TIME_KEYS
    h = h % 24

    local a, b = keys[#keys], keys[1]
    for i = 1, #keys do
        local nxt = keys[i + 1] or keys[1]
        if h >= keys[i].h and (h < nxt.h or not keys[i + 1]) then
            a, b = keys[i], nxt
            break
        end
    end

    local span = (b.h - a.h) % 24
    if span == 0 then span = 24 end
    local f = ((h - a.h) % 24) / span

    local function L(x, y) return LerpVector(f, x, y) end

    local sunAng = (h - 6) / 24 * math.pi * 2         -- 0 at 6:00 (rising in the east)
    return {
        world = L(a.world, b.world), sky = L(a.sky, b.sky),
        top = L(a.top, b.top), bottom = L(a.bottom, b.bottom), dusk = L(a.dusk, b.dusk),
        duskI = Lerp(f, a.duskI, b.duskI), stars = (f < 0.5) and a.stars or b.stars,
        sun = Vector(math.cos(sunAng), 0.25, math.sin(sunAng)):GetNormalized(),
    }
end

-- the same preset names as SKY_PRESETS, as painted-sky colours
local SKYPAINT_PRESETS = {
    sky_day01_01    = {TopColor = Vector(0.20, 0.50, 1.00), BottomColor = Vector(0.80, 1.00, 1.00), HDRScale = 0.66, DrawStars = false},
    sky_day01_09    = {TopColor = Vector(0.42, 0.48, 0.55), BottomColor = Vector(0.70, 0.72, 0.75), HDRScale = 0.5, DrawStars = false},
    sky_day02_05    = {TopColor = Vector(0.05, 0.35, 0.95), BottomColor = Vector(0.85, 0.95, 1.00), HDRScale = 0.8, DrawStars = false},
    sky_day03_06    = {TopColor = Vector(0.22, 0.18, 0.45), BottomColor = Vector(1.00, 0.55, 0.25), DuskColor = Vector(1.0, 0.35, 0.1), DuskIntensity = 2, HDRScale = 0.6, DrawStars = false},
    sky_borealis01  = {TopColor = Vector(0.00, 0.12, 0.10), BottomColor = Vector(0.10, 0.50, 0.30), HDRScale = 0.5, DrawStars = true, StarLayers = 2},
    sky_wasteland02 = {TopColor = Vector(0.50, 0.35, 0.20), BottomColor = Vector(0.80, 0.65, 0.40), HDRScale = 0.6, DrawStars = false},
}

local function FindSkyPaint()
    if IsValid(skyPaint) then return skyPaint end

    skyPaint = ents.FindByClass("env_skypaint")[1]

    -- the values remembered as the map's own stay as long as it is the same entity (looked up
    -- again after "Re-apply" it would hand back our night colours as the originals)
    if skyPaint ~= WL.skyPaintOwner then
        skyPaintOrig = nil
        WL.skyPaintOwner = skyPaint
    end

    return skyPaint
end

local function ApplySkyPaint(neutral)
    local sp = FindSkyPaint()
    if not IsValid(sp) then return end

    -- remember the map's own values the first time
    if not skyPaintOrig then
        skyPaintOrig = {}
        for _, f in ipairs(SKYPAINT_FIELDS) do
            local getter = sp["Get" .. f]
            if getter then skyPaintOrig[f] = getter(sp) end
        end
    end

    local w = cfg.world
    local values = {}
    for f, v in pairs(skyPaintOrig) do values[f] = v end

    if not neutral then
        local preset = w.skyPreset ~= "default" and SKYPAINT_PRESETS[w.skyPreset]
        if preset then
            for f, v in pairs(preset) do values[f] = v end
        end

        local tint = Vector(1, 1, 1)

        if w.timeOn then
            -- custom time: the sky is painted from the hour (night mode's darkening is skipped)
            local t = WL.TimeLook(w.timeHour)
            values.TopColor, values.BottomColor, values.DuskColor = t.top, t.bottom, t.dusk
            values.DuskIntensity = t.duskI
            values.DrawStars = t.stars
            if t.stars then values.StarLayers = math.max(values.StarLayers or 0, 2) end
            values.SunNormal = t.sun
            values.SunColor = t.sun.z > 0 and Vector(0.3, 0.25, 0.15) or Vector(0, 0, 0)
        elseif w.night then
            local b = 1 - math.Clamp(w.nightAmount, 0, 0.95)
            tint = Vector(b * 0.5, b * 0.55, b * 0.7)
            values.DrawStars = true
            values.StarLayers = math.max(values.StarLayers or 0, 2)
        end

        if w.skyTint then
            tint = Vector(tint.x * w.skyR / 255, tint.y * w.skyG / 255, tint.z * w.skyB / 255)
        end

        for _, f in ipairs({"TopColor", "BottomColor", "DuskColor", "SunColor"}) do
            local c = values[f]
            if c then values[f] = Vector(c.x * tint.x, c.y * tint.y, c.z * tint.z) end
        end
    end

    for f, v in pairs(values) do
        local setter = sp["Set" .. f]
        if setter then setter(sp, v) end
    end
end

-- neutral = everything back to how the map ships it
local function ApplyWorldLook(neutral)
    CollectWorldMaterials()
    local w = cfg.world

    local worldCol = Vector(1, 1, 1)
    local skyCol = Vector(1, 1, 1)

    if not neutral then
        if w.timeOn then
            local t = WL.TimeLook(w.timeHour)
            worldCol, skyCol = t.world, t.sky
        elseif w.night then
            local b = 1 - math.Clamp(w.nightAmount, 0, 0.95)
            worldCol = Vector(b * 0.8, b * 0.9, b)          -- slightly blue
            skyCol = Vector(b * 0.5, b * 0.55, b * 0.7)
        end

        if w.skyTint then
            skyCol = Vector(
                skyCol.x * w.skyR / 255,
                skyCol.y * w.skyG / 255,
                skyCol.z * w.skyB / 255
            )
        end
    end

    for _, m in ipairs(worldMats or {}) do SetMatColor(m, worldCol) end

    local skyScale = (skyCol.x + skyCol.y + skyCol.z) / 3

    for face, m in pairs(skyMats) do
        local orig = skyOrigTex[face] or {}

        local preset
        if not neutral and w.skyPreset ~= "default" then
            preset = Material("skybox/" .. w.skyPreset .. face)
            if preset:IsError() then preset = nil end
        end

        for _, key in ipairs(SKY_TEX_KEYS) do
            local tex = orig[key]

            if preset then
                local pt = preset:GetTexture(key)
                if pt and not pt:IsError() then tex = pt end
            end

            if tex then m:SetTexture(key, tex) end
        end

        -- tint for the plain sky, brightness scale for the HDR one
        m:SetFloat("$hdrcolorscale", (orig.scale or 1) * skyScale)
        SetMatColor(m, skyCol)
    end

    ApplySkyPaint(neutral)
end

WorldMaterialsNeutral = function()
    if worldTouched then pcall(ApplyWorldLook, true) end
end

WorldMaterialsRestore = function()
    if worldTouched then pcall(ApplyWorldLook, false) end
end

-- menu helpers: re-run the apply, and a one line status so it is visible whether anything was found
local function ForceWorldLook()
    worldSig = nil
    worldMats = nil
    skyPaint = nil
    worldNext = 0
end

local function WorldLookStatus()
    if worldError then return "error: " .. string.sub(worldError, -24) end
    if not worldMats then return "Map materials: none yet" end

    return string.format("Map: %d brush + %d prop mats", WL.brushMats or #worldMats, WL.propMats or 0)
end

local function SkyLookStatus()
    if worldError then return "error: " .. string.sub(worldError, -24) end
    if IsValid(skyPaint) then return "Sky: painted sky (env_skypaint)" end

    local faces = 0
    for _ in pairs(skyMats) do faces = faces + 1 end

    return string.format("Sky: %s (%d/6 faces)", skyName ~= "" and skyName or "?", faces)
end

-- re-apply whenever one of the settings changes (checked four times a second)
AddHook("Think", "worldlook", function()
    local now = CurTime()
    if now < worldNext then return end
    worldNext = now + 0.25

    local w = cfg.world

    -- day cycle: the hour runs on (the slider moves with it)
    if w.timeOn and w.timeCycle then
        local rt = RealTime()
        local dt = WL.timeLast and math.min(rt - WL.timeLast, 1) or 0
        WL.timeLast = rt
        w.timeHour = (w.timeHour + dt * w.timeSpeed / 60) % 24
    else
        WL.timeLast = nil
    end

    -- the hour in tenths: a change that small is re-applied, finer steps aren't worth it
    local sig = table.concat({
        tostring(w.night), w.nightAmount, tostring(w.skyTint), w.skyR, w.skyG, w.skyB, w.skyPreset,
        tostring(w.timeOn), w.timeOn and math.floor(w.timeHour * 10) or 0,
    }, "|")
    if sig == worldSig then return end
    worldSig = sig

    local wants = w.night or w.timeOn or w.skyTint or w.skyPreset ~= "default"
    if not wants and not worldTouched then return end   -- never changed anything, nothing to undo

    worldTouched = true

    local ok, err = pcall(ApplyWorldLook, false)
    worldError = (not ok) and tostring(err) or nil
end)

-- night mode, screen-space part: dims everything (players too), for maps where the material
-- colour above has no visible effect
AddHook("RenderScreenspaceEffects", "nightscreen", function()
    local w = cfg.world
    if not (w.night and w.nightScreen) or IsHidden() then return end

    local a = math.Clamp(w.nightAmount, 0, 0.95)

    DrawColorModify({
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = 0,
        ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = -a * 0.35,
        ["$pp_colour_contrast"] = 1 + a * 0.15,
        ["$pp_colour_colour"] = 1 - a * 0.35,
        ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0,
        ["$pp_colour_mulb"] = 0.05 * a,
    })
end)

-- custom time, screen-space part: the hour's light colour over everything (players and props
-- too), for maps where the material colour has no visible effect
AddHook("RenderScreenspaceEffects", "timescreen", function()
    local w = cfg.world
    if not (w.timeOn and w.timeScreen) or IsHidden() then return end

    local c = WL.TimeLook(w.timeHour).world
    local lum = (c.x + c.y + c.z) / 3

    DrawColorModify({
        ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = (lum - 1) * 0.35,
        ["$pp_colour_contrast"] = 1,
        ["$pp_colour_colour"] = 0.6 + 0.4 * lum,
        ["$pp_colour_mulr"] = (c.x - lum) * 2,
        ["$pp_colour_mulg"] = (c.y - lum) * 2,
        ["$pp_colour_mulb"] = (c.z - lum) * 2,
    })
end)

-- solid colour sky: the engine's sky is skipped and the screen cleared with the colour instead,
-- which works on every map whatever the sky is made of
AddHook("PreDrawSkyBox", "skysolid", function()
    local w = cfg.world
    if not w.skySolid or IsHidden() then return end

    render.Clear(w.solidR, w.solidG, w.solidB, 255)
    return true
end)

WL.Force = ForceWorldLook
WL.Status = WorldLookStatus
WL.SkyStatus = SkyLookStatus
end   -- world look

-- ---------------------------------------------------------------------------
-- player chams
-- ---------------------------------------------------------------------------

-- Looks for chams. Some are materials the game ships, some are made here with CreateMaterial so
-- they exist on every install; a stock one that doesn't load (content not mounted) is simply left
-- out of the list. CHAMS_MATS[key] is the IMaterial, CHAMS_LIT[mat] marks those that need the
-- engine's lighting (the rest are drawn with it suppressed, so they come out as flat colour),
-- CHAMS_CHOICES is {label, key} for the menu.
local CHAMS_MATS, CHAMS_LIT, CHAMS_CHOICES = {}, {}, {}

do
    local WHITE = "models/debug/debugwhite"

    local function Made(name, shader, params)
        params["$model"] = 1
        return CreateMaterial("nyx_cham_" .. name, shader, params)
    end

    local defs = {
        {"flat",      "Flat",        Material(WHITE)},
        {"glow",      "Glow",        Made("glow", "UnlitGeneric", {["$basetexture"] = WHITE, ["$additive"] = 1})},
        {"wireframe", "Wireframe",   Material("models/wireframe")},
        {"wireglow",  "Wire glow",   Made("wireglow", "UnlitGeneric", {["$basetexture"] = WHITE, ["$wireframe"] = 1, ["$additive"] = 1})},
        {"rim",       "Rim light",   Made("rim", "VertexLitGeneric", {
            ["$basetexture"] = WHITE, ["$phong"] = 1, ["$phongexponent"] = 8, ["$phongboost"] = 8,
            ["$phongfresnelranges"] = "[0.1 0.5 1]",
        }), true},
        -- Recolourable copies of four HL2 effect materials (their .vmt read out of the game's
        -- VPKs, the same textures and scrolling, only the colour opened up):
        --  * Shield / Crystal are Refract: they ignore the colour modulation, the colour is
        --    $refracttint (written per draw by MV.ChamTint); the tint *textures* they had are
        --    dropped, those would fix the colour.
        --  * Energy ball / Portal are additive and the modulation does reach them, but it is
        --    multiplied with textures that are teal: red came out nearly black. $color evens the
        --    channels out (texture's luminance / its average per channel, from the .vtf headers'
        --    reflectivity), so texture x $color is grey-ish and the modulation gives the hue.
        {"shield",    "Shield",      Made("nyx_shield2", "Refract", {
            ["$nocull"] = 1, ["$nowritez"] = 1, ["$bluramount"] = 1, ["$refractamount"] = ".02",
            ["$dudvmap"] = "models/shadertest/shader3_dudv", ["$normalmap"] = "models/shadertest/shader3_normal",
            ["$envmap"] = "env_cubemap", ["$envmaptint"] = "[.1 .1 .2]", ["$refracttint"] = "[1 1 1]",
            Proxies = {TextureScroll = {texturescrollvar = "$bumptransform", texturescrollrate = 0.08, texturescrollangle = 90}},
        }), nil, "refract"},
        {"energy",    "Energy ball", Made("nyx_energy2", "UnlitGeneric", {
            ["$basetexture"] = "models/effects/comball_sphere", ["$additive"] = 1, ["$translucent"] = 1,
            ["$color"] = "[1.45 0.72 1.24]",
            Proxies = {TextureScroll = {texturescrollvar = "$basetexturetransform", texturescrollrate = 1, texturescrollangle = -80}},
        })},
        {"portal",    "Portal",      Made("nyx_portal2", "UnlitTwoTexture", {
            ["$basetexture"] = "models/props_combine/portalball001_sheet",
            ["$texture2"] = "models/props_combine/portalball001b_sheet",
            ["$nocull"] = 1, ["$additive"] = 1, ["$color"] = "[2.5 0.72 0.83]",
            Proxies = {TextureScroll = {texturescrollvar = "$texture2transform", texturescrollrate = -0.2, texturescrollangle = 60}},
        })},
        {"warp",      "Warp",        Material("models/props_lab/warp_sheet")},
        {"crystal",   "Crystal",     Made("nyx_crystal2", "Refract", {
            ["$refractamount"] = ".05", ["$scale"] = "[1 1]",
            ["$dudvmap"] = "models/props_lab/xencrystal_dudv", ["$normalmap"] = "models/props_lab/xencrystal_normal",
            ["$envmap"] = "env_cubemap", ["$envmapcontrast"] = 1, ["$envmapsaturation"] = "[1 1 1]",
            ["$envmaptint"] = "[1 1 .1]", ["$refracttint"] = "[1 0.86 0]",
            -- the original animated its tint texture; with that gone the ripples move instead
            Proxies = {TextureScroll = {texturescrollvar = "$bumptransform", texturescrollrate = 0.05, texturescrollangle = 45}},
        }), nil, "refract"},
        {"electric",  "Electric",    Material("cable/blue_elec")},
        -- Self-illumination ($selfillum): the model keeps the engine's lighting and shape, and the
        -- glow is added on top, so it never goes dark. The base texture's alpha is the glow mask
        -- (vgui/white: all of it). The glow colour is $selfillumtint, which the colour modulation
        -- doesn't reach, so MV.ChamTint writes it before every draw: full strength, or half for
        -- "soft" where the shading still shows through.
        -- (vgui/white and dev/flat_normal both ship with GMod's HL2 content)
        -- The look from the reference shot: the colour fully shaded by the world's light (dark
        -- sides go deep, lit sides bright), a soft gloss from phong + the map's cubemap, and only
        -- a little self-illumination so the darkest parts never turn pure black.
        -- (phong needs a bump map in this shader: a flat one)
        {"selfillum", "Self-illum",  Made("nyx_selfillum3", "VertexLitGeneric", {
            ["$basetexture"] = "vgui/white", ["$bumpmap"] = "dev/flat_normal",
            ["$selfillum"] = 1, ["$selfillumtint"] = "[0.12 0.12 0.12]",
            ["$phong"] = 1, ["$phongexponent"] = 12, ["$phongboost"] = 1.5,
            ["$phongfresnelranges"] = "[0.3 0.6 1]",
            ["$envmap"] = "env_cubemap", ["$envmaptint"] = "[0.12 0.12 0.12]",
        }), true, 0.12},
        {"selfillumglow", "Self-illum glow", Made("nyx_selfillumglow2", "VertexLitGeneric", {
            ["$basetexture"] = "vgui/white", ["$selfillum"] = 1, ["$selfillumtint"] = "[0.6 0.6 0.6]",
        }), true, 0.6},
        {"selfillumfull", "Self-illum full", Made("nyx_selfillumfull2", "VertexLitGeneric", {
            ["$basetexture"] = "vgui/white", ["$selfillum"] = 1, ["$selfillumtint"] = "[1 1 1]",
        }), true, 1},
        -- the glow only toward the silhouette: $selfillumfresnel (needs a bump map, a flat one here)
        {"selfillumrim", "Self-illum rim", Made("nyx_selfillumrim2", "VertexLitGeneric", {
            ["$basetexture"] = "vgui/white", ["$bumpmap"] = "dev/flat_normal",
            ["$selfillum"] = 1, ["$selfillumfresnel"] = 1, ["$selfillumfresnelminmaxexp"] = "[0 1 1.5]",
            ["$selfillumtint"] = "[1 1 1]",
        }), true, 1},
    }

    -- material -> how strong its self-illumination is (only the selfillum ones are in here)
    MV.chamTint = {}

    for _, d in ipairs(defs) do
        local key, label, mat, lit, tint = d[1], d[2], d[3], d[4], d[5]

        if mat and not mat:IsError() then
            CHAMS_MATS[key] = mat
            CHAMS_LIT[mat] = lit and true or nil
            CHAMS_CHOICES[#CHAMS_CHOICES + 1] = {label, key}
            if tint then MV.chamTint[mat] = tint end
        end
    end
end

-- The colour of a material the modulation doesn't fully colour, from the same r, g, b the
-- modulation gets: the glow of a selfillum one (MV.chamTint = its strength), the tint of a
-- Refract one (MV.chamTint = "refract", its reflections get a dimmer share). Nothing for the rest.
function MV.ChamTint(mat, r, g, b)
    local k = mat and MV.chamTint[mat]
    if not k then return end

    r, g, b = r / 255, g / 255, b / 255

    if k == "refract" then
        mat:SetVector("$refracttint", Vector(r, g, b))
        mat:SetVector("$envmaptint", Vector(r * 0.3, g * 0.3, b * 0.3))
        return
    end

    mat:SetVector("$selfillumtint", Vector(r * k, g * k, b * k))
end

local function DrawCham(ent, mat, r, g, b, alpha, ignoreZ)
    MV.ChamTint(mat, r, g, b)
    cam.IgnoreZ(ignoreZ)
    render.SuppressEngineLighting(not CHAMS_LIT[mat])
    render.MaterialOverride(mat)
    render.SetColorModulation(r / 255, g / 255, b / 255)
    render.SetBlend(alpha / 255)

    ent:DrawModel()

    render.SetBlend(1)
    render.SetColorModulation(1, 1, 1)
    render.MaterialOverride(nil)
    render.SuppressEngineLighting(false)
    cam.IgnoreZ(false)
end

-- Why the visible colour does not come from a second DrawModel pass: the engine has already
-- drawn the model, so a second pass lands on exactly the same depth, fails the depth test and
-- never shows. Only the always-visible pass ("behind walls" colour) did, over the whole model,
-- which made the visible colour look dead and the behind-walls colour repaint everything.
-- So the visible colour is put on the engine's own draw of the player (material, colour and
-- blend overridden between PrePlayerDraw and PostPlayerDraw, depth tested as usual), and the
-- through-walls pass is the only extra draw: made first, with the depth test off.
do
    local busy = false        -- our own DrawModel must not re-enter the hook
    local active = false      -- an override is waiting to be undone in PostPlayerDraw

    local function Undo()
        render.SetBlend(1)
        render.SetColorModulation(1, 1, 1)
        render.MaterialOverride(nil)
        render.SuppressEngineLighting(false)
    end

    -- no return values in either hook: returning true from PrePlayerDraw cancels the draw
    AddHook("PrePlayerDraw", "chams", function(ply)
        if busy then return end

        -- an override that never got its PostPlayerDraw would paint whatever is drawn next
        if active then
            active = false
            Undo()
        end

        if IsHidden() then return end

        local c = cfg.chams
        if not c.enabled then return end

        local me = LocalPlayer()
        if not IsValid(me) or not ply:Alive() then return end

        local mat, r, g, b, alpha

        if ply == me then
            -- your own model is only on screen in third person / free camera
            if not c.self or not (cfg.view.thirdperson or freeActive) then return end

            mat = CHAMS_MATS[c.selfMaterial] or CHAMS_MATS.flat
            r, g, b, alpha = c.selfR, c.selfG, c.selfB, math.min(c.selfAlpha, 254)
        else
            if not c.players or ply:IsDormant() then return end
            if c.teamCheck and ply:Team() == me:Team() then return end

            mat = CHAMS_MATS[c.material] or CHAMS_MATS.flat
            r, g, b, alpha = c.visR, c.visG, c.visB, math.min(c.alpha, 254)   -- 254 is the ceiling

            if c.throughWalls then
                busy = true
                DrawCham(ply, mat, c.hidR, c.hidG, c.hidB, alpha, true)
                busy = false
            end
        end

        MV.ChamTint(mat, r, g, b)      -- after the walls pass, which tinted it its own colour
        render.SuppressEngineLighting(not CHAMS_LIT[mat])
        render.MaterialOverride(mat)
        render.SetColorModulation(r / 255, g / 255, b / 255)
        render.SetBlend(alpha / 255)
        active = true
    end)

    AddHook("PostPlayerDraw", "chams", function(ply)
        if not active then return end
        active = false

        Undo()
    end)

    -- safety net: whatever happens, nothing stays overridden past the opaque pass
    AddHook("PostDrawOpaqueRenderables", "chamsguard", function()
        if not active then return end
        active = false

        Undo()
    end)
end

-- custom player model ------------------------------------------------------------------------
-- The player entity keeps its real model (so the aimbots' bones stay the server's hitboxes); a
-- clientside model is bone-merged onto it and drawn in its place through RenderOverride. Swapping
-- the player's own model with SetModel does not hold: the engine re-applies the networked model
-- index, and gamemodes set it again on their own.
-- A player model shares the ValveBiped skeleton, so the merged one follows every animation.
-- RenderOverride runs inside the engine's draw, between PrePlayerDraw and PostPlayerDraw, so the
-- chams' material / colour override lands on the merged model too.
-- During a screengrab (IsHidden) the real model is drawn instead.
-- Lives in MV.mdl: the main chunk is at Lua's 200 locals.
MV.mdl = {
    ents = setmetatable({}, {__mode = "k"}),   -- ply -> the clientside model merged onto it
    list = nil,                                -- {label, path} of every installed player model
}

do
    local M = MV.mdl

    -- "kleiner", "models/player/kleiner.mdl" -> a model path, nil when it isn't installed
    -- (file.Exists, not util.IsValidModel: on the client that one is false for anything not
    -- precached yet, which is most models nobody on the server wears)
    -- A full disk path (C:\...\addons\x\models\player\a.mdl), backslashes and quotes are taken
    -- too: everything from "models/" on is the game path.
    function M.Resolve(s)
        if not isstring(s) then return nil end
        s = string.lower(string.Trim((string.gsub(s, "[\"']", ""))))
        s = string.gsub(s, "\\", "/")
        if s == "" then return nil end

        -- "models/" as a whole folder name only: ".../custommodels/models/..." must not cut at
        -- the "custommodels/" before it
        local at
        if string.StartWith(s, "models/") then
            at = 1
        else
            at = string.find(s, "/models/", 1, true)
            if at then at = at + 1 end
        end

        if at then
            s = string.sub(s, at)
        else
            s = string.lower(player_manager.TranslatePlayerModel(s))
        end

        if not string.EndsWith(s, ".mdl") then
            -- a folder: the model inside it (the first one, when there are several)
            local dir = string.TrimRight(s, "/")
            if file.IsDir(dir, "GAME") then
                local found = file.Find(dir .. "/*.mdl", "GAME")
                if found and found[1] then
                    table.sort(found)
                    s = dir .. "/" .. string.lower(found[1])
                    return s, s
                end
            end

            s = s .. ".mdl"
        end

        return file.Exists(s, "GAME") and s or nil, s
    end

    -- every model registered with player_manager (base game, mounted games, workshop), sorted
    function M.List()
        if M.list then return M.list end

        local out, seen = {}, {}
        for name, path in pairs(player_manager.AllValidModels()) do
            path = string.lower(path)
            if not seen[path] then
                seen[path] = true
                out[#out + 1] = {name, path}
            end
        end
        table.sort(out, function(a, b) return a[1] < b[1] end)

        M.list = out
        return out
    end

    -- label of a path (the player_manager name when it has one)
    function M.Label(path)
        for _, e in ipairs(M.List()) do
            if e[2] == path then return e[1] end
        end
        return string.GetFileFromFilename(path or "") or "?"
    end

    -- the next / previous installed model after cfg.model[key]
    function M.Step(key, dir)
        local list = M.List()
        if #list == 0 then return end

        local cur = 0
        for i, e in ipairs(list) do
            if e[2] == cfg.model[key] then cur = i break end
        end

        local i = cur + dir
        if i < 1 then i = #list elseif i > #list then i = 1 end
        cfg.model[key] = list[i][2]
    end

    -- the model ply should wear now, nil = its own
    local function Want(ply, me)
        if not ply:Alive() then return nil end
        local c = cfg.model

        if ply == me then
            return c.self and M.Resolve(c.selfModel) or nil
        end

        if not c.others then return nil end
        if c.teamCheck and IsValid(me) and ply:Team() == me:Team() then return nil end
        return M.Resolve(c.othersModel)
    end

    -- drawn instead of the player; self is the player
    local function Draw(self)
        local e = M.ents[self]

        if IsHidden() or not IsValid(e) then
            self:DrawModel()
            return
        end

        -- the merged model takes the bones of this frame
        self:SetupBones()
        e:DrawModel()
    end

    local function Drop(ply)
        local e = M.ents[ply]
        if IsValid(e) then e:Remove() end
        M.ents[ply] = nil

        if IsValid(ply) and ply.RenderOverride == Draw then ply.RenderOverride = nil end
    end

    function M.Apply(ply, me)
        local want = Want(ply, me)
        local e = M.ents[ply]

        if not want then
            if e or ply.RenderOverride == Draw then Drop(ply) end
            return
        end

        if IsValid(e) and e:GetParent() ~= ply then
            Drop(ply)
            e = nil
        end

        if not IsValid(e) then
            e = ClientsideModel(want, RENDERGROUP_OPAQUE)
            if not IsValid(e) then return end

            e:SetNoDraw(true)          -- only ever drawn from Draw
            e:SetParent(ply)
            e:AddEffects(EF_BONEMERGE + EF_BONEMERGE_FASTCULL)
            e:SetPos(ply:GetPos())
            M.ents[ply] = e
        elseif e:GetModel() ~= want then
            e:SetModel(want)
        end

        -- a gamemode or another addon may have put its own override in meanwhile: ours goes back
        if ply.RenderOverride ~= Draw then ply.RenderOverride = Draw end
    end

    -- every merged model gone, every player drawn by the engine again (unload)
    function M.Restore()
        for ply in pairs(M.ents) do Drop(ply) end
        for _, ply in ipairs(player.GetAll()) do
            if ply.RenderOverride == Draw then ply.RenderOverride = nil end
        end
        M.ents = setmetatable({}, {__mode = "k"})
    end

    -- a few times a second is enough: the override and the merged model stay put in between
    local nextApply = 0
    AddHook("Think", "model", function()
        local c = cfg.model
        if not (c.self or c.others or next(M.ents)) then return end

        local now = RealTime()
        if now < nextApply then return end
        nextApply = now + 0.2

        local me = LocalPlayer()
        for _, ply in ipairs(player.GetAll()) do M.Apply(ply, me) end

        -- players who left: their merged model would otherwise stay in the world
        for ply in pairs(M.ents) do
            if not IsValid(ply) then
                local e = M.ents[ply]
                if IsValid(e) then e:Remove() end
                M.ents[ply] = nil
            end
        end
    end)

    -- nyx_model self|others <name or path>; no argument lists the installed names
    -- result in the console and the chat (the console is easy to miss)
    function M.Say(ok, text)
        local col = ok and Color(149, 184, 6) or Color(255, 80, 80)
        MsgC(col, "[nyx] ", color_white, text .. "\n")
        chat.AddText(col, "[nyx] ", color_white, text)
    end
    local Say = M.Say

    -- The folder for your own models: addons/nyx_models (models/player + materials/models/player
    -- inside). Lua can't open Explorer, so its full path goes to the clipboard for Win+R.
    -- The install path comes from gameinfo.txt, which always sits in garrysmod/.
    function M.CopyFolder()
        local dir
        local ok, full = pcall(util.RelativePathToFull, "gameinfo.txt")
        if ok and isstring(full) and full ~= "" and full ~= "gameinfo.txt" then
            dir = string.gsub(full, "[/\\]gameinfo%.txt$", "") .. "\\addons\\nyx_models"
        else
            dir = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\GarrysMod\\garrysmod\\addons\\nyx_models"
        end
        dir = string.gsub(dir, "/", "\\")

        SetClipboardText(dir)
        M.Say(true, "copied: " .. dir)
        M.Say(true, "Win+R -> Ctrl+V -> Enter. Put models\\ and materials\\ inside, then restart GMod.")
    end

    -- Model scan: every .mdl under models/ the game can load (its VPKs, mounted games, workshop
    -- and server-downloaded .gma, folders in addons/), walked a few milliseconds per frame so a
    -- tree of tens of thousands of files doesn't freeze the game.
    M.scan = {all = {}, queue = nil, done = false, dirs = 0}

    function M.StartScan()
        local S = M.scan
        if S.queue then return end
        S.all, S.queue, S.done, S.dirs, S.seen = {}, {"models/"}, false, 0, {}
        M.findCache = nil
    end

    AddHook("Think", "modelscan", function()
        local S = M.scan
        if not S.queue then return end

        local stop = SysTime() + 0.003
        while #S.queue > 0 and SysTime() < stop do
            local dir = table.remove(S.queue)
            local files, dirs = file.Find(dir .. "*", "GAME")

            for _, f in ipairs(files or {}) do
                local p = string.lower(dir .. f)
                if string.EndsWith(p, ".mdl") and not S.seen[p] then
                    S.seen[p] = true
                    S.all[#S.all + 1] = p
                end
            end

            for _, d in ipairs(dirs or {}) do S.queue[#S.queue + 1] = dir .. d .. "/" end
            S.dirs = S.dirs + 1
        end

        if #S.queue == 0 then
            table.sort(S.all)
            S.queue, S.done, S.seen = nil, true, nil
            M.findCache = nil
        end
    end)

    -- a model that can be worn: in a player folder, and not first person arms or an animation base
    function M.IsPlayerish(p)
        if not (string.find(p, "/player/", 1, true) or string.find(p, "playermodel", 1, true)) then return false end
        local name = string.GetFileFromFilename(p)
        return not (string.find(name, "arms", 1, true) or string.find(name, "hands", 1, true)
            or string.StartWith(name, "c_") or string.StartWith(name, "anim_"))
    end

    -- scanned models whose path contains every word of query
    function M.Find(query, all)
        local key = query .. (all and "|a" or "|p")
        local fc = M.findCache
        if fc and fc.key == key then
            -- while the scan still grows the list, refilter four times a second, not every paint
            if fc.n == #M.scan.all or (not M.scan.done and RealTime() - fc.t < 0.25) then return fc.list end
        end

        local words = string.Explode(" ", string.lower(query))
        local out = {}

        for _, p in ipairs(M.scan.all) do
            if all or M.IsPlayerish(p) then
                local ok = true
                for _, w in ipairs(words) do
                    if w ~= "" and not string.find(p, w, 1, true) then ok = false break end
                end
                if ok then out[#out + 1] = p end
            end
        end

        M.findCache = {key = key, list = out, n = #M.scan.all, t = RealTime()}
        return out
    end

    -- The path is taken from the whole argument string, not args[2]: the console tokenizer
    -- splits quoted / Windows paths into pieces.
    concommand.Add("nyx_model", function(_, _, args, argStr)
        local which = string.lower(args[1] or "")
        local what = string.Trim(string.sub(argStr or "", #(args[1] or "") + 1))

        if which ~= "self" and which ~= "others" then
            MsgC(Color(149, 184, 6), "[nyx] ", color_white, "nyx_model self|others <name or models/...mdl>\n")
            for _, e in ipairs(M.List()) do print("  " .. e[1] .. "  " .. e[2]) end
            return
        end

        if what == "" then
            Say(true, which .. " model now: " .. tostring(cfg.model[which .. "Model"]) .. (cfg.model[which] and "" or " (off)"))
            return
        end

        local path, tried = M.Resolve(what)
        if not path then
            Say(false, "model not found: " .. tostring(tried or what) .. " (addons\\ folder: restart GMod after adding it)")
            return
        end

        cfg.model[which .. "Model"] = path
        cfg.model[which] = true
        Say(true, which .. " model: " .. path)
    end)
end

-- First person hands and weapon. The arms are a separate entity drawn from the gamemode's
-- PostDrawViewModel (bracketed by PreDrawPlayerHands / PostDrawPlayerHands), the weapon is the
-- viewmodel itself (PreDrawViewModel / PostDrawViewModel). The override is the same trick as for
-- the players: material, colour and blend set before the engine's own draw, undone after it.
-- None of these hooks may return a value: a value from PreDrawViewModel / PreDrawPlayerHands
-- cancels the draw, and one from PostDrawViewModel skips drawing the hands.
do
    local handsActive, weaponActive = false, false

    local function Begin()
        local c = cfg.chams

        local mat = CHAMS_MATS[c.handMaterial] or CHAMS_MATS.flat

        MV.ChamTint(mat, c.handR, c.handG, c.handB)
        render.SuppressEngineLighting(not CHAMS_LIT[mat])
        render.MaterialOverride(mat)
        render.SetColorModulation(c.handR / 255, c.handG / 255, c.handB / 255)
        render.SetBlend(math.min(c.handAlpha, 254) / 255)
    end

    local function Finish()
        render.SetBlend(1)
        render.SetColorModulation(1, 1, 1)
        render.MaterialOverride(nil)
        render.SuppressEngineLighting(false)
    end

    AddHook("PreDrawPlayerHands", "chams", function()
        if IsHidden() then return end

        local c = cfg.chams
        if c.enabled and c.hands then
            Begin()
            handsActive = true
        end
    end)

    AddHook("PostDrawPlayerHands", "chams", function()
        if not handsActive then return end

        handsActive = false
        Finish()
    end)

    AddHook("PreDrawViewModel", "chams", function()
        if IsHidden() then return end

        local c = cfg.chams
        if c.enabled and c.weapon then
            Begin()
            weaponActive = true
        end
    end)

    AddHook("PostDrawViewModel", "chams", function()
        if not weaponActive then return end

        weaponActive = false
        Finish()
    end)
end

-- ---------------------------------------------------------------------------
-- bullet tracers
-- ---------------------------------------------------------------------------

do
local tracers = {}               -- {from, to, born}
local tracerMat = Material("effects/laser1")
local lastBulletEvent = 0
local lastWep, lastClip = nil, 0

local function AddTracer(ply, src, dir, dist)
    local tr = util.TraceLine({
        start = src,
        endpos = src + dir * (dist and dist > 0 and dist or 56756),
        filter = ply,
        mask = MASK_SHOT,
    })

    -- start a bit in front of / below the eyes so it reads as coming from the gun
    local muzzle = src + realAng:Forward() * 14 + realAng:Right() * 6 - realAng:Up() * 6

    tracers[#tracers + 1] = {from = muzzle, to = tr.HitPos, born = CurTime()}
    if #tracers > 64 then table.remove(tracers, 1) end
end

-- bullets of your own weapon (predicted); shotguns get one tracer per pellet, capped
AddHook("EntityFireBullets", "tracers", function(ent, data)
    if not IsFirstTimePredicted() then return end

    local me = LocalPlayer()
    if not IsValid(me) or ent ~= me then return end

    lastBulletEvent = CurTime()
    NotifyShot()                       -- resolver: another shot at the current target

    if not cfg.tracers.enabled then return end

    local spread = data.Spread or vector_origin
    for i = 1, math.min(data.Num or 1, 8) do
        local dir = data.Dir
        if i > 1 or (data.Num or 1) > 1 then
            dir = (dir + Vector(
                math.Rand(-spread.x, spread.x),
                math.Rand(-spread.y, spread.y),
                math.Rand(-spread.z, spread.z)
            )):GetNormalized()
        end
        AddTracer(me, data.Src, dir, data.Distance)
    end
end)

-- fallback for weapons that don't go through EntityFireBullets on the client: a shot is
-- noticed when the clip drops, and the tracer follows the angle sent on the previous tick
TrackShots = function(ply, sentDir)
    if not cfg.tracers.enabled and not cfg.resolver.enabled then return end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then
        lastWep = nil
        return
    end

    local clip = wep:Clip1()
    if wep == lastWep and clip >= 0 and clip < lastClip and CurTime() - lastBulletEvent > 0.25 then
        lastBulletEvent = CurTime()
        NotifyShot()
        if cfg.tracers.enabled then AddTracer(ply, ply:GetShootPos(), sentDir) end
    end

    lastWep, lastClip = wep, clip
end

AddHook("PostDrawTranslucentRenderables", "tracers", function()
    if IsHidden() or #tracers == 0 then return end

    local t = cfg.tracers
    local now = CurTime()

    render.SetMaterial(tracerMat)

    for i = #tracers, 1, -1 do
        local tr = tracers[i]
        local age = now - tr.born

        if age > t.life then
            table.remove(tracers, i)
        else
            local fade = 1 - age / t.life
            render.DrawBeam(tr.from, tr.to, t.width, 0, 1, Color(t.r, t.g, t.b, 255 * fade))
        end
    end
end)

end   -- tracers

-- ---------------------------------------------------------------------------
-- taunt spam / interpolation / fake lag / t-pose / sequence / glow / killsay
-- ---------------------------------------------------------------------------

local TAUNTS = {
    {"Dance", "dance"}, {"Robot", "robot"}, {"Muscle", "muscle"}, {"Laugh", "laugh"},
    {"Cheer", "cheer"}, {"Wave", "wave"}, {"Bow", "bow"}, {"Salute", "salute"},
    {"Zombie", "zombie"}, {"Agree", "agree"}, {"Disagree", "disagree"}, {"Forward", "forward"},
    {"Group", "group"}, {"Halt", "halt"}, {"Becon", "becon"}, {"Persistence", "pers"},
}

local tauntNext = 0

-- `act <name>` is the same command as the context menu's gestures
AddHook("Think", "taunt", function()
    local t = cfg.taunt
    if not t.enabled then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local now = CurTime()
    if now < tauntNext then return end
    tauntNext = now + math.max(t.interval, 0.05)

    RunConsoleCommand("act", t.name)
end)

-- network convars: interpolation and fake lag. The original values are remembered the first time
-- a convar is touched and put back whenever the setting goes back to default / off.
local NET = {}

do
local netOrig = {}
local netTouched = {}
local netSig, netNext = nil, 0

local function SetNetVar(name, value)
    local cv = GetConVar(name)
    if not cv then return end

    if netOrig[name] == nil then netOrig[name] = cv:GetString() end
    netTouched[name] = true

    RunConsoleCommand(name, tostring(value))
end

local function RestoreNetVars()
    for name in pairs(netTouched) do
        if netOrig[name] ~= nil then RunConsoleCommand(name, netOrig[name]) end
    end
    netTouched = {}
end

AddHook("Think", "netvars", function()
    local now = CurTime()
    if now < netNext then return end
    netNext = now + 0.5

    local i = cfg.interp
    local sig = i.mode
    if sig == netSig then return end
    netSig = sig

    RestoreNetVars()

    -- The effective lerp is max(cl_interp, cl_interp_ratio / cl_updaterate), and the server clamps
    -- the ratio to sv_client_min_interp_ratio. A ratio of 0 is invalid, so the smallest lerp is
    -- reached with interp 0, ratio 1 and the highest update rate.
    if i.mode == "low" or i.mode == "off" then
        SetNetVar("cl_interp", 0)
        SetNetVar("cl_interp_ratio", 1)
        SetNetVar("cl_updaterate", 100)
    end

    -- "off" additionally stops the client from interpolating entities at all (they snap from
    -- tick to tick), so everything moves exactly at the server tick rate
    if i.mode == "off" then
        SetNetVar("cl_interpolate", 0)
    elseif i.mode == "smooth" then
        SetNetVar("cl_interp_ratio", 3)
    end
end)

local function CV(name)
    local cv = GetConVar(name)
    return cv and cv:GetString() or "?"
end

-- one short line for the menu, read straight from the convars
local function NetStatusA()
    return string.format("interp %s  ratio %s  upd %s", CV("cl_interp"), CV("cl_interp_ratio"), CV("cl_updaterate"))
end

NET.Restore = RestoreNetVars
NET.Status = NetStatusA
end   -- network convars

-- removals: the parts that are not in the view code (HUD parts, convars, ragdolls). Camera shake,
-- punch, viewmodel bob and hiding the viewmodel are handled in CalcView / CalcViewModelView.
local REM = {}

do
-- cfg.removals key -> HUD elements the game draws
local HUD_PARTS = {
    hudDamage    = {"CHudDamageIndicator"},
    hudCrosshair = {"CHudCrosshair"},
    hudHealth    = {"CHudHealth", "CHudBattery"},
    hudAmmo      = {"CHudAmmo", "CHudSecondaryAmmo"},
    hudWeapons   = {"CHudWeaponSelection"},
    hudPickup    = {"CHudHistoryResource"},
    hudKillfeed  = {"CHudDeathNotice"},
}

local hudKey = {}
for key, names in pairs(HUD_PARTS) do
    for _, n in ipairs(names) do hudKey[n] = key end
end

AddHook("HUDShouldDraw", "removals", function(name)
    local key = hudKey[name]
    if key and cfg.removals.enabled and cfg.removals[key] then return false end
end)

-- convars: [cfg.removals key] = {convar, value while removed}
local CONVARS = {
    motionBlur = {"mat_motion_blur_enabled", "0"},
    decals     = {"mp_decals", "0"},
    shells     = {"cl_ejectbrass", "0"},
}

local origValue = {}        -- convar -> value it had before we touched it
local applied = {}          -- convar -> true while our value is the one set

local function ApplyConvars()
    for key, def in pairs(CONVARS) do
        local name, value = def[1], def[2]
        local cv = GetConVar(name)

        if cv then
            if cfg.removals.enabled and cfg.removals[key] then
                if not applied[name] then
                    origValue[name] = cv:GetString()
                    applied[name] = true
                    RunConsoleCommand(name, value)

                    -- the decals already on the walls go as well
                    if key == "decals" then RunConsoleCommand("r_cleardecals") end
                end
            elseif applied[name] then
                applied[name] = nil
                RunConsoleCommand(name, origValue[name] or "1")
            end
        end
    end
end

-- ragdolls are only hidden (NoDraw), and shown again when the switch goes off
local hiddenRagdolls = {}
local RAGDOLL_CLASSES = {"class C_ClientRagdoll", "prop_ragdoll"}

local function ShowRagdolls()
    for ent in pairs(hiddenRagdolls) do
        if IsValid(ent) then ent:SetNoDraw(false) end
    end
    hiddenRagdolls = {}
end

local nextRemovals = 0

AddHook("Think", "removals", function()
    local now = CurTime()
    if now < nextRemovals then return end
    nextRemovals = now + 0.25

    ApplyConvars()

    if cfg.removals.enabled and cfg.removals.ragdolls then
        for _, class in ipairs(RAGDOLL_CLASSES) do
            for _, ent in ipairs(ents.FindByClass(class)) do
                if not hiddenRagdolls[ent] then
                    hiddenRagdolls[ent] = true
                    ent:SetNoDraw(true)
                end
            end
        end
    elseif next(hiddenRagdolls) then
        ShowRagdolls()
    end
end)

-- everything we changed goes back (unload)
function REM.Restore()
    for key, def in pairs(CONVARS) do
        local name = def[1]

        if applied[name] then
            applied[name] = nil
            RunConsoleCommand(name, origValue[name] or "1")
        end
    end

    ShowRagdolls()
end
end   -- removals

-- resolver, drawn side: the target keeps the brute-forced angle on screen too, and its pose is
-- fixed right before the model is drawn each frame. No return value: returning true here would
-- cancel the draw.
AddHook("PrePlayerDraw", "resolver", function(ply)
    ApplyResolver(ply)
end)

-- animation overrides (client side only, nobody else sees them): t-pose for everybody and a
-- fixed sequence for yourself
AddHook("CalcMainActivity", "animation", function(ply, velocity)
    local me = LocalPlayer()

    local t = cfg.tpose
    if t.enabled and (ply ~= me or t.includeSelf) then
        local seq = ply:LookupSequence("reference")
        if not seq or seq < 0 then seq = ply:LookupSequence("ref_pose") end
        if seq and seq >= 0 then return -1, seq end
    end

    if cfg.seq.enabled and ply == me then
        local last = math.max(ply:GetSequenceCount() - 1, 0)
        return -1, math.Clamp(math.floor(cfg.seq.index), 0, last)
    end
end)

-- player glow (others, and yourself in third person / free camera)
AddHook("PreDrawHalos", "playerglow", function()
    local g = cfg.glow
    if IsHidden() or not (g.enabled or g.self) then return end

    local me = LocalPlayer()
    if not IsValid(me) then return end

    if g.enabled then
        local list = {}

        for _, v in ipairs(player.GetAll()) do
            if v ~= me and v:Alive() and not v:IsDormant()
                and not (g.teamCheck and v:Team() == me:Team()) then
                list[#list + 1] = v
            end
        end

        if #list > 0 then
            halo.Add(list, Color(g.r, g.g, g.b), g.width, g.width, 2, true, g.throughWalls)
        end
    end

    if g.self and me:Alive() and (cfg.view.thirdperson or freeActive) then
        halo.Add({me}, Color(g.selfR, g.selfG, g.selfB), g.width, g.width, 2, true, false)
    end
end)

-- kill effects
-- (own block as well; the menu needs KFX.Preview, and `alive` is cleared on unload so the ragdoll
-- render overrides that are already set stop doing anything)
local KFX = {alive = true}

do
local fxList = {}                    -- effects that are playing
local streak, lastKillTime = 0, 0
local lastVictim, lastVictimTime = nil, 0

local matGlow  = Material("sprites/glow04_noz")
local matBeam  = Material("effects/laser1")
local matShiny = Material("models/shiny")
local matWhite = Material("models/debug/debugwhite")

surface.CreateFont("NyxKillFx", {font = "Verdana", size = 30, weight = 800, antialias = true})
surface.CreateFont("NyxKillFxSmall", {font = "Verdana", size = 15, weight = 600, antialias = true})

local STREAK_TEXT = {"KILL", "DOUBLE KILL", "TRIPLE KILL", "MULTI KILL", "MEGA KILL", "ULTRA KILL", "MONSTER KILL"}

-- colour of element i; the rainbow shifts with time and with the element
local function FxColor(i, a)
    local k = cfg.killfx

    if k.rainbow then
        local c = HSVToColor((CurTime() * 140 + (i or 0) * 37) % 360, 0.85, 1)
        c.a = a
        return c
    end

    return Color(k.r, k.g, k.b, a)
end

-- the ragdoll of the victim is painted by a render override: it only draws differently while no
-- screengrab is being taken, and nothing is written into the entity itself
local function RagdollRender(self)
    local fx = self.nyxFx

    if not KFX.alive or not fx or IsHidden() then
        self:DrawModel()
        return
    end

    local age = CurTime() - fx.born
    local blend = 1

    if fx.mode == "dissolve" then
        blend = math.max(0, 1 - age / 1.6)
        if blend <= 0 then return end
    end

    local r, g, b = fx.r, fx.g, fx.b
    if fx.tinted and cfg.killfx.rainbow then
        local c = HSVToColor((CurTime() * 140) % 360, 0.85, 1)
        r, g, b = c.r, c.g, c.b
    end

    -- pulse: the colour breathes between dim and full
    if fx.mode == "pulse" then
        local p = 0.3 + 0.7 * math.abs(math.sin(age * 4))
        r, g, b = r * p, g * p, b * p
    end

    MV.ChamTint(fx.mat, r, g, b)
    if fx.flat then render.SuppressEngineLighting(true) end
    render.MaterialOverride(fx.mat)
    render.SetColorModulation(r / 255, g / 255, b / 255)
    render.SetBlend(blend)

    self:DrawModel()

    render.SetBlend(1)
    render.SetColorModulation(1, 1, 1)
    render.MaterialOverride(nil)
    if fx.flat then render.SuppressEngineLighting(false) end
end

-- the ragdoll shows up a moment after the death, so it is looked for a few times
local function PaintRagdoll(victim)
    local k = cfg.killfx
    if k.ragdoll == "off" or not IsValid(victim) then return end

    local mode = k.ragdoll
    local fx = {mode = mode, mat = matShiny, r = k.r, g = k.g, b = k.b}
    local M = KFX.mats

    if mode == "gold" then
        fx.r, fx.g, fx.b = 255, 190, 40
    elseif mode == "ice" then
        fx.r, fx.g, fx.b = 110, 190, 255
    elseif mode == "dissolve" then
        fx.mat, fx.r, fx.g, fx.b = matWhite, 255, 255, 255
    elseif mode == "neon" then
        fx.mat, fx.flat = M.wire, true
    elseif mode == "chrome" then
        fx.mat, fx.r, fx.g, fx.b = M.chrome, 255, 255, 255
    elseif mode == "energy" then
        fx.mat, fx.flat, fx.r, fx.g, fx.b = M.energy, true, 255, 255, 255
    elseif mode == "void" then
        fx.mat, fx.flat, fx.r, fx.g, fx.b = matWhite, true, 6, 6, 10
    elseif mode == "selfillum" then
        fx.mat = CHAMS_MATS.selfillum or matShiny
    end

    -- the modes that use the menu colour also follow the rainbow
    fx.tinted = mode == "color" or mode == "neon" or mode == "pulse" or mode == "selfillum"

    local tries = 0

    local function Try()
        tries = tries + 1

        local rag = IsValid(victim) and victim.GetRagdollEntity and victim:GetRagdollEntity() or nil

        if IsValid(rag) then
            fx.born = CurTime()
            rag.nyxFx = fx

            if mode == "dissolve" then rag:SetRenderMode(RENDERMODE_TRANSCOLOR) end
            rag.RenderOverride = RagdollRender
        elseif tries < 14 then
            timer.Simple(0.05, Try)
        end
    end

    Try()
end

-- one effect: everything random is rolled here, drawing only replays it
local function Spawn(center, ground, name, label, victim)
    local k = cfg.killfx
    local s = k.scale

    local e = {pos = center, ground = ground, born = CurTime(), name = name, label = label,
        seed = math.Rand(0, 6.28), parts = {}, bolts = {}}

    if k.burst then
        for i = 1, math.Clamp(math.floor(k.count), 4, 120) do
            local ang = math.Rand(0, math.pi * 2)
            local up = math.Rand(0.35, 1)
            local spd = math.Rand(70, 230) * s

            e.parts[i] = {
                vel = Vector(math.cos(ang) * spd * (1.1 - up * 0.5), math.sin(ang) * spd * (1.1 - up * 0.5),
                    math.Rand(140, 330) * up * s),
                size = math.Rand(3, 8) * s,
            }
        end
    end

    if k.bolt then
        for b = 1, 3 do
            local top = center + Vector(math.Rand(-45, 45), math.Rand(-45, 45), 520)
            local pts = {top}
            local segs = 9

            for n = 1, segs - 1 do
                local f = n / segs
                local base = LerpVector(f, top, center)
                pts[#pts + 1] = base + Vector(math.Rand(-30, 30), math.Rand(-30, 30), 0) * (1 - f * 0.6)
            end

            pts[#pts + 1] = center
            e.bolts[b] = pts
        end
    end

    KFX.SpawnExtra(e, k, victim)

    fxList[#fxList + 1] = e
    if #fxList > 8 then
        KFX.Free(fxList[1])
        table.remove(fxList, 1)
    end

    if k.sparks then
        local ed = EffectData()
        ed:SetOrigin(center)
        ed:SetScale(1)
        ed:SetMagnitude(1)
        util.Effect("cball_explode", ed)
    end

    if k.sound ~= "off" then surface.PlaySound(k.sound) end
end

-- a kill of yours; victim may be missing (the kill feed only has a name)
local function Trigger(victim, name)
    local k = cfg.killfx
    if not k.enabled then return end

    local now = CurTime()

    -- the game event and the kill feed both report the same kill
    if lastVictim == name and now - lastVictimTime < 0.6 then return end
    lastVictim, lastVictimTime = name, now

    if now - lastKillTime < 4 then streak = streak + 1 else streak = 1 end
    lastKillTime = now

    local origin
    if IsValid(victim) then
        origin = victim:GetPos()
    else
        local me = LocalPlayer()
        if not IsValid(me) then return end
        origin = me:GetEyeTrace().HitPos
    end

    local ground = util.TraceLine({
        start = origin + Vector(0, 0, 8),
        endpos = origin - Vector(0, 0, 64),
        mask = MASK_SOLID_BRUSHONLY,
    }).HitPos

    Spawn(origin + Vector(0, 0, 36), ground, name, STREAK_TEXT[math.min(streak, #STREAK_TEXT)], victim)
    PaintRagdoll(victim)
end

-- plays the whole thing 300 units ahead of you (the menu button)
function KFX.Preview()
    local me = LocalPlayer()
    if not IsValid(me) then return end

    local tr = util.TraceLine({
        start = me:EyePos(),
        endpos = me:EyePos() + me:EyeAngles():Forward() * 300,
        filter = me,
    })

    local ground = util.TraceLine({
        start = tr.HitPos + Vector(0, 0, 16),
        endpos = tr.HitPos - Vector(0, 0, 400),
        mask = MASK_SOLID_BRUSHONLY,
    }).HitPos

    -- the ghost needs a model: yours stands in for the victim
    Spawn(ground + Vector(0, 0, 36), ground, "preview", STREAK_TEXT[math.random(#STREAK_TEXT)], me)
end

AddHook("player_death", "killfx", function(data)
    local me = LocalPlayer()
    if not IsValid(me) then return end
    if data.attacker ~= me:UserID() or data.userid == data.attacker then return end

    local victim = Player(data.userid)
    Trigger(victim, IsValid(victim) and victim:Nick() or "?")
end)

AddHook("AddDeathNotice", "killfx", function(attacker, attackerTeam, inflictor, victimName)
    local me = LocalPlayer()
    if not IsValid(me) then return end

    local nick = me:Nick()
    if attacker ~= nick or victimName == nick then return end

    local victim
    for _, p in ipairs(player.GetAll()) do
        if p:Nick() == victimName then victim = p break end
    end

    Trigger(victim, victimName)
end)

-- extra effects ------------------------------------------------------------------------------
-- Everything below lives on KFX instead of new locals: this block shares the main chunk's 200.

KFX.mats = {
    white  = Material("vgui/white"),
    wire   = Material("models/wireframe"),
    chrome = Material("debug/env_cubemap_model"),
    energy = Material("models/props_combine/portalball001_sheet"),
}

surface.CreateFont("NyxKillFxBig", {font = "Verdana", size = 58, weight = 900, antialias = true})

-- rolls everything random of the extra effects into e (drawing only replays it)
function KFX.SpawnExtra(e, k, victim)
    local s = k.scale
    local ground = e.ground

    if k.vortex then
        e.vortex = {}
        for i = 1, 40 do
            e.vortex[i] = {a = math.Rand(0, math.pi * 2), r = math.Rand(40, 95) * s, h = math.Rand(0, 40) * s,
                spd = math.Rand(4, 7), size = math.Rand(3, 7) * s}
        end
    end

    if k.fireworks then
        e.rockets = {}
        for i = 1, 3 do
            local stars = {}
            for n = 1, 28 do stars[n] = VectorRand():GetNormalized() * math.Rand(90, 150) * s end

            e.rockets[i] = {
                top = ground + Vector(math.Rand(-90, 90) * s, math.Rand(-90, 90) * s, math.Rand(240, 380) * s),
                fly = math.Rand(0.45, 0.7), stars = stars, hue = math.Rand(0, 360),
            }
        end
    end

    if k.confetti then
        e.confetti = {}
        for i = 1, 70 do
            local ang = math.Rand(0, math.pi * 2)
            local spd = math.Rand(60, 200) * s

            e.confetti[i] = {
                vel = Vector(math.cos(ang) * spd, math.sin(ang) * spd, math.Rand(200, 380) * s),
                col = HSVToColor(math.Rand(0, 360), 0.8, 1),
                spin = math.Rand(-8, 8), ph = math.Rand(0, 6.28),
                w = math.Rand(3, 5) * s, h = math.Rand(1.5, 2.5) * s,
            }
        end
    end

    -- a client-side copy of the victim's model, drawn by hand (SetNoDraw) so screengrabs skip it
    if k.ghost and IsValid(victim) and victim:GetModel() then
        local m = ClientsideModel(victim:GetModel(), RENDERGROUP_TRANSLUCENT)

        if IsValid(m) then
            m:SetNoDraw(true)
            m:SetPos(ground)
            m:SetAngles(Angle(0, victim:EyeAngles().y, 0))
            m:SetSkin(victim:GetSkin())
            for _, bg in ipairs(victim:GetBodyGroups() or {}) do m:SetBodygroup(bg.id, victim:GetBodygroup(bg.id)) end

            local seq = m:LookupSequence("idle_all_01")
            if seq and seq > 0 then m:ResetSequence(seq) end

            e.ghost = m
        end
    end

    if k.shake then util.ScreenShake(LocalPlayer():GetPos(), 6 * s, 30, 0.45, 2000) end
    if k.scorch then util.Decal("Scorch", ground + Vector(0, 0, 8), ground - Vector(0, 0, 16)) end
end

-- whatever an effect holds outside Lua (the ghost model) goes away with it
function KFX.Free(e)
    if e and IsValid(e.ghost) then e.ghost:Remove() end
    if e then e.ghost = nil end
end

function KFX.Cleanup()
    for i = #fxList, 1, -1 do
        KFX.Free(fxList[i])
        fxList[i] = nil
    end
end

function KFX.Draw3DExtra(e, t, k)
    local life, s = k.life, k.scale
    local fade = math.Clamp(1 - t / life, 0, 1)
    local ground = e.ground

    -- pillar: shoots up in 0.15 s, then thins out
    if k.pillar then
        local top = ground + Vector(0, 0, 700 * s * math.min(1, t / 0.15))
        local w = 46 * s * fade * (0.8 + 0.2 * math.sin(t * 30))

        render.SetMaterial(matBeam)
        render.DrawBeam(ground, top, w, 0, 4, FxColor(0, 200 * fade))
        render.DrawBeam(ground, top, w * 0.3, 0, 4, Color(255, 255, 255, 230 * fade))

        render.SetMaterial(matGlow)
        render.DrawSprite(ground + Vector(0, 0, 4), 120 * s * fade, 120 * s * fade, FxColor(1, 255 * fade))
    end

    -- vortex: the radius shrinks while the sparks climb
    if e.vortex then
        local f = math.Clamp(t / life, 0, 1)
        render.SetMaterial(matGlow)

        for n, p in ipairs(e.vortex) do
            local r = p.r * (1 - f) ^ 1.5
            local a = p.a + t * p.spd
            local pp = ground + Vector(math.cos(a) * r, math.sin(a) * r, p.h + t * 150 * s)
            render.DrawSprite(pp, p.size, p.size, FxColor(n, 255 * fade))
        end
    end

    -- dome: eases out to full size, turning slowly
    if k.dome then
        local R = 150 * s * (1 - (1 - math.min(1, t / (life * 0.6))) ^ 3)
        local col = FxColor(2, 180 * fade)
        local turn = t * 0.6

        render.SetMaterial(matBeam)

        for lat = 0, 4 do
            local el = lat / 5 * math.pi / 2
            local rr, z = math.cos(el) * R, math.sin(el) * R
            local prev

            for n = 0, 24 do
                local a = n / 24 * math.pi * 2 + turn
                local p = ground + Vector(math.cos(a) * rr, math.sin(a) * rr, z)
                if prev then render.DrawBeam(prev, p, 3 * s, 0, 1, col) end
                prev = p
            end
        end

        for m = 0, 7 do
            local a = m / 8 * math.pi * 2 + turn
            local prev

            for n = 0, 8 do
                local el = n / 8 * math.pi / 2
                local p = ground + Vector(math.cos(a) * math.cos(el) * R, math.sin(a) * math.cos(el) * R, math.sin(el) * R)
                if prev then render.DrawBeam(prev, p, 3 * s, 0, 1, col) end
                prev = p
            end
        end
    end

    -- fireworks: a rocket with a short trail, then a sphere of stars that drags and drops
    if e.rockets then
        for i, r in ipairs(e.rockets) do
            if t < r.fly then
                local f = 1 - (1 - t / r.fly) ^ 2
                local p = LerpVector(f, ground, r.top)

                render.SetMaterial(matBeam)
                render.DrawBeam(LerpVector(math.max(0, f - 0.15), ground, r.top), p, 4 * s, 0, 1, Color(255, 200, 120, 200))
                render.SetMaterial(matGlow)
                render.DrawSprite(p, 14 * s, 14 * s, Color(255, 230, 180, 255))
            else
                local bt = t - r.fly
                local a = math.Clamp(1 - bt / math.max(life - r.fly, 0.1), 0, 1)

                if a > 0 then
                    local d = (1 - math.exp(-3 * bt)) / 3
                    render.SetMaterial(matGlow)

                    for n, v in ipairs(r.stars) do
                        local pp = r.top + v * d - Vector(0, 0, 40 * bt * bt)
                        local c = k.rainbow and FxColor(n + i * 5, 255) or HSVToColor((r.hue + n * 3) % 360, 0.7, 1)
                        c.a = 255 * a
                        render.DrawSprite(pp, 7 * s, 7 * s, c)
                    end

                    if bt < 0.15 then
                        local fl = 160 * s * (1 - bt / 0.15)
                        render.DrawSprite(r.top, fl, fl, Color(255, 255, 255, 255))
                    end
                end
            end
        end
    end

    -- confetti: drag on the throw, a slow sink, a sideways flutter, the quad flipping as it turns
    if e.confetti then
        local d = (1 - math.exp(-2.5 * t)) / 2.5
        local eye = EyePos()

        render.SetMaterial(KFX.mats.white)

        for _, c in ipairs(e.confetti) do
            local pp = e.pos + Vector(c.vel.x * d + math.sin(t * 5 + c.ph) * 8 * s, c.vel.y * d, c.vel.z * d - 70 * t * s)
            pp.z = math.max(pp.z, ground.z + 1)

            render.DrawQuadEasy(pp, (eye - pp):GetNormalized(), c.w,
                c.h * math.abs(math.cos(t * c.spin + c.ph)) + 0.3,
                Color(c.col.r, c.col.g, c.col.b, 255 * fade), (t * c.spin * 57) % 360)
        end
    end

    -- ghost: flat-lit, see-through, rising and bobbing
    if IsValid(e.ghost) then
        local m = e.ghost
        m:SetPos(ground + Vector(0, 0, t * 45 * s + math.sin(t * 3) * 3))
        m:FrameAdvance()
        m:SetupBones()

        local c = FxColor(3, 255)
        render.SuppressEngineLighting(true)
        render.MaterialOverride(matWhite)
        render.SetColorModulation(c.r / 255, c.g / 255, c.b / 255)
        render.SetBlend(0.45 * fade)

        m:DrawModel()

        render.SetBlend(1)
        render.SetColorModulation(1, 1, 1)
        render.MaterialOverride(nil)
        render.SuppressEngineLighting(false)
    end
end

-- newest: only the latest kill gets the banner, so two of them never overlap
function KFX.Draw2DExtra(e, t, k, sw, sh, newest)
    local s = k.scale

    -- hitmarker: four strokes around the crosshair, pushed outward as they fade
    if k.hitmarker and t < 0.5 then
        local a = 1 - t / 0.5
        local len = 12 * s
        local d = (8 + t * 40) * s + len / 2

        draw.NoTexture()

        for i = 0, 3 do
            local deg = 45 + i * 90
            local x = sw / 2 + math.cos(math.rad(deg)) * d
            local y = sh / 2 + math.sin(math.rad(deg)) * d
            local c = FxColor(i, 255 * a)

            surface.SetDrawColor(0, 0, 0, 200 * a)
            surface.DrawTexturedRectRotated(x, y, len + 2, 4 * s, -deg)
            surface.SetDrawColor(c.r, c.g, c.b, 255 * a)
            surface.DrawTexturedRectRotated(x, y, len, 2 * s, -deg)
        end
    end

    -- banner: pops in a little oversized, settles, fades out at the end
    if k.banner and newest and t < k.life then
        local a = math.Clamp(1 - (t / k.life) ^ 3, 0, 1)
        local pop = 1 + 0.4 * math.max(0, 1 - t / 0.15)
        local y = sh * 0.22

        local m = Matrix()
        m:Translate(Vector(sw / 2, y, 0))
        m:Scale(Vector(pop, pop, 1))

        cam.PushModelMatrix(m)
        draw.SimpleTextOutlined(e.label, "NyxKillFxBig", 0, 0, FxColor(1, 255 * a),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 3, Color(0, 0, 0, 200 * a))
        cam.PopModelMatrix()

        draw.SimpleTextOutlined(e.name, "NyxKillFxSmall", sw / 2, y + 36, Color(255, 255, 255, 220 * a),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200 * a))
    end
end

local function Draw3D(e, t, k)
    local life = k.life
    local fade = math.Clamp(1 - t / life, 0, 1)
    local pos, ground = e.pos, e.ground
    local s = k.scale

    -- shockwave rings on the floor
    if k.ring then
        render.SetMaterial(matBeam)

        for j = 0, 1 do
            local rt = t - j * 0.18
            local a = math.Clamp(1 - rt / (life * 0.75), 0, 1)

            if rt > 0 and a > 0 then
                local radius = rt * 240 * s
                local col = FxColor(j * 3, 255 * a)
                local seg = 36
                local prev

                for n = 0, seg do
                    local ang = n / seg * math.pi * 2
                    local p = ground + Vector(math.cos(ang) * radius, math.sin(ang) * radius, 2)

                    if prev then render.DrawBeam(prev, p, 5 * s, 0, 1, col) end
                    prev = p
                end
            end
        end
    end

    -- lightning: flickers for the first half second
    if k.bolt and t < 0.55 then
        local a = (1 - t / 0.55) * (0.55 + 0.45 * math.sin(t * 95 + e.seed))

        render.SetMaterial(matBeam)

        for _, pts in ipairs(e.bolts) do
            for n = 1, #pts - 1 do
                render.DrawBeam(pts[n], pts[n + 1], 14 * s, 0, 1, FxColor(n, 200 * a))
                render.DrawBeam(pts[n], pts[n + 1], 4 * s, 0, 1, Color(255, 255, 255, 255 * a))
            end
        end

        render.SetMaterial(matGlow)
        render.DrawSprite(pos, 150 * s * a, 150 * s * a, FxColor(0, 255 * a))
    end

    -- sparks flying out, falling back down
    if k.burst then
        render.SetMaterial(matGlow)

        for n, p in ipairs(e.parts) do
            local pp = pos + p.vel * t
            pp.z = math.max(pp.z - 220 * t * t, ground.z + 1)

            local size = p.size * (1 - 0.6 * (t / life)) * 2
            render.DrawSprite(pp, size, size, FxColor(n, 255 * fade))
        end
    end

    -- orbs winding upward
    if k.souls then
        render.SetMaterial(matGlow)

        for n = 1, 6 do
            local ph = n * 1.1
            local pp = pos + Vector(math.cos(t * 2.2 + ph) * 16, math.sin(t * 2.2 + ph) * 16, t * 60 + n * 5)
            local size = 16 * (1 - 0.5 * t / life) * s

            render.DrawSprite(pp, size, size, FxColor(n * 2, 220 * fade))
        end
    end
end

AddHook("PostDrawTranslucentRenderables", "killfx", function(depth, skybox)
    if skybox or #fxList == 0 or IsHidden() then return end

    local k = cfg.killfx
    local now = CurTime()

    for i = #fxList, 1, -1 do
        local e = fxList[i]
        local t = now - e.born

        if t > k.life then
            KFX.Free(e)
            table.remove(fxList, i)
        else
            Draw3D(e, t, k)
            KFX.Draw3DExtra(e, t, k)
        end
    end
end)

AddHook("HUDPaint", "killfx", function()
    if #fxList == 0 or IsHidden() then return end

    local k = cfg.killfx
    local now = CurTime()
    local sw, sh = ScrW(), ScrH()

    for i, e in ipairs(fxList) do
        local t = now - e.born

        KFX.Draw2DExtra(e, t, k, sw, sh, i == #fxList)

        -- the screen edges light up and fade
        if k.flash and t < 0.45 then
            local a = 1 - t / 0.45

            for n = 0, 23 do
                local band = a * (1 - n / 24) ^ 2 * 110
                local col = FxColor(0, band)

                surface.SetDrawColor(col.r, col.g, col.b, band)
                surface.DrawRect(0, n * 6, sw, 6)
                surface.DrawRect(0, sh - (n + 1) * 6, sw, 6)
                surface.DrawRect(n * 6, 0, 6, sh)
                surface.DrawRect(sw - (n + 1) * 6, 0, 6, sh)
            end
        end

        if k.text and t < k.life then
            local sp = (e.pos + Vector(0, 0, 40 + t * 40)):ToScreen()

            if sp.visible then
                local a = 255 * math.Clamp(1 - (t / k.life) ^ 2, 0, 1)

                draw.SimpleTextOutlined(e.label, "NyxKillFx", sp.x, sp.y, FxColor(1, a),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, a))
                draw.SimpleTextOutlined(e.name, "NyxKillFxSmall", sp.x, sp.y + 2, Color(255, 255, 255, a),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, a))
            end
        end
    end
end)
end   -- kill effects

-- killsay
-- killsay lives in its own block (Lua allows 200 locals per chunk); the menu only needs KS.Status
local KS = {}

do
local KILLSAY = {
    english = {
        "{name}, ez.",
        "Sit down, {name}.",
        "{name} just got deleted.",
        "Nice try, {name}.",
        "Better luck next time, {name}.",
        "{name}, did you even see me?",
        "Thanks for the free kill, {name}.",
    },
    russian = {
        "{name}, \208\184\208\183\208\184.",
        "\208\161\209\143\208\180\209\140, {name}.",
        "{name}, \209\141\209\130\208\190 \208\177\209\139\208\187\208\190 \209\129\208\187\208\184\209\136\208\186\208\190\208\188 \208\191\209\128\208\190\209\129\209\130\208\190.",
        "\208\155\208\190\208\178\208\184 \209\128\208\181\209\129\208\191\208\176\209\131\208\189, {name}.",
        "{name}, \209\131\208\180\208\176\209\135\208\184 \208\178 \209\129\208\187\208\181\208\180\209\131\209\142\209\137\208\184\208\185 \209\128\208\176\208\183.",
    },
}

local killsayLast = 0
local killsayInfo = "no kills yet"

-- two independent sources report a kill (the game event and the kill feed); whichever comes
-- first wins, the other one inside the same half second is ignored
local function DoKillsay(victimName)
    local k = cfg.killsay
    if not k.enabled then return end

    local now = CurTime()
    if now - killsayLast < 0.5 then return end
    killsayLast = now

    local pool = {}
    if k.set == "custom" then
        if k.custom and k.custom ~= "" then pool[1] = k.custom end
    else
        if k.set ~= "russian" then table.Add(pool, KILLSAY.english) end
        if k.set ~= "english" then table.Add(pool, KILLSAY.russian) end
    end

    if #pool == 0 then
        killsayInfo = "empty: set text with nyx_killsay"
        return
    end

    local name = tostring(victimName or "?")
    local line = pool[math.random(#pool)]:gsub("{name}", function() return name end)

    killsayInfo = "last kill: " .. name

    timer.Create(ID .. "killsay", math.max(k.delay, 0), 1, function()
        RunConsoleCommand("say", line)
    end)
end

gameevent.Listen("player_death")

-- game event: attacker / victim as user ids
AddHook("player_death", "killsay", function(data)
    local me = LocalPlayer()
    if not IsValid(me) then return end
    if data.attacker ~= me:UserID() or data.userid == data.attacker then return end

    local victim = Player(data.userid)
    DoKillsay(IsValid(victim) and victim:Nick() or "?")
end)

-- kill feed: attacker / victim as names (covers servers that don't forward the game event)
AddHook("AddDeathNotice", "killsay", function(attacker, attackerTeam, inflictor, victim, victimTeam)
    local me = LocalPlayer()
    if not IsValid(me) then return end

    local nick = me:Nick()
    if attacker == nick and victim ~= nick then DoKillsay(victim) end
end)

-- custom line: nyx_killsay <text>, {name} is replaced with the victim's name
concommand.Add("nyx_killsay", function(ply, cmd, args, argStr)
    cfg.killsay.custom = argStr or ""
    cfg.killsay.set = "custom"
    killsayInfo = "custom text set"
end)

local function KillsayStatus()
    return killsayInfo
end

KS.Status = KillsayStatus
end   -- killsay

-- when each player was last seen non-dormant (weak keys: disconnected players drop out)
local dormantSeen = setmetatable({}, {__mode = "k"})
local COL_DORMANT = Color(170, 170, 170)

-- a circle `deg` degrees around the crosshair (angle -> pixels using the real horizontal fov)
local function DrawFovRing(me, deg, r, g, b, a)
    local fov = cfg.view.fovOn and cfg.view.fov or me:GetFOV()
    local aspect = ScrW() / ScrH()
    local hfov = 2 * math.atan(math.tan(math.rad(fov) / 2) * (aspect / (4 / 3)))
    local radius = math.tan(math.rad(math.min(deg, 85))) / math.tan(hfov / 2) * (ScrW() / 2)

    local cx, cy = ScrW() / 2, ScrH() / 2
    local segments = 64

    surface.SetDrawColor(r, g, b, a)
    for i = 0, segments - 1 do
        local a1 = (i / segments) * math.pi * 2
        local a2 = ((i + 1) / segments) * math.pi * 2
        surface.DrawLine(
            cx + math.cos(a1) * radius, cy + math.sin(a1) * radius,
            cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
        )
    end
end

AddHook("HUDPaint", "esp", function()
    if IsHidden() then return end

    local me = LocalPlayer()
    if not IsValid(me) then return end

    local esp = cfg.esp
    if esp.enabled then
        local myPos = me:GetPos()
        local baseColor = Color(esp.r, esp.g, esp.b, 255)

        local now = CurTime()

        for _, v in ipairs(player.GetAll()) do
            if v == me or not v:Alive() then continue end
            if v:GetObserverMode() ~= OBS_MODE_NONE then continue end
            if esp.teamCheck and v:Team() == me:Team() then continue end

            -- A dormant player is outside the PVS: the server stopped sending it, and the entity
            -- just sits at the last position it was networked at. Keep showing it there, fading.
            local dormant = v:IsDormant()
            local fade = 1

            if dormant then
                local seen = dormantSeen[v]
                if not esp.dormant or not seen then continue end

                local age = now - seen
                if age > esp.dormantTime then continue end

                fade = 1 - (age / esp.dormantTime) * 0.8
            else
                dormantSeen[v] = now
            end

            local metres = myPos:Distance(v:GetPos()) * 0.01905
            if metres > esp.maxDist then continue end

            local x, y, w, h = GetScreenBox(v)
            if not x then continue end

            local col = esp.teamColor and team.GetColor(v:Team()) or baseColor
            if FR.IsTarget(v) then
                col = FR.targetColor
            elseif FR.Is(v) then
                col = FR.color
            end
            local outline = COL_BLACK

            if dormant then
                col = Color(COL_DORMANT.r, COL_DORMANT.g, COL_DORMANT.b, 255 * fade)
                outline = Color(0, 0, 0, 255 * fade)
            end

            if esp.box then
                surface.SetDrawColor(COL_BOXBG)
                surface.DrawOutlinedRect(x - 1, y - 1, w + 2, h + 2, 1)
                surface.DrawOutlinedRect(x + 1, y + 1, w - 2, h - 2, 1)
                surface.SetDrawColor(col)
                surface.DrawOutlinedRect(x, y, w, h, 1)
            end

            local hpLine     -- text + colour of the HP number when it goes under the box

            if esp.health and not dormant then
                local hp = v:Health()
                local maxHp = math.max(v:GetMaxHealth(), 100)
                local frac = math.Clamp(hp / maxHp, 0, 1)
                local barH = math.floor(h * frac)
                local barCol = Color(255 * (1 - frac), 255 * frac, 0, 255)

                surface.SetDrawColor(COL_BOXBG)
                surface.DrawRect(x - 6, y - 1, 4, h + 2)
                surface.SetDrawColor(barCol)
                surface.DrawRect(x - 5, y + h - barH, 2, barH)

                -- the number
                if esp.hpText and not (esp.hpHideFull and hp >= maxHp) then
                    local text = esp.hpPercent and (math.floor(frac * 100 + 0.5) .. "%") or tostring(math.max(hp, 0))
                    local tcol = barCol
                    if esp.hpColor == "text" then
                        tcol = col
                    elseif esp.hpColor == "custom" then
                        tcol = Color(esp.hpR, esp.hpG, esp.hpB, col.a)
                    end
                    tcol = Color(tcol.r, tcol.g, tcol.b, col.a)   -- dormant fade

                    if esp.hpPos == "top" then
                        draw.SimpleTextOutlined(text, "NyxESP", x - 4, y - 3, tcol, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, outline)
                    elseif esp.hpPos == "below" then
                        hpLine = {text, tcol}
                    else
                        -- beside the bar, riding on its top edge (kept inside the box's height)
                        local ty = math.Clamp(y + h - barH, y, y + h - 8)
                        draw.SimpleTextOutlined(text, "NyxESP", x - 8, ty, tcol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 1, outline)
                    end
                end
            end

            if esp.name then
                draw.SimpleTextOutlined(v:Nick(), "NyxESP", x + w / 2, y - 3, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, outline)
            end

            local lineY = y + h + 2

            if hpLine then
                draw.SimpleTextOutlined(hpLine[1] .. (esp.hpPercent and "" or " hp"), "NyxESP", x + w / 2, lineY, hpLine[2],
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, outline)
                lineY = lineY + 12
            end
            if esp.weapon and not dormant then
                local wname = WeaponName(v)
                if wname then
                    draw.SimpleTextOutlined(wname, "NyxESP", x + w / 2, lineY, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, COL_BLACK)
                    lineY = lineY + 12
                end
            end

            if esp.distance then
                draw.SimpleTextOutlined(math.floor(metres) .. "m", "NyxESP", x + w / 2, lineY, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, outline)
                lineY = lineY + 12
            end

            if dormant then
                draw.SimpleTextOutlined("dormant", "NyxESP", x + w / 2, lineY, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, outline)
            end
        end
    end

    -- world ESP: NPCs, loose weapons, props, vehicles, items, doors, scripted entities
    local world = cfg.world
    if world.enabled then
        local myPos = me:GetPos()

        for _, entry in ipairs(GetWorldList(me)) do
            local e = entry.ent
            if not IsValid(e) then continue end

            local metres = myPos:Distance(e:GetPos()) * 0.01905
            if metres > world.maxDist then continue end

            local x, y, w, h = GetScreenBox(e)
            if not x then continue end

            local col = WORLD_COLORS[entry.cat]

            if world.box then
                surface.SetDrawColor(COL_BOXBG)
                surface.DrawOutlinedRect(x - 1, y - 1, w + 2, h + 2, 1)
                surface.DrawOutlinedRect(x + 1, y + 1, w - 2, h - 2, 1)
                surface.SetDrawColor(col)
                surface.DrawOutlinedRect(x, y, w, h, 1)
            end

            if world.name then
                draw.SimpleTextOutlined(WorldLabel(e, entry.cat), "NyxESP", x + w / 2, y - 3, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, COL_BLACK)
            end

            if world.distance then
                draw.SimpleTextOutlined(math.floor(metres) .. "m", "NyxESP", x + w / 2, y + h + 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, COL_BLACK)
            end
        end
    end

    -- aim FOV circles: white for the legit aimbot, red for the rage one
    if cfg.aim.enabled and cfg.aim.drawFov then
        DrawFovRing(me, cfg.aim.fov, 255, 255, 255, 110)
    end

    -- rage FOV 180 is the whole view, a ring would only be off screen
    if cfg.rage.enabled and cfg.rage.drawFov and cfg.rage.fov < 180 then
        local rg = cfg.rage
        DrawFovRing(me, rg.fov, rg.fovR, rg.fovG, rg.fovB, 150)
    end

    -- marker on the point the aimbot is using
    -- (each aimbot has its own switch for it)
    local markerOn
    if lastAimRage then
        markerOn = cfg.rage.enabled and cfg.rage.drawTarget
    else
        markerOn = cfg.aim.enabled and cfg.aim.drawTarget
    end

    if markerOn and lastAimPos and CurTime() - lastAimTime < 0.2 then
        local sp = lastAimPos:ToScreen()
        if sp.visible then
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawOutlinedRect(sp.x - 3, sp.y - 3, 7, 7, 1)

            -- red = a clear shot, orange = through a wall (autowall)
            if lastAimWall then
                surface.SetDrawColor(255, 170, 40, 255)
                surface.DrawRect(sp.x - 2, sp.y - 2, 5, 5)
                draw.SimpleText("wallbang", "NyxESP", sp.x, sp.y + 8, Color(255, 170, 40), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            else
                surface.SetDrawColor(255, 60, 60, 255)
                surface.DrawRect(sp.x - 2, sp.y - 2, 5, 5)
            end

            -- shot at an older position of the target (backtrack)
            if lastAimBT then
                draw.SimpleText(string.format("backtrack %dms", lastAimBT), "NyxESP", sp.x, sp.y + (lastAimWall and 20 or 8),
                    Color(90, 200, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
        end
    end

    -- the records backtrack can still shoot at, as dots along the target's recent path
    if cfg.backtrack.enabled and cfg.backtrack.draw and IsValid(aimTargetEnt)
        and CurTime() - aimTargetTime < 1 and BT.recs[aimTargetEnt] then
        local now = CurTime()
        local maxAge = cfg.backtrack.ms / 1000

        for _, rec in ipairs(BT.recs[aimTargetEnt]) do
            local age = now - rec.time

            if age <= maxAge then
                local p = rec.chest:ToScreen()

                if p.visible then
                    local a = 40 + 200 * (1 - age / math.max(maxAge, 0.001))

                    surface.SetDrawColor(0, 0, 0, a)
                    surface.DrawRect(p.x - 2, p.y - 2, 5, 5)
                    surface.SetDrawColor(90, 200, 255, a)
                    surface.DrawRect(p.x - 1, p.y - 1, 3, 3)
                end
            end
        end
    end

    -- anti-aim indicator: green = where you really look (always up), red = the angle being sent
    if cfg.aa.enabled and cfg.aa.indicator and aaActive then
        local cx, cy = ScrW() / 2, ScrH() / 2

        local function Arrow(rel, col)
            local rad = math.rad(rel)
            local dx, dy = -math.sin(rad), -math.cos(rad)   -- yaw grows counter-clockwise
            local px, py = -dy, dx

            local tipX, tipY = cx + dx * 70, cy + dy * 70
            local bx, by = cx + dx * 52, cy + dy * 52

            surface.SetDrawColor(col)
            surface.DrawLine(tipX, tipY, bx + px * 7, by + py * 7)
            surface.DrawLine(tipX, tipY, bx - px * 7, by - py * 7)
            surface.DrawLine(bx + px * 7, by + py * 7, bx - px * 7, by - py * 7)
        end

        Arrow(0, Color(0, 255, 0, 220))
        Arrow(math.NormalizeAngle((MV.aaYaw or sentAng.y) - realAng.y), Color(255, 60, 60, 220))
    end
end)

-- ---------------------------------------------------------------------------
-- menu (custom-painted VGUI, skeet style)
--   right-click a checkbox  : bind it (hold / toggle / release on any key)
--   small arrow on the row  : settings dropdown of that feature
-- ---------------------------------------------------------------------------

surface.CreateFont("NyxUI", {font = "Verdana", size = 12, weight = 400, antialias = false})
surface.CreateFont("NyxUIBold", {font = "Verdana", size = 12, weight = 700, antialias = false})
surface.CreateFont("NyxUISmall", {font = "Verdana", size = 11, weight = 400, antialias = false})

local C = {
    bg          = Color(13, 13, 13),
    tabBg       = Color(20, 20, 20),
    border      = Color(50, 50, 50),
    groupBorder = Color(38, 38, 38),
    text        = Color(190, 190, 190),
    textHi      = Color(255, 255, 255),
    textDim     = Color(110, 110, 110),
    accent      = Color(149, 184, 6),
    boxOff      = Color(58, 58, 58),
    boxBorder   = Color(4, 4, 4),
    field       = Color(26, 26, 26),
    fieldHover  = Color(40, 40, 40),
}

local GRADIENT = {Color(127, 217, 60), Color(55, 140, 255), Color(200, 70, 230)}

local function GradientAt(t)
    local seg = t * (#GRADIENT - 1)
    local i = math.min(math.floor(seg) + 1, #GRADIENT - 1)
    local f = seg - (i - 1)
    local a, b = GRADIENT[i], GRADIENT[i + 1]
    return a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f
end

-- Animation helpers. ANIM.Step eases a value towards its target (frame-rate independent, and it
-- just snaps when the menu animations are switched off); ANIM.Mix blends two colours.
local ANIM = {}

function ANIM.Step(cur, target, rate)
    if not cfg.menu.anim then return target end

    local v = cur + (target - cur) * math.min(1, FrameTime() * rate * cfg.menu.speed)
    if math.abs(target - v) < 0.003 then return target end
    return v
end

function ANIM.Mix(a, b, t)
    return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 255)
end

-- Search index (Ctrl+F). While BuildMenu builds the pages, every widget registers its name here
-- together with the tab it is on; the content of a feature's settings popup is indexed too (the
-- popup builder is run once into a hidden panel) and points back at the feature that owns it.
local SEARCH = {index = {}, tab = nil, via = nil}

function SEARCH.Register(text, panel, kind)
    if not SEARCH.tab or type(text) ~= "string" or text == "" then return end

    SEARCH.index[#SEARCH.index + 1] = {text = text, tab = SEARCH.tab, panel = panel, kind = kind, via = SEARCH.via}
end

local lastTab = 1
local binding = nil     -- keybind widget currently waiting for a key

-- Bind finished, or cancelled with ESC. Fed from three sources (polling, key events on the
-- menu, mouse capture on the bind widget) so a press is picked up whichever one sees it.
local function FinishBinding(code)
    if not binding then return end

    if code ~= KEY_ESCAPE and code ~= KEY_INSERT then
        binding.tbl[binding.key] = code
    end

    local panel = binding.panel
    binding = nil

    if IsValid(panel) then panel:MouseCapture(false) end
    if IsValid(menu) then menu:SetKeyboardInputEnabled(false) end
end

-- feature binds ----------------------------------------------------------------
-- entry = {tbl, key, code, mode = always|hold|toggle|release, wasDown}
-- The entry drives tbl[key] (the same value the checkbox shows).

local bindIndex = {}    -- bindIndex[tbl][key] = entry
local bindList = {}

local MODE_SHORT = {hold = "hold", toggle = "toggle", release = "release"}

local function GetBind(tbl, key, create)
    local per = bindIndex[tbl]
    if not per then
        if not create then return nil end
        per = {}
        bindIndex[tbl] = per
    end

    local e = per[key]
    if not e and create then
        e = {tbl = tbl, key = key, code = nil, mode = "always", wasDown = false}
        per[key] = e
        bindList[#bindList + 1] = e
    end
    return e
end

-- tab icons (drawn with lines so there are no material dependencies)
local function Line(x1, y1, x2, y2, col)
    surface.SetDrawColor(col)
    surface.DrawLine(x1, y1, x2, y2)
    surface.DrawLine(x1 + 1, y1, x2 + 1, y2)
end

local function Ring(cx, cy, r, col)
    local seg = 32
    local px, py = cx + r, cy
    for i = 1, seg do
        local a = (i / seg) * math.pi * 2
        local nx, ny = cx + math.cos(a) * r, cy + math.sin(a) * r
        Line(px, py, nx, ny, col)
        px, py = nx, ny
    end
end

local ICONS = {
    -- rage: bolt
    function(cx, cy, col)
        Line(cx + 5, cy - 17, cx - 7, cy + 1, col)
        Line(cx - 7, cy + 1, cx + 3, cy + 1, col)
        Line(cx + 3, cy + 1, cx - 5, cy + 17, col)
        Line(cx + 6, cy - 17, cx + 7, cy - 9, col)
        Line(cx - 4, cy + 17, cx - 3, cy + 9, col)
    end,
    -- anti-aim: ring with a bar through it
    function(cx, cy, col)
        Ring(cx, cy, 14, col)
        Line(cx - 10, cy - 10, cx + 10, cy + 10, col)
    end,
    -- legit aim: crosshair
    function(cx, cy, col)
        Ring(cx, cy, 13, col)
        Line(cx - 21, cy, cx - 8, cy, col)
        Line(cx + 8, cy, cx + 21, cy, col)
        Line(cx, cy - 21, cx, cy - 8, col)
        Line(cx, cy + 8, cx, cy + 21, col)
        surface.SetDrawColor(col)
        surface.DrawRect(cx - 1, cy - 1, 3, 3)
    end,
    -- visuals: half-filled circle
    function(cx, cy, col)
        Ring(cx, cy, 15, col)
        local pts = {}
        for i = 0, 16 do
            local a = math.pi / 2 + (i / 16) * math.pi
            pts[#pts + 1] = {x = cx + math.cos(a) * 12, y = cy + math.sin(a) * 12}
        end
        surface.SetDrawColor(col)
        draw.NoTexture()
        surface.DrawPoly(pts)
    end,
    -- movement: double chevron
    function(cx, cy, col)
        for _, off in ipairs({-9, 5}) do
            Line(cx + off - 5, cy - 12, cx + off + 5, cy, col)
            Line(cx + off + 5, cy, cx + off - 5, cy + 12, col)
        end
    end,
    -- misc: gear
    function(cx, cy, col)
        Ring(cx, cy, 9, col)
        Ring(cx, cy, 4, col)
        for i = 0, 7 do
            local a = i * math.pi / 4
            Line(cx + math.cos(a) * 9, cy + math.sin(a) * 9, cx + math.cos(a) * 15, cy + math.sin(a) * 15, col)
        end
    end,
    -- config: floppy disk
    function(cx, cy, col)
        Line(cx - 13, cy - 13, cx + 9, cy - 13, col)
        Line(cx + 9, cy - 13, cx + 13, cy - 9, col)
        Line(cx + 13, cy - 9, cx + 13, cy + 13, col)
        Line(cx + 13, cy + 13, cx - 13, cy + 13, col)
        Line(cx - 13, cy + 13, cx - 13, cy - 13, col)
        Line(cx - 7, cy - 13, cx - 7, cy - 5, col)
        Line(cx - 7, cy - 5, cx + 6, cy - 5, col)
        Line(cx + 6, cy - 5, cx + 6, cy - 13, col)
        Line(cx - 7, cy + 13, cx - 7, cy + 4, col)
        Line(cx - 7, cy + 4, cx + 7, cy + 4, col)
        Line(cx + 7, cy + 4, cx + 7, cy + 13, col)
    end,
    -- players: head and shoulders
    function(cx, cy, col)
        Ring(cx, cy - 6, 6, col)
        Line(cx - 13, cy + 14, cx - 11, cy + 5, col)
        Line(cx - 11, cy + 5, cx - 5, cy + 2, col)
        Line(cx - 5, cy + 2, cx + 5, cy + 2, col)
        Line(cx + 5, cy + 2, cx + 11, cy + 5, col)
        Line(cx + 11, cy + 5, cx + 13, cy + 14, col)
        Line(cx - 13, cy + 14, cx + 13, cy + 14, col)
    end,
    -- entities: wireframe cube
    function(cx, cy, col)
        local s, o = 10, 6
        Line(cx - s, cy - s + o, cx + s - o, cy - s + o, col)
        Line(cx + s - o, cy - s + o, cx + s - o, cy + s, col)
        Line(cx + s - o, cy + s, cx - s, cy + s, col)
        Line(cx - s, cy + s, cx - s, cy - s + o, col)
        Line(cx - s + o, cy - s, cx + s, cy - s, col)
        Line(cx + s, cy - s, cx + s, cy + s - o, col)
        Line(cx - s, cy - s + o, cx - s + o, cy - s, col)
        Line(cx + s - o, cy - s + o, cx + s, cy - s, col)
        Line(cx + s - o, cy + s, cx + s, cy + s - o, col)
    end,
}

-- widgets ------------------------------------------------------------------

local MOUSE_NAMES = {
    [MOUSE_LEFT] = "MOUSE1", [MOUSE_RIGHT] = "MOUSE2", [MOUSE_MIDDLE] = "MOUSE3",
    [MOUSE_4] = "MOUSE4", [MOUSE_5] = "MOUSE5",
}

local function KeyName(k)
    if not k then return "NONE" end
    return MOUSE_NAMES[k] or string.upper(input.GetKeyName(k) or ("KEY" .. k))
end

-- assigned further down (they need widgets defined after AddCheck)
local OpenBindPopup, OpenSettingsPopup, OpenColorPopup

-- a "group" is any panel with a `cy` cursor: tab groups and popups both work
local function NewGroup(col, title)
    local g = vgui.Create("Panel", col.page)
    g:SetPos(col.x, col.y)
    g:SetSize(col.w, 60)
    g.col = col
    g.cy = 22

    g.Paint = function(self, w, h)
        surface.SetDrawColor(C.groupBorder)
        surface.DrawOutlinedRect(0, 6, w, h - 6, 1)

        surface.SetFont("NyxUIBold")
        local tw = surface.GetTextSize(title)
        surface.SetDrawColor(C.bg)
        surface.DrawRect(8, 0, tw + 8, 14)
        draw.SimpleText(title, "NyxUIBold", 12, 0, C.textHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    SEARCH.Register(title, g, "group")

    return g
end

local function EndGroup(g)
    g.baseY = g:GetY()          -- the unscrolled position; the page's scroll is subtracted from it
    g:SetTall(g.cy + 6)
    g.col.y = g.col.y + g:GetTall() + 14
end

local function WidgetPanel(g, h)
    local p = vgui.Create("Panel", g)
    p:SetPos(14, g.cy)
    p:SetSize(g:GetWide() - 28, h)
    g.cy = g.cy + h + 6
    return p
end

local SETTINGS_BTN_W = 18

-- settings(popup) is optional: when given the row gets a dropdown arrow that opens it
local function AddCheck(g, text, tbl, key, settings)
    local p = WidgetPanel(g, 14)
    p:SetCursor("hand")

    local on = tbl[key] and 1 or 0       -- eased 0..1: the box fills and empties smoothly
    local hot = 0                        -- eased hover

    p.Paint = function(self, w, h)
        on = ANIM.Step(on, tbl[key] and 1 or 0, 14)
        hot = ANIM.Step(hot, self:IsHovered() and 1 or 0, 12)

        surface.SetDrawColor(C.boxOff)
        surface.DrawRect(0, 3, 9, 9)

        if on > 0 then
            local s = 9 * on
            local o = (9 - s) / 2
            surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 255 * on)
            surface.DrawRect(o, 3 + o, s, s)
        end

        surface.SetDrawColor(C.boxBorder)
        surface.DrawOutlinedRect(0, 3, 9, 9, 1)
        draw.SimpleText(text, "NyxUI", 17 + hot * 2, h / 2, ANIM.Mix(C.text, C.textHi, hot), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local right = w
        if settings then
            local bx = w - SETTINGS_BTN_W
            local mx = self:CursorPos()
            local hov = self:IsHovered() and mx >= bx

            surface.SetDrawColor(hov and C.fieldHover or C.field)
            surface.DrawRect(bx, 0, SETTINGS_BTN_W, h)
            surface.SetDrawColor(C.groupBorder)
            surface.DrawOutlinedRect(bx, 0, SETTINGS_BTN_W, h, 1)

            local cx, cy = bx + SETTINGS_BTN_W / 2, h / 2
            surface.SetDrawColor(hov and C.textHi or C.textDim)
            surface.DrawLine(cx - 3, cy - 1, cx, cy + 2)
            surface.DrawLine(cx, cy + 2, cx + 3, cy - 1)

            right = bx - 6
        end

        -- bind indicator, e.g. [hold MOUSE4]
        local e = GetBind(tbl, key, false)
        if e and e.mode ~= "always" and e.code then
            draw.SimpleText("[" .. MODE_SHORT[e.mode] .. " " .. KeyName(e.code) .. "]", "NyxUISmall", right, h / 2, C.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    p.OnMousePressed = function(self, code)
        if code == MOUSE_RIGHT then
            OpenBindPopup(text, tbl, key)
            return
        end
        if code ~= MOUSE_LEFT then return end

        if settings then
            local mx = self:CursorPos()
            if mx >= self:GetWide() - SETTINGS_BTN_W then
                OpenSettingsPopup(text, settings)
                return
            end
        end

        tbl[key] = not tbl[key]
    end

    SEARCH.Register(text, p, "toggle")

    -- index what is inside its settings popup: run the builder once into a hidden panel
    if settings and SEARCH.tab and not SEARCH.via then
        SEARCH.via = {
            text = text,
            panel = p,
            open = function() OpenSettingsPopup(text, settings) end,
        }

        local dummy = vgui.Create("Panel")
        dummy:SetSize(230, 40)
        dummy:SetVisible(false)
        dummy.cy = 28

        pcall(settings, dummy)

        dummy:Remove()
        SEARCH.via = nil
    end
end

local function AddSlider(g, text, tbl, key, min, max, dec, suffix)
    suffix = suffix or ""
    local p = WidgetPanel(g, 30)

    local function setFromCursor(self)
        local x = self:CursorPos()
        local frac = math.Clamp(x / self:GetWide(), 0, 1)
        local m = 10 ^ dec
        tbl[key] = math.floor((min + (max - min) * frac) * m + 0.5) / m
    end

    local shown = nil                    -- eased fill, so the bar glides to a new value

    p.Paint = function(self, w, h)
        draw.SimpleText(text, "NyxUI", 0, 0, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local frac = math.Clamp((tbl[key] - min) / (max - min), 0, 1)
        shown = shown and ANIM.Step(shown, frac, 18) or frac

        surface.SetDrawColor(C.field)
        surface.DrawRect(0, 16, w, 12)
        surface.SetDrawColor(C.accent)
        surface.DrawRect(1, 17, math.floor((w - 2) * shown), 10)
        surface.SetDrawColor(C.boxBorder)
        surface.DrawOutlinedRect(0, 16, w, 12, 1)

        draw.SimpleText(string.format("%." .. dec .. "f%s", tbl[key], suffix), "NyxUISmall", w / 2, 22, C.textHi, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    p.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end
        self.drag = true
        self:MouseCapture(true)
        setFromCursor(self)
    end

    p.OnMouseReleased = function(self)
        self.drag = false
        self:MouseCapture(false)
    end

    p.OnCursorMoved = function(self)
        if self.drag then setFromCursor(self) end
    end

    SEARCH.Register(text, p, "slider")
end

-- choices = { {label, value}, ... }
local function AddList(g, text, tbl, key, choices)
    local rowH = 15
    local p = WidgetPanel(g, 16 + 8 + #choices * rowH)
    p:SetCursor("hand")

    local rowHot, rowSel = {}, {}

    local function rowAt(self, y)
        local i = math.floor((y - 16 - 4) / rowH) + 1
        if i >= 1 and i <= #choices then return i end
    end

    p.Paint = function(self, w, h)
        draw.SimpleText(text, "NyxUI", 0, 0, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        surface.SetDrawColor(C.field)
        surface.DrawRect(0, 16, w, h - 16)
        surface.SetDrawColor(C.groupBorder)
        surface.DrawOutlinedRect(0, 16, w, h - 16, 1)

        local hover
        if self:IsHovered() then
            local _, my = self:CursorPos()
            hover = rowAt(self, my)
        end

        for i, choice in ipairs(choices) do
            -- eased hover / selection per row: text slides in and the accent bar grows
            rowHot[i] = ANIM.Step(rowHot[i] or 0, (i == hover) and 1 or 0, 14)
            rowSel[i] = ANIM.Step(rowSel[i] or 0, (choice[2] == tbl[key]) and 1 or 0, 14)

            local y = 16 + 4 + (i - 1) * rowH

            if rowSel[i] > 0 then
                surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 255 * rowSel[i])
                surface.DrawRect(1, y, 2, rowH - 2)
            end

            local col = ANIM.Mix(ANIM.Mix(C.textDim, C.textHi, rowHot[i]), C.accent, rowSel[i])
            draw.SimpleText("- " .. choice[1], "NyxUI", 8 + rowHot[i] * 2 + rowSel[i] * 2, y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end

    p.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end
        local _, my = self:CursorPos()
        local i = rowAt(self, my)
        if i then tbl[key] = choices[i][2] end
    end

    SEARCH.Register(text, p, "list")
end

local function AddKeybind(g, text, tbl, key)
    local p = WidgetPanel(g, 18)
    p:SetCursor("hand")

    p.Paint = function(self, w, h)
        draw.SimpleText(text, "NyxUI", 0, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local waiting = binding and binding.panel == self
        local label = waiting and "..." or KeyName(tbl[key])
        local bw = 88

        surface.SetDrawColor(C.field)
        surface.DrawRect(w - bw, 0, bw, h)
        surface.SetDrawColor(C.groupBorder)
        surface.DrawOutlinedRect(w - bw, 0, bw, h, 1)
        draw.SimpleText("[ " .. label .. " ]", "NyxUI", w - bw / 2, h / 2, waiting and C.accent or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    p.OnMousePressed = function(self, code)
        -- already waiting: the mouse is captured, so any click binds that mouse button
        if binding and binding.panel == self then
            FinishBinding(code)
            return
        end

        if code ~= MOUSE_LEFT then return end

        binding = {panel = self, tbl = tbl, key = key, armed = false}
        self:MouseCapture(true)

        -- let the menu receive key events while we wait
        if IsValid(menu) then
            menu:SetKeyboardInputEnabled(true)
            menu:RequestFocus()
        end
    end

    SEARCH.Register(text, p, "key")
end

local function AddButton(g, text, fn)
    local p = WidgetPanel(g, 22)
    p:SetCursor("hand")

    local hot, flash = 0, 0              -- eased hover, and a short flash after a click

    p.Paint = function(self, w, h)
        hot = ANIM.Step(hot, self:IsHovered() and 1 or 0, 12)
        flash = ANIM.Step(flash, 0, 7)

        local bg = ANIM.Mix(C.field, C.fieldHover, hot)
        surface.SetDrawColor(math.min(255, bg.r + 40 * flash), math.min(255, bg.g + 50 * flash), math.min(255, bg.b + 10 * flash), 255)
        surface.DrawRect(0, 0, w, h)

        local border = ANIM.Mix(C.groupBorder, C.accent, hot * 0.7)
        surface.SetDrawColor(border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        draw.SimpleText(text, "NyxUI", w / 2, h / 2, ANIM.Mix(C.text, C.textHi, hot), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    p.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end

        flash = 1
        fn()
    end

    SEARCH.Register(text, p, "button")
end

-- text may be a function for live values
local function AddLabel(g, text, col)
    local p = WidgetPanel(g, 14)
    p.Paint = function(self, w, h)
        local s = type(text) == "function" and text() or text
        draw.SimpleText(s, "NyxUI", 0, h / 2, col or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

-- colour picker -------------------------------------------------------------

local CU = {}

-- h, s, v in 0..1 -> r, g, b in 0..1
function CU.ToRGB(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)

    i = i % 6
    if i == 0 then return v, t, p end
    if i == 1 then return q, v, p end
    if i == 2 then return p, v, t end
    if i == 3 then return p, q, v end
    if i == 4 then return t, p, v end
    return v, p, q
end

-- r, g, b in 0..1 -> h, s, v in 0..1
function CU.ToHSV(r, g, b)
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local d = max - min

    local h = 0
    if d > 0 then
        if max == r then
            h = ((g - b) / d) % 6
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
    end

    return h, (max > 0) and (d / max) or 0, max
end

function CU.Inside(panel, mx, my)
    local x, y = panel:LocalToScreen(0, 0)
    return mx >= x and mx <= x + panel:GetWide() and my >= y and my <= y + panel:GetTall()
end

-- Saturation / value square, hue bar and a preview line. The colour is written straight into
-- tbl[rk], tbl[gk], tbl[bk] as 0..255 integers, so any trio of fields can be edited.
local function AddColorPicker(g, tbl, rk, gk, bk)
    local SV_H, GAP, HUE_H, CELL = 110, 8, 14, 5
    local p = WidgetPanel(g, SV_H + GAP + HUE_H + GAP + 18)

    local h, s, v = CU.ToHSV((tbl[rk] or 255) / 255, (tbl[gk] or 255) / 255, (tbl[bk] or 255) / 255)
    local grid, gridHue, gridCols = nil, -1, 0
    local drag = nil          -- "sv" | "hue"

    local function write()
        local r, gg, b = CU.ToRGB(h, s, v)
        tbl[rk] = math.floor(r * 255 + 0.5)
        tbl[gk] = math.floor(gg * 255 + 0.5)
        tbl[bk] = math.floor(b * 255 + 0.5)
    end

    local function update(self)
        local x, y = self:CursorPos()

        if drag == "sv" then
            s = math.Clamp(x / self:GetWide(), 0, 1)
            v = 1 - math.Clamp(y / SV_H, 0, 1)
        elseif drag == "hue" then
            h = math.Clamp(x / self:GetWide(), 0, 0.999)
        end

        write()
    end

    p.Paint = function(self, w, ph)
        -- the square is a grid of flat cells, rebuilt only when the hue (or width) changed
        local cols, rows = math.ceil(w / CELL), math.ceil(SV_H / CELL)

        if not grid or gridHue ~= h or gridCols ~= cols then
            grid = {r = {}, g = {}, b = {}}

            for cy = 0, rows - 1 do
                for cx = 0, cols - 1 do
                    local r, gg, b = CU.ToRGB(h, (cx + 0.5) / cols, 1 - (cy + 0.5) / rows)
                    local i = cy * cols + cx
                    grid.r[i], grid.g[i], grid.b[i] = r * 255, gg * 255, b * 255
                end
            end

            gridHue, gridCols = h, cols
        end

        for cy = 0, rows - 1 do
            for cx = 0, cols - 1 do
                local i = cy * cols + cx
                surface.SetDrawColor(grid.r[i], grid.g[i], grid.b[i], 255)
                surface.DrawRect(cx * CELL, cy * CELL, CELL, CELL)
            end
        end

        surface.SetDrawColor(C.boxBorder)
        surface.DrawOutlinedRect(0, 0, w, SV_H, 1)

        -- marker on the square
        local mx, my = s * (w - 1), (1 - v) * (SV_H - 1)
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawOutlinedRect(mx - 4, my - 4, 9, 9, 1)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawOutlinedRect(mx - 3, my - 3, 7, 7, 1)

        -- hue bar
        local hueY = SV_H + GAP
        for x = 0, w - 1, 2 do
            local r, gg, b = CU.ToRGB(x / w, 1, 1)
            surface.SetDrawColor(r * 255, gg * 255, b * 255, 255)
            surface.DrawRect(x, hueY, 2, HUE_H)
        end

        surface.SetDrawColor(C.boxBorder)
        surface.DrawOutlinedRect(0, hueY, w, HUE_H, 1)

        local hx = h * (w - 1)
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(hx - 1, hueY - 2, 4, HUE_H + 4)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawRect(hx, hueY - 1, 2, HUE_H + 2)

        -- preview + values
        local py = hueY + HUE_H + GAP
        local r, gg, b = math.floor(tbl[rk] + 0.5), math.floor(tbl[gk] + 0.5), math.floor(tbl[bk] + 0.5)

        surface.SetDrawColor(r, gg, b, 255)
        surface.DrawRect(0, py, 40, 16)
        surface.SetDrawColor(C.boxBorder)
        surface.DrawOutlinedRect(0, py, 40, 16, 1)

        draw.SimpleText(string.format("#%02X%02X%02X   %d  %d  %d", r, gg, b, r, gg, b), "NyxUISmall", 48, py + 8, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    p.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end

        local _, y = self:CursorPos()
        if y <= SV_H then
            drag = "sv"
        elseif y >= SV_H + GAP - 2 and y <= SV_H + GAP + HUE_H + 2 then
            drag = "hue"
        else
            return
        end

        self:MouseCapture(true)
        update(self)
    end

    p.OnMouseReleased = function(self)
        drag = nil
        self:MouseCapture(false)
    end

    p.OnCursorMoved = function(self)
        if drag then update(self) end
    end
end

-- a label with a colour swatch; clicking it opens the picker next to the current popup
local function AddColor(g, text, tbl, rk, gk, bk)
    local p = WidgetPanel(g, 16)
    p:SetCursor("hand")

    p.Paint = function(self, w, h)
        draw.SimpleText(text, "NyxUI", 0, h / 2, self:IsHovered() and C.textHi or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local bw = 38
        surface.SetDrawColor(tbl[rk], tbl[gk], tbl[bk], 255)
        surface.DrawRect(w - bw, 1, bw, h - 2)
        surface.SetDrawColor(C.boxBorder)
        surface.DrawOutlinedRect(w - bw, 1, bw, h - 2, 1)
    end

    p.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end
        OpenColorPopup(text, function(pop) AddColorPicker(pop, tbl, rk, gk, bk) end)
    end

    SEARCH.Register(text, p, "color")
end

-- the whole menu paints nothing while a screengrab is being taken
local function WrapPaint(panel)
    -- plain "Panel" objects have no Paint method at all, so it can be nil
    local paint = panel.Paint
    panel.Paint = function(self, w, h)
        if IsHidden() then return end
        if paint then return paint(self, w, h) end
    end

    for _, child in ipairs(panel:GetChildren()) do
        WrapPaint(child)
    end
end

-- popups (bind menu, feature settings) ------------------------------------

local popup = nil
local colorPopup = nil     -- the colour picker, a second panel beside the current popup

local function ClosePopup()
    if IsValid(popup) then popup:Remove() end
    if IsValid(colorPopup) then colorPopup:Remove() end
    popup = nil
    colorPopup = nil
end

-- build(p) fills the popup with the same widgets the tab groups use
local function OpenPopup(title, width, build)
    ClosePopup()
    if not IsValid(menu) then return end

    local mx, my = gui.MouseX(), gui.MouseY()

    local p = vgui.Create("Panel", menu)
    popup = p
    p:SetSize(width, 60)
    p.cy = 28

    p.Paint = function(self, w, h)
        surface.SetDrawColor(C.tabBg)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        surface.SetDrawColor(C.accent)
        surface.DrawRect(1, 1, w - 2, 1)
        draw.SimpleText(title, "NyxUIBold", 10, 8, C.textHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    build(p)
    p:SetTall(p.cy + 6)

    local fx, fy = menu:ScreenToLocal(mx, my)
    p:SetPos(
        math.Clamp(fx, 4, menu:GetWide() - width - 4),
        math.Clamp(fy, 4, menu:GetTall() - p:GetTall() - 4)
    )
    p:MoveToFront()

    -- close on a click outside; the click that opened us is still down, so wait for its release
    -- fades in (and drifts up a little) when it opens
    p.fade = 0
    p:SetAlpha(0)
    local popupY = p:GetY()

    p.wasDown = true
    p.Think = function(self)
        self.fade = ANIM.Step(self.fade, 1, 14)
        self:SetAlpha(255 * self.fade)
        self:SetY(popupY + (1 - self.fade) * 8)

        local down = input.IsMouseDown(MOUSE_LEFT) or input.IsMouseDown(MOUSE_RIGHT)

        if down and not self.wasDown and not binding then
            local x, y = self:LocalToScreen(0, 0)
            local cx, cy = gui.MouseX(), gui.MouseY()
            local outside = cx < x or cx > x + self:GetWide() or cy < y or cy > y + self:GetTall()

            -- a click on the colour picker that sits beside this popup is not "outside"
            if outside and not (IsValid(colorPopup) and CU.Inside(colorPopup, cx, cy)) then
                ClosePopup()
                return
            end
        end

        self.wasDown = down
    end

    WrapPaint(p)
end

OpenBindPopup = function(name, tbl, key)
    local e = GetBind(tbl, key, true)
    e.name = name                         -- shown in the keybind list

    OpenPopup(name .. " - bind", 220, function(p)
        AddKeybind(p, "Key", e, "code")
        AddList(p, "Mode", e, "mode", {
            {"Always on", "always"},
            {"Hold", "hold"},
            {"Toggle", "toggle"},
            {"Release (off while held)", "release"},
        })
        AddLabel(p, "Always on = checkbox only, no key")
    end)
end

OpenSettingsPopup = function(name, build)
    OpenPopup(name, 230, build)
end

-- The picker is its own panel, so the settings popup it was opened from stays where it is. It
-- goes to the right of that popup (left when there is no room); a click anywhere else closes it.
OpenColorPopup = function(title, build)
    if not IsValid(menu) then return end
    if IsValid(colorPopup) then colorPopup:Remove() end

    local width = 230
    local mx, my = gui.MouseX(), gui.MouseY()

    local p = vgui.Create("Panel", menu)
    colorPopup = p
    p:SetSize(width, 60)
    p.cy = 28

    p.Paint = function(self, w, h)
        surface.SetDrawColor(C.tabBg)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        surface.SetDrawColor(C.accent)
        surface.DrawRect(1, 1, w - 2, 1)
        draw.SimpleText(title, "NyxUIBold", 10, 8, C.textHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    build(p)
    p:SetTall(p.cy + 6)

    local x, y
    if IsValid(popup) then
        local px, py = popup:GetPos()
        x, y = px + popup:GetWide() + 6, py
        if x + width > menu:GetWide() - 4 then x = px - width - 6 end
    else
        x, y = menu:ScreenToLocal(mx, my)
    end

    p:SetPos(
        math.Clamp(x, 4, menu:GetWide() - width - 4),
        math.Clamp(y, 4, menu:GetTall() - p:GetTall() - 4)
    )
    p:MoveToFront()

    -- fades in (and drifts up a little) when it opens
    p.fade = 0
    p:SetAlpha(0)
    local popupY = p:GetY()

    p.wasDown = true
    p.Think = function(self)
        self.fade = ANIM.Step(self.fade, 1, 14)
        self:SetAlpha(255 * self.fade)
        self:SetY(popupY + (1 - self.fade) * 8)

        local down = input.IsMouseDown(MOUSE_LEFT) or input.IsMouseDown(MOUSE_RIGHT)

        if down and not self.wasDown and not CU.Inside(self, gui.MouseX(), gui.MouseY()) then
            self:Remove()
            if colorPopup == self then colorPopup = nil end
            return
        end

        self.wasDown = down
    end

    WrapPaint(p)
end

-- keybind capture by polling: wait until everything is released, then take the first press.
-- Only real keys are scanned: KEY_CAPSLOCKTOGGLE / NUMLOCKTOGGLE / SCROLLLOCKTOGGLE (104-106)
-- read as "down" for as long as the lock is on, which used to keep the bind from ever arming.
local function PollBinding()
    if not binding then return end

    local pressed
    for k = KEY_0, KEY_F12 do
        if input.IsKeyDown(k) then pressed = k break end
    end
    if not pressed then
        for k = MOUSE_LEFT, MOUSE_5 do
            if input.IsMouseDown(k) then pressed = k break end
        end
    end

    if not binding.armed then
        if not pressed then binding.armed = true end
        return
    end

    if pressed then FinishBinding(pressed) end
end

-- background -------------------------------------------------------------------
-- A picture behind the whole menu, animated. The bundled one (a point-cloud wave) is written to
-- data/nyx/bg/ on first run; anything else dropped into that folder (png / jpg) shows up in the
-- list, or can be fetched with the console command  nyx_bg_url <link> [name].
-- Like the configs, it lives in its own block and only exports BG.

local BG = {}

do
    local DIR = "nyx/bg"
    local DEFAULT_FILE = "nyx_wave.jpg"
    local PER_PAGE = 6

    -- the bundled picture, base64 of a jpeg
    local DEFAULT_B64 = table.concat({
        "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAQCAwMDAgQDAwMEBAQEBQkGBQUFBQsICAYJDQsNDQ0LDAwOEBQRDg8TDwwMEhgSExUWFxcXDhEZGx",
        "kWGhQWFxb/2wBDAQQEBAUFBQoGBgoWDwwPFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhb/wAARCADR",
        "Af4DASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhBy",
        "JxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKT",
        "lJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAA",
        "AAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRom",
        "JygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExc",
        "bHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD5D+PXjPWNS+KV2Vu5o4tJu/LtIwx2xvE2N4HQncCc46YrB+J3",
        "jzxd8SPFP/CReNNam1bVDAlt9olVVbYudq4UAYGT+dbX7S3jTVvGnxMkOrRWUf8AYEH9i2gtLZYQYIJJNrPt+85LMSx5OR6VwUfT8++Kubbk7k",
        "U0lFWOx/4Vd41HwX/4Ws2lovhY6h/Z63jXMYZp8Z2iPdvI98Yrjuf8mrp1vVv7CGh/2neHTBN54sjcP5AkxjeI87d3viut+BWmfDfVtX1NPiVr",
        "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",
    })

    local mats = {}            -- file name -> IMaterial, or false when it would not load
    local files = {}           -- picture names currently in the folder
    local page = 1
    local status = "ready"

    local function CleanName(name)
        name = string.gsub(tostring(name or ""), "[^%w_%-]", "")
        return string.sub(name, 1, 40)
    end

    local function EnsureDefault()
        file.CreateDir("nyx")
        file.CreateDir(DIR)

        local path = DIR .. "/" .. DEFAULT_FILE
        if not file.Exists(path, "DATA") then
            local raw = util.Base64Decode(DEFAULT_B64)
            if raw and #raw > 0 then file.Write(path, raw) end
        end
    end

    function BG.Refresh()
        EnsureDefault()

        files = {}
        for _, ext in ipairs({"png", "jpg", "jpeg"}) do
            for _, f in ipairs((file.Find(DIR .. "/*." .. ext, "DATA"))) do
                files[#files + 1] = f
            end
        end
        table.sort(files)

        -- pictures that failed to load once get another chance
        for name, m in pairs(mats) do
            if m == false then mats[name] = nil end
        end

        local pages = math.max(1, math.ceil(#files / PER_PAGE))
        if page > pages then page = 1 end
    end

    function BG.NextPage()
        local pages = math.max(1, math.ceil(#files / PER_PAGE))
        page = page % pages + 1
    end

    function BG.Status()
        return status
    end

    local function GetMat(name)
        if not name or name == "" then return nil end

        local m = mats[name]
        if m == nil then
            local rel = DIR .. "/" .. name

            m = Material("data/" .. rel, "smooth")
            if not m or m:IsError() then m = Material("../data/" .. rel, "smooth") end
            if not m or m:IsError() then m = false end

            mats[name] = m
        end

        return m or nil
    end

    -- Called from the menu's Paint with the frame size. The picture covers the frame with a
    -- margin, and the motion is a slow pan across it plus a breathing zoom; "pulse" breathes
    -- the opacity, a few twinkling dots sit on top.
    function BG.Draw(w, h)
        local b = cfg.bg
        if not b.enabled then return end

        local t = CurTime() * b.speed
        local moving = b.mode == "drift" or b.mode == "both"
        local pulsing = b.mode == "pulse" or b.mode == "both"

        local alpha = b.opacity
        if pulsing then alpha = alpha * (1 + 0.3 * math.sin(t * 1.6)) end
        alpha = math.Clamp(alpha, 0, 1)

        local m = GetMat(b.file)
        if m then
            local iw, ih = m:Width(), m:Height()
            if iw > 0 and ih > 0 then
                local scale = math.max(w / iw, h / ih) * 1.1
                local panX, panY, zoom = 0.5, 0.5, 0

                if moving then
                    panX = 0.5 + 0.5 * math.sin(t * 0.12)
                    panY = 0.5 + 0.5 * math.sin(t * 0.09 + 1)
                    zoom = 0.07 * (0.5 + 0.5 * math.sin(t * 0.3))
                end

                scale = scale * (1 + zoom)
                local dw, dh = iw * scale, ih * scale

                surface.SetMaterial(m)
                surface.SetDrawColor(b.r, b.g, b.b, 255 * alpha)
                surface.DrawTexturedRect(-(dw - w) * panX, -(dh - h) * panY, dw, dh)
            end
        end

        if b.twinkle then
            for i = 1, 70 do
                local ph = i * 1.7
                local fx = (i * 0.6180339) % 1
                local fy = (i * 0.7548776 + 0.31) % 1
                local tw = 0.5 + 0.5 * math.sin(t * (0.8 + (i % 5) * 0.3) + ph)

                local x = (fx * w + math.sin(t * 0.2 + ph) * 6) % w
                local y = (fy * h + math.cos(t * 0.17 + ph) * 6) % h

                surface.SetDrawColor(b.r, b.g, b.b, 255 * math.min(1, alpha + 0.15) * tw)
                surface.DrawRect(x, y, 2, 2)
            end
        end
    end

    function BG.Select(name)
        cfg.bg.file = name
        cfg.bg.enabled = true
        status = "using " .. name
    end

    -- onSaved(fileName) runs after a successful download; without it the picture becomes the
    -- menu background
    function BG.Download(url, name, onSaved)
        status = "downloading..."

        http.Fetch(url, function(body, size, headers, code)
            if code ~= 200 or #body < 100 then
                status = "download failed (" .. tostring(code) .. ")"
                return
            end

            if #body > 12 * 1024 * 1024 then
                status = "file is too big"
                return
            end

            local ext
            if string.sub(body, 1, 4) == "\137PNG" then
                ext = "png"
            elseif string.sub(body, 1, 2) == "\255\216" then
                ext = "jpg"
            end

            if not ext then
                status = "that is not a png / jpg"
                return
            end

            name = CleanName(name)
            if name == "" then name = "img_" .. os.time() end

            local full = name .. "." .. ext

            EnsureDefault()
            file.Write(DIR .. "/" .. full, body)

            mats[full] = nil
            BG.Refresh()

            if onSaved then
                status = "saved " .. full
                onSaved(full)
            else
                BG.Select(full)
            end
        end, function(err)
            status = "download failed: " .. tostring(err)
        end)
    end

    -- material of a picture in the folder (nil when it won't load); also used for the sky picture
    BG.Mat = GetMat

    -- the picture list, one page of it at a time. By default it picks the menu background;
    -- tbl / key / onSelect let another feature (the sky picture) use the same list.
    function BG.AddPicker(g, tbl, key, onSelect)
        tbl = tbl or cfg.bg
        key = key or "file"
        onSelect = onSelect or BG.Select

        local rowH = 15
        local p = WidgetPanel(g, 16 + 8 + PER_PAGE * rowH)
        p:SetCursor("hand")

        local function rowAt(self, y)
            local i = math.floor((y - 16 - 4) / rowH) + 1
            if i < 1 or i > PER_PAGE then return nil end
            return (page - 1) * PER_PAGE + i
        end

        p.Paint = function(self, w, h)
            local pages = math.max(1, math.ceil(#files / PER_PAGE))
            draw.SimpleText(string.format("Picture  (%d / %d)", page, pages), "NyxUI", 0, 0, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            surface.SetDrawColor(C.field)
            surface.DrawRect(0, 16, w, h - 16)
            surface.SetDrawColor(C.groupBorder)
            surface.DrawOutlinedRect(0, 16, w, h - 16, 1)

            local hover
            if self:IsHovered() then
                local _, my = self:CursorPos()
                hover = rowAt(self, my)
            end

            for i = 1, PER_PAGE do
                local idx = (page - 1) * PER_PAGE + i
                local name = files[idx]
                if not name then break end

                local col = C.textDim
                if name == tbl[key] then
                    col = C.accent
                elseif idx == hover then
                    col = C.textHi
                end

                draw.SimpleText(string.sub(name, 1, 30), "NyxUI", 8, 16 + 4 + (i - 1) * rowH, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
        end

        p.OnMousePressed = function(self, code)
            if code ~= MOUSE_LEFT then return end

            local _, my = self:CursorPos()
            local idx = rowAt(self, my)
            if idx and files[idx] then onSelect(files[idx]) end
        end
    end

    function BG.DeleteSelected()
        local name = cfg.bg.file
        if not name or name == "" then return end

        file.Delete(DIR .. "/" .. name)
        mats[name] = nil
        BG.Refresh()

        if not table.HasValue(files, name) then
            cfg.bg.file = files[1] or DEFAULT_FILE
        end

        status = "deleted " .. name
    end

    concommand.Add("nyx_bg_url", function(ply, cmd, args)
        if not args[1] or args[1] == "" then
            print("usage: nyx_bg_url <link to a png / jpg> [name]")
            return
        end

        BG.Download(args[1], args[2])
    end)

    concommand.Add("nyx_bg", function(ply, cmd, args)
        local name = args[1]
        if not name or not table.HasValue(files, name) then
            print("[nyx] no such picture, see nyx_bg_list")
            return
        end

        BG.Select(name)
    end)

    concommand.Add("nyx_bg_list", function()
        BG.Refresh()
        print("[nyx] pictures in data/" .. DIR .. ":")
        for _, f in ipairs(files) do print("   " .. f) end
    end)

    BG.Refresh()
end

-- sky picture -------------------------------------------------------------------
-- Your own picture as the sky: a sphere around the camera, textured with the picture, drawn
-- right after the engine's 2D sky (so it covers whatever the map or an env_skypaint drew).
-- The pictures come from the same folder as the menu background, data/nyx/bg/. A normal photo
-- gets wrapped around the full 360 degrees; a 2:1 panorama looks right as it is.

local SKYPIC = {status = "pick a picture"}

do
    AddHook("PostDraw2DSkyBox", "skypic", function()
        local w = cfg.world
        if not w.skyPic or w.skyPicFile == "" or IsHidden() then return end

        local m = BG.Mat(w.skyPicFile)
        if not m then
            SKYPIC.status = "can't load " .. w.skyPicFile
            return
        end

        local vs = render.GetViewSetup()
        local ang = Angle(vs.angles.p, vs.angles.y + CurTime() * w.skyPicRot, vs.angles.r)
        local b = math.Clamp(w.skyPicBright * 255, 0, 255)

        cam.Start3D(vector_origin, ang, vs.fov, 0, 0, ScrW(), ScrH(), 1, 5000)
            render.SuppressEngineLighting(true)
            render.SetMaterial(m)
            render.DrawSphere(vector_origin, -1000, 32, 32, Color(b, b, b, 255))
            render.SuppressEngineLighting(false)
        cam.End3D()
    end)

    function SKYPIC.Select(name)
        cfg.world.skyPicFile = name
        cfg.world.skyPic = true
        SKYPIC.status = "using " .. name
    end

    function SKYPIC.Status()
        return SKYPIC.status
    end

    -- nyx_sky_url <link to a png / jpg> [name]: fetch a picture and put it on the sky
    concommand.Add("nyx_sky_url", function(ply, cmd, args)
        if not args[1] or args[1] == "" then
            print("usage: nyx_sky_url <link to a png / jpg> [name]")
            return
        end

        BG.Download(args[1], args[2], SKYPIC.Select)
    end)
end

-- configs ---------------------------------------------------------------------
-- data/nyx/<name>.json holds every setting plus the feature binds. The menu works on ten fixed
-- slots; the console commands nyx_config_save / nyx_config_load / nyx_config_list take any name.

-- The whole system sits in its own block and only exports CFGS: the file is close to Lua's limit
-- of 200 local variables in one chunk, and nothing in here has to stay in scope afterwards.
local CFGS = {}

do
local CONFIG_DIR = "nyx"
local CONFIG_SLOTS = 10

local defaultCfg = table.Copy(cfg)       -- what "Reset" goes back to (nothing has been touched yet)
local configSlot = 1
local configStatus = "ready"
local slotUsed = {}

local function CleanName(name)
    name = string.gsub(tostring(name or ""), "[^%w_%-]", "")
    return string.sub(name, 1, 32)
end

local function ConfigPath(name)
    return CONFIG_DIR .. "/" .. name .. ".json"
end

local function RefreshSlots()
    for i = 1, CONFIG_SLOTS do
        slotUsed[i] = file.Exists(ConfigPath("config_" .. i), "DATA")
    end
end

RefreshSlots()

-- name of the top level cfg table that tbl is (binds are stored against it)
local function CfgTableName(tbl)
    for name, t in pairs(cfg) do
        if t == tbl then return name end
    end
end

-- copy only the values that exist in dst with the same type, so an old or edited file can't
-- add junk or break a field
local function MergeInto(dst, src)
    for k, v in pairs(src) do
        local cur = dst[k]

        if type(cur) == "table" and type(v) == "table" then
            MergeInto(cur, v)
        elseif cur ~= nil and type(cur) == type(v) then
            dst[k] = v
        end
    end
end

local function ClearBinds()
    for _, e in ipairs(bindList) do
        e.mode = "always"
        e.code = nil
        e.wasDown = false
    end
end

local function SaveConfig(name)
    local binds = {}

    for _, e in ipairs(bindList) do
        local tname = CfgTableName(e.tbl)
        if tname and e.mode ~= "always" and e.code then
            binds[#binds + 1] = {t = tname, k = e.key, code = e.code, mode = e.mode, name = e.name}
        end
    end

    file.CreateDir(CONFIG_DIR)
    file.Write(ConfigPath(name), util.TableToJSON({version = 1, cfg = cfg, binds = binds}, true))
    RefreshSlots()
end

-- returns true, or false + the reason
local function LoadConfig(name)
    local raw = file.Read(ConfigPath(name), "DATA")
    if not raw then return false, "no such config" end

    local data = util.JSONToTable(raw)
    if not istable(data) or not istable(data.cfg) then return false, "file is not readable" end

    MergeInto(cfg, data.cfg)

    ClearBinds()
    for _, b in ipairs(data.binds or {}) do
        local tbl = cfg[b.t]
        if istable(tbl) and tbl[b.k] ~= nil and isnumber(b.code) and isstring(b.mode) then
            local e = GetBind(tbl, b.k, true)
            e.code, e.mode = b.code, b.mode
            e.name = isstring(b.name) and b.name or (b.t .. "." .. b.k)
        end
    end

    return true
end

local function ResetConfig()
    MergeInto(cfg, defaultCfg)
    ClearBinds()
end

local function SlotName(i)
    return "config_" .. i
end

-- the ten-row slot picker
local function AddConfigSlots(g)
    local rowH = 15
    local p = WidgetPanel(g, 16 + 8 + CONFIG_SLOTS * rowH)
    p:SetCursor("hand")

    local function rowAt(self, y)
        local i = math.floor((y - 16 - 4) / rowH) + 1
        if i >= 1 and i <= CONFIG_SLOTS then return i end
    end

    p.Paint = function(self, w, h)
        draw.SimpleText("Slot", "NyxUI", 0, 0, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        surface.SetDrawColor(C.field)
        surface.DrawRect(0, 16, w, h - 16)
        surface.SetDrawColor(C.groupBorder)
        surface.DrawOutlinedRect(0, 16, w, h - 16, 1)

        local hover
        if self:IsHovered() then
            local _, my = self:CursorPos()
            hover = rowAt(self, my)
        end

        for i = 1, CONFIG_SLOTS do
            local col = C.textDim
            if i == configSlot then
                col = C.accent
            elseif i == hover then
                col = C.textHi
            end

            local label = string.format("%2d   %s%s", i, SlotName(i), slotUsed[i] and "   [saved]" or "")
            draw.SimpleText(label, "NyxUI", 8, 16 + 4 + (i - 1) * rowH, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end

    p.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end
        local _, my = self:CursorPos()
        local i = rowAt(self, my)
        if i then configSlot = i end
    end
end

concommand.Add("nyx_config_save", function(ply, cmd, args)
    local name = CleanName(args[1])
    if name == "" then print("usage: nyx_config_save <name>") return end

    SaveConfig(name)
    configStatus = "saved " .. name
    print("[nyx] saved " .. ConfigPath(name))
end)

concommand.Add("nyx_config_load", function(ply, cmd, args)
    local name = CleanName(args[1])
    if name == "" then print("usage: nyx_config_load <name>") return end

    local ok, why = LoadConfig(name)
    configStatus = ok and ("loaded " .. name) or (name .. ": " .. why)
    print("[nyx] " .. configStatus)
end)

concommand.Add("nyx_config_list", function()
    local files = file.Find(CONFIG_DIR .. "/*.json", "DATA")
    print("[nyx] configs in data/" .. CONFIG_DIR .. ":")
    for _, f in ipairs(files) do print("   " .. string.StripExtension(f)) end
end)

-- what the menu uses
CFGS.AddSlots = AddConfigSlots
CFGS.Status = function() return configStatus end

CFGS.Save = function()
    SaveConfig(SlotName(configSlot))
    configStatus = "saved slot " .. configSlot
end

CFGS.Load = function()
    local ok, why = LoadConfig(SlotName(configSlot))
    configStatus = ok and ("loaded slot " .. configSlot) or ("slot " .. configSlot .. ": " .. why)
end

CFGS.Delete = function()
    file.Delete(ConfigPath(SlotName(configSlot)))
    RefreshSlots()
    configStatus = "deleted slot " .. configSlot
end

CFGS.Reset = function()
    ResetConfig()
    configStatus = "defaults restored"
end

end   -- configs

-- window --------------------------------------------------------------------

-- player list ----------------------------------------------------------------------
-- Left: every player on the server in one list (friend = green nick, target = red nick).
-- Right: profile and settings of the selected player: friend / target flags, a resolver override
-- for just that player, steam / team / group / language / position info.
--   friend : never picked by the aimbots, drawn green
--   target : drawn red, picked first, and the only ones when "Target only" is on
-- Everything is kept in data/nyx/players.json (read once on load), independent of the configs.

local PL = {}

do
    local FILE = "nyx/players.json"
    local OLD_FILE = "nyx/friends.json"          -- first version of the list: friends only
    local PER_PAGE = 22

    local selKey = nil                           -- key (SteamID64 / bot nick) of the selected player
    local status = "ready"

    -- persistence -------------------------------------------------------------------

    local function Save()
        local out = {friends = {}, targets = {}, overrides = {}}

        for key, rec in pairs(FR.list) do
            out.friends[#out.friends + 1] = {key = tostring(key), name = tostring(rec.name or key)}
        end

        for key, rec in pairs(FR.targets) do
            out.targets[#out.targets + 1] = {key = tostring(key), name = tostring(rec.name or key)}
        end

        for key, rec in pairs(FR.over) do
            out.overrides[#out.overrides + 1] = {
                key = tostring(key), name = tostring(rec.name or key),
                on = rec.on and true or false, yaw = rec.yaw or 0,
                pitchOn = rec.pitchOn and true or false, pitch = rec.pitch or 0,
            }
        end

        file.CreateDir("nyx")
        file.Write(FILE, util.TableToJSON(out))
    end

    local function Load()
        local raw = file.Read(FILE, "DATA")
        local data = raw and util.JSONToTable(raw)

        if istable(data) then
            for _, e in ipairs(data.friends or {}) do
                if istable(e) and e.key then FR.list[tostring(e.key)] = {name = tostring(e.name or e.key)} end
            end

            for _, e in ipairs(data.targets or {}) do
                if istable(e) and e.key then FR.targets[tostring(e.key)] = {name = tostring(e.name or e.key)} end
            end

            for _, e in ipairs(data.overrides or {}) do
                if istable(e) and e.key then
                    FR.over[tostring(e.key)] = {
                        name = tostring(e.name or e.key), on = e.on == true, yaw = tonumber(e.yaw) or 0,
                        pitchOn = e.pitchOn == true, pitch = tonumber(e.pitch) or 0,
                    }
                end
            end

            return
        end

        -- the first version only had friends
        local old = file.Read(OLD_FILE, "DATA")
        local list = old and util.JSONToTable(old)
        if istable(list) then
            for _, e in ipairs(list) do
                if istable(e) and e.key then FR.list[tostring(e.key)] = {name = tostring(e.name or e.key)} end
            end
        end
    end

    Load()

    -- helpers --------------------------------------------------------------------------

    local function PlayerByKey(key)
        if not key then return nil end

        for _, v in ipairs(player.GetAll()) do
            if FR.Key(v) == key then return v end
        end
    end

    local function SelectedName()
        local v = PlayerByKey(selKey)
        if v then return v:Nick() end

        local rec = selKey and (FR.list[selKey] or FR.targets[selKey] or FR.over[selKey])
        return rec and rec.name or tostring(selKey)
    end

    local function OverrideOf(key, create)
        local ov = FR.over[key]
        if not ov and create then
            ov = {name = SelectedName(), on = false, yaw = 0, pitchOn = false, pitch = 0}
            FR.over[key] = ov
        end
        return ov
    end

    -- A proxy so ordinary checkboxes / sliders edit the selected player. A friend is never a
    -- target and the other way round, so setting one clears the other.
    local sel = setmetatable({}, {
        __index = function(_, k)
            if not selKey then return (k == "ovYaw" or k == "ovPitch") and 0 or false end

            if k == "friend" then return FR.list[selKey] ~= nil end
            if k == "target" then return FR.targets[selKey] ~= nil end

            local ov = FR.over[selKey]
            if k == "ovOn" then return ov and ov.on or false end
            if k == "ovYaw" then return ov and ov.yaw or 0 end
            if k == "ovPitchOn" then return ov and ov.pitchOn or false end
            if k == "ovPitch" then return ov and ov.pitch or 0 end
        end,

        __newindex = function(_, k, v)
            if not selKey then return end
            local name = SelectedName()

            if k == "friend" then
                FR.list[selKey] = v and {name = name} or nil
                if v then FR.targets[selKey] = nil end
            elseif k == "target" then
                FR.targets[selKey] = v and {name = name} or nil
                if v then FR.list[selKey] = nil end
            elseif k == "ovOn" then
                OverrideOf(selKey, true).on = v and true or false
            elseif k == "ovYaw" then
                OverrideOf(selKey, true).yaw = v
            elseif k == "ovPitchOn" then
                OverrideOf(selKey, true).pitchOn = v and true or false
            elseif k == "ovPitch" then
                OverrideOf(selKey, true).pitch = v
            end

            Save()
        end,
    })

    -- the left list: one column, one line per player -------------------------------------

    local function PlayerRows()
        local rows = {}

        for _, v in ipairs(player.GetAll()) do
            rows[#rows + 1] = {key = FR.Key(v), text = v:Nick(), friend = FR.Is(v), target = FR.IsTarget(v)}
        end

        table.sort(rows, function(a, b) return string.lower(a.text) < string.lower(b.text) end)
        return rows
    end

    local page = 1

    local function AddPlayerList(g)
        local rowH = 15
        local p = WidgetPanel(g, 16 + 8 + PER_PAGE * rowH)
        p:SetCursor("hand")

        local function rowAt(y)
            local i = math.floor((y - 16 - 4) / rowH) + 1
            if i >= 1 and i <= PER_PAGE then return i end
        end

        p.Paint = function(self, w, h)
            local rows = PlayerRows()
            local pages = math.max(1, math.ceil(#rows / PER_PAGE))
            if page > pages then page = pages end

            draw.SimpleText(string.format("Players  (%d / %d)", page, pages), "NyxUI", 0, 0, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            surface.SetDrawColor(C.field)
            surface.DrawRect(0, 16, w, h - 16)
            surface.SetDrawColor(C.groupBorder)
            surface.DrawOutlinedRect(0, 16, w, h - 16, 1)

            local hover
            if self:IsHovered() then
                local _, my = self:CursorPos()
                hover = rowAt(my)
            end

            for i = 1, PER_PAGE do
                local row = rows[(page - 1) * PER_PAGE + i]
                if not row then break end

                local y = 16 + 4 + (i - 1) * rowH

                -- nick colour: target red, friend green, everyone else grey (white on hover)
                local col = C.textDim
                if row.target then
                    col = FR.targetColor
                elseif row.friend then
                    col = FR.color
                elseif i == hover then
                    col = C.textHi
                end

                if row.key == selKey then
                    surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 45)
                    surface.DrawRect(1, y - 1, w - 2, rowH)
                    surface.SetDrawColor(C.accent)
                    surface.DrawRect(1, y - 1, 2, rowH)

                    if col == C.textDim then col = C.textHi end
                end

                draw.SimpleText(string.sub(row.text, 1, 28), "NyxUI", 8, y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
        end

        p.OnMousePressed = function(self, code)
            if code ~= MOUSE_LEFT then return end

            local _, my = self:CursorPos()
            local i = rowAt(my)
            local row = i and PlayerRows()[(page - 1) * PER_PAGE + i]
            if row then selKey = row.key end
        end
    end

    -- the right side: profile block with the avatar ---------------------------------------

    local PROFILE_H = 164

    local function AddProfile(g)
        local p = WidgetPanel(g, PROFILE_H)

        -- Steam avatar; AvatarImage is the engine's own widget
        local av = vgui.Create("AvatarImage", p)
        av:SetSize(64, 64)
        av:SetPos(0, 0)
        av:SetVisible(false)

        local shown = false
        p.Think = function(self)
            local v = PlayerByKey(selKey)
            local key = v and selKey or false

            if shown ~= key then
                shown = key

                if v then
                    av:SetPlayer(v, 64)
                    av:SetVisible(true)
                else
                    av:SetVisible(false)
                end
            end
        end

        local function Line(self, label, value, x, y, col)
            draw.SimpleText(label, "NyxUISmall", x, y, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(value, "NyxUISmall", x + 78, y, col or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        p.Paint = function(self, w, h)
            surface.SetDrawColor(C.groupBorder)
            surface.DrawOutlinedRect(0, 0, 64, 64, 1)

            local v = PlayerByKey(selKey)
            if not v then
                draw.SimpleText("Select a player in the list", "NyxUI", 74, 24, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                return
            end

            local nameCol = C.textHi
            if FR.IsTarget(v) then
                nameCol = FR.targetColor
            elseif FR.Is(v) then
                nameCol = FR.color
            end

            local tcol = team.GetColor(v:Team())
            local pos = v:GetPos()
            local ang = v:EyeAngles()
            local lang = v:GetInfo("gmod_language")
            if not lang or lang == "" then lang = "unknown" end

            -- next to the avatar
            draw.SimpleText(v:Nick(), "NyxUIBold", 74, 0, nameCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            Line(self, "SteamID64", v:SteamID64() or "bot", 74, 17)
            Line(self, "SteamID", v:SteamID(), 74, 31)
            Line(self, "Team", string.format("%s (%d)", team.GetName(v:Team()), v:Team()), 74, 45, tcol)

            -- below it
            Line(self, "Usergroup", v:GetUserGroup(), 0, 72)
            Line(self, "Gamemode", engine.ActiveGamemode(), 0, 87)
            Line(self, "Language", lang, 0, 102)
            Line(self, "Position", string.format("%.0f   %.0f   %.0f", pos.x, pos.y, pos.z), 0, 117)
            Line(self, "Eye angles", string.format("%.1f   %.1f   %.1f", ang.p, ang.y, ang.r), 0, 132)
            Line(self, "Health", string.format("%d   armor %d   ping %d", v:Health(), v:Armor(), v:Ping()), 0, 147)
        end
    end

    -- buttons ----------------------------------------------------------------------------

    local function AddSteamFriends()
        local added = 0

        for _, v in ipairs(player.GetAll()) do
            if v ~= LocalPlayer() and v:GetFriendStatus() == "friend" and not FR.Is(v) then
                FR.list[FR.Key(v)] = {name = v:Nick()}
                FR.targets[FR.Key(v)] = nil
                added = added + 1
            end
        end

        status = added .. " Steam friends added"
        Save()
    end

    local function CopySteamID()
        local v = PlayerByKey(selKey)
        if not v then status = "pick a player first" return end

        SetClipboardText(v:SteamID64() or v:Nick())
        status = "copied " .. v:Nick()
    end

    local function ClearFriends()
        table.Empty(FR.list)
        status = "friends cleared"
        Save()
    end

    local function ClearTargets()
        table.Empty(FR.targets)
        status = "targets cleared"
        Save()
    end

    function PL.BuildPage(page_)
        local left = {page = page_, x = 0, y = 0, w = 214}
        local right = {page = page_, x = 230, y = 0, w = math.max(page_:GetWide() - 230, 200), kind = "fill"}

        local g = NewGroup(left, "Players")
        AddPlayerList(g)
        AddButton(g, "Add all Steam friends", AddSteamFriends)
        AddButton(g, "Next page", function()
            local pages = math.max(1, math.ceil(#PlayerRows() / PER_PAGE))
            page = page % pages + 1
        end)
        AddLabel(g, function() return status end, C.accent)
        EndGroup(g)

        g = NewGroup(right, "Player settings")
        AddProfile(g)
        AddCheck(g, "Friend  (aimbots never target, green)", sel, "friend")
        AddCheck(g, "Target  (red, preferred)", sel, "target")
        AddCheck(g, "Override resolver for this player", sel, "ovOn")
        AddSlider(g, "Override yaw", sel, "ovYaw", -180, 180, 0, "\194\176")
        AddCheck(g, "Override pitch too", sel, "ovPitchOn")
        AddSlider(g, "Override pitch", sel, "ovPitch", -89, 89, 0, "\194\176")
        AddButton(g, "Copy SteamID64", CopySteamID)
        AddButton(g, "Clear all friends", ClearFriends)
        AddButton(g, "Clear all targets", ClearTargets)
        EndGroup(g)
    end
end

-- entities tab ------------------------------------------------------------------------
-- Left: every entity in range (players, NPCs, weapons, props, ... by the filter), nearest first.
-- Click selects (halo on it), clicking the selected one again or "Preview" opens the viewer.
-- The viewer is a full 3D copy: a clientside model of the same model with the same skin,
-- bodygroups, materials, colour, scale and - copied bone by bone - the exact pose, plus the
-- weapon in its hands. With "live" it keeps following the real entity; without it, or once the
-- real one is gone, it stays as it was. Brush entities (doors, func_*) have no model file to copy,
-- so the real one is drawn in the viewer instead.
-- Lives in PL.EV: the main chunk is at Lua's 200 locals.
PL.EV = {}

do
    local EV = PL.EV
    local ev = cfg.entview

    local PER_PAGE = 18
    local TITLE_H, INFO_H = 22, 74
    local rows, rowsNext, page = {}, 0, 1
    local viewer = nil

    EV.sel = nil
    EV.status = "click an entity, then Preview"

    local PLAYER_COL = Color(120, 170, 255)
    local ANY_COL = Color(200, 200, 200)
    local GRID_COL = Color(255, 255, 255, 22)

    local FILTERS = {
        {"Everything", "all"}, {"Players", "player"}, {"NPCs", "npc"}, {"Weapons", "weapon"},
        {"Props", "prop"}, {"Vehicles", "vehicle"}, {"Items / ammo", "item"}, {"Doors", "door"},
        {"Scripted", "other"}, {"Any model", "any"},
    }

    -- list ------------------------------------------------------------------------------

    -- category of e for the list; "any" = has a model but is none of the ESP categories
    local function Category(e, me)
        if e == me then return nil end
        if e:IsPlayer() then return ev.showPlayers and "player" or nil end   -- the "Show players" switch

        local cat = WorldCategory(e)
        if cat then return cat end

        local m = e:GetModel()
        if isstring(m) and m ~= "" and not e:IsWeapon() and not IsValid(e:GetParent())
            and e ~= me:GetViewModel(0) and e:GetClass() ~= "gmod_hands" then
            return "any"
        end
    end

    local function RowText(e, cat, key)
        if cat == "player" then return e:Nick() end
        if key and MV.entNames[key] then return MV.entNames[key] end
        if cat == "any" then
            local mdl = e:GetModel() or ""
            return e:GetClass() .. "  " .. (string.match(mdl, "([^/]+)%.mdl$") or "")
        end
        return WorldLabel(e, cat)
    end

    -- grouping, names, entity chams --------------------------------------------------------
    -- Entities of the same kind (MV.EntKey) collapse into one row "name  xN" that opens on a
    -- click. Right click on any row: chams on that entity / on every one of its kind, rename.
    -- Names and per-kind chams are saved in data/nyx/entities.json; chams on one entity only
    -- last as long as it exists (entity indices are reused).
    EV.chamEnt = setmetatable({}, {__mode = "k"})   -- entity -> true
    EV.chamKind = {}                                 -- MV.EntKey -> true
    EV.espEnt = setmetatable({}, {__mode = "k"})    -- the same two for the wallhack
    EV.espKind = {}
    EV.expanded = {}                                 -- group key -> true
    EV.total = 0
    EV.DATA_FILE = "nyx/entities.json"     -- a field, not a local: this block shares the main chunk's 200

    function EV.SaveData()
        local names, kinds, esp = {}, {}, {}
        for k, v in pairs(MV.entNames) do names[#names + 1] = {key = k, name = v} end
        for k in pairs(EV.chamKind) do kinds[#kinds + 1] = k end
        for k in pairs(EV.espKind) do esp[#esp + 1] = k end

        file.CreateDir("nyx")
        file.Write(EV.DATA_FILE, util.TableToJSON({names = names, chams = kinds, esp = esp}, true))
    end

    do
        local data = util.JSONToTable(file.Read(EV.DATA_FILE, "DATA") or "")
        if istable(data) then
            for _, n in ipairs(data.names or {}) do
                if isstring(n.key) and isstring(n.name) then MV.entNames[n.key] = n.name end
            end
            for _, k in ipairs(data.chams or {}) do
                if isstring(k) then EV.chamKind[k] = true end
            end
            for _, k in ipairs(data.esp or {}) do
                if isstring(k) then EV.espKind[k] = true end
            end
        end
    end

    function EV.Refresh()
        rowsNext = 0
        EV.chamNext = 0
        EV.espNext = 0
    end

    function EV.ToggleEspEnt(e)
        EV.espEnt[e] = not EV.espEnt[e] or nil
        EV.Refresh()
    end

    function EV.ToggleEspKind(key)
        EV.espKind[key] = not EV.espKind[key] or nil
        EV.SaveData()
        EV.Refresh()
    end

    function EV.HasEsp(r)
        if r.group then return EV.espKind[r.key] or false end
        return EV.espEnt[r.ent] or (r.key and EV.espKind[r.key]) or false
    end

    function EV.Rename(key, current)
        Derma_StringRequest("Rename", "New name for " .. key .. "\n(leave empty for the original)",
            MV.entNames[key] or current or "", function(txt)
                txt = string.Trim(txt or "")
                MV.entNames[key] = txt ~= "" and string.sub(txt, 1, 48) or nil
                EV.SaveData()
                EV.Refresh()
            end)
    end

    function EV.ToggleChamEnt(e)
        EV.chamEnt[e] = not EV.chamEnt[e] or nil
        EV.Refresh()
    end

    function EV.ToggleChamKind(key)
        EV.chamKind[key] = not EV.chamKind[key] or nil
        EV.SaveData()
        EV.Refresh()
    end

    function EV.HasChams(r)
        if r.group then return EV.chamKind[r.key] or false end
        return EV.chamEnt[r.ent] or (r.key and EV.chamKind[r.key]) or false
    end

    -- right-click menu of a row
    function EV.RowMenu(r)
        local dm = DermaMenu()

        if r.group then
            local key = r.key
            dm:AddOption(EV.expanded[key] and "Collapse" or "Expand (" .. r.count .. ")", function()
                EV.expanded[key] = not EV.expanded[key] or nil
                EV.Refresh()
            end)
            dm:AddOption((EV.chamKind[key] and "Chams off" or "Chams on") .. " for all " .. r.count, function()
                EV.ToggleChamKind(key)
            end)
            dm:AddOption((EV.espKind[key] and "Wallhack off" or "Wallhack on") .. " for all " .. r.count, function()
                EV.ToggleEspKind(key)
            end)
            dm:AddOption("Rename...", function() EV.Rename(key, r.text) end)
            if MV.entNames[key] then
                dm:AddOption("Original name", function()
                    MV.entNames[key] = nil
                    EV.SaveData()
                    EV.Refresh()
                end)
            end
        else
            local e = r.ent
            if not IsValid(e) then return end

            if not e:IsPlayer() then
                dm:AddOption(EV.chamEnt[e] and "Chams off (this one)" or "Chams on (this one)", function()
                    EV.ToggleChamEnt(e)
                end)
                dm:AddOption(EV.espEnt[e] and "Wallhack off (this one)" or "Wallhack on (this one)", function()
                    EV.ToggleEspEnt(e)
                end)
            end

            if r.key then
                dm:AddOption((EV.chamKind[r.key] and "Chams off" or "Chams on") .. " for every one like it", function()
                    EV.ToggleChamKind(r.key)
                end)
                dm:AddOption((EV.espKind[r.key] and "Wallhack off" or "Wallhack on") .. " for every one like it", function()
                    EV.ToggleEspKind(r.key)
                end)
                dm:AddOption("Rename...", function() EV.Rename(r.key, r.text) end)
                if MV.entNames[r.key] then
                    dm:AddOption("Original name", function()
                        MV.entNames[r.key] = nil
                        EV.SaveData()
                        EV.Refresh()
                    end)
                end
            end

            dm:AddSpacer()
            dm:AddOption("Select", function() EV.Select(e) end)
            dm:AddOption("Preview", function() EV.Select(e) EV.Open(e) end)
        end

        dm:Open()
    end

    -- rebuilt twice a second; EntIndex <= 0 leaves out the world and every clientside model
    -- (ours included). Groups are ordered by their nearest member.
    function EV.Rows()
        local now = RealTime()
        if now < rowsNext then return rows end
        rowsNext = now + 0.5

        local out = {}
        local me = LocalPlayer()

        if IsValid(me) then
            local myPos = me:GetPos()
            local maxD = cfg.world.maxDist / 0.01905
            if ev.filter == "player" and not ev.showPlayers then ev.filter = "all" end   -- nothing to show under it
            local f = ev.filter
            local q = EV.Lower(EV.search)

            for _, e in ipairs(ents.GetAll()) do
                if IsValid(e) and e:EntIndex() > 0 then
                    local cat = Category(e, me)

                    if cat and (f == "any" or f == cat or (f == "all" and cat ~= "any")) then
                        local d = myPos:Distance(e:GetPos())
                        if d <= maxD then
                            local key = MV.EntKey(e)
                            local text = RowText(e, cat, key)

                            if q == "" or EV.Matches(e, text, q) then
                                out[#out + 1] = {ent = e, cat = cat, dist = d, key = key, text = text}
                            end
                        end
                    end
                end
            end
        end

        table.sort(out, function(a, b) return a.dist < b.dist end)
        EV.total = #out

        local groups, order = {}, {}
        for _, r in ipairs(out) do
            local gk = r.key or ("#" .. r.ent:EntIndex())
            local g = groups[gk]

            if not g then
                g = {key = gk, cat = r.cat, dist = r.dist, text = r.text, members = {}}
                groups[gk] = g
                order[#order + 1] = g
            end

            g.members[#g.members + 1] = r
        end

        local disp = {}
        for _, g in ipairs(order) do
            if #g.members == 1 then
                disp[#disp + 1] = g.members[1]
            else
                disp[#disp + 1] = {group = true, key = g.key, cat = g.cat, dist = g.dist, text = g.text, count = #g.members}

                if EV.expanded[g.key] then
                    for _, m in ipairs(g.members) do
                        m.child = true
                        disp[#disp + 1] = m
                    end
                end
            end
        end

        rows = disp
        return rows
    end

    -- NWVars ------------------------------------------------------------------------------
    -- Everything an entity has networked, as {kind, name, value, text}:
    --   DT  - NetworkVar from SetupDataTables (GetNetworkVars)
    --   NW  - SetNW* (GetNWVarTable)
    --   NW2 - SetNW2* (GetNW2VarTable; entries there are {type, value})
    -- Newer GMod keeps NW on top of NW2, so a name seen as NW is not listed again as NW2.

    function EV.Fmt(v)
        if isstring(v) then
            local s = string.gsub(string.sub(v, 1, 60), "[\r\n\t]", " ")
            return '"' .. s .. '"' .. (#v > 60 and ("..(" .. #v .. ")") or "")
        end

        if IsEntity(v) then
            if v == game.GetWorld() then return "world" end
            if not IsValid(v) then return "NULL" end
            if v:IsPlayer() then return "player " .. v:Nick() end
            return v:GetClass() .. " #" .. v:EntIndex()
        end

        if isnumber(v) then
            if v == math.floor(v) and math.abs(v) < 2 ^ 31 then return string.format("%d", v) end
            return string.format("%.3f", v)
        end

        if isvector(v) then return string.format("[%.1f %.1f %.1f]", v.x, v.y, v.z) end
        if isangle(v) then return string.format("{%.1f %.1f %.1f}", v.p, v.y, v.r) end

        if istable(v) then
            local j = util.TableToJSON(v) or "{?}"
            return #j > 80 and (string.sub(j, 1, 80) .. "..") or j
        end

        return tostring(v)
    end

    function EV.NWVars(e)
        local out, seen = {}, {}

        local function Add(kind, name, v)
            name = tostring(name)
            if kind == "NW2" and seen[name] then return end
            if kind == "NW" then seen[name] = true end
            out[#out + 1] = {kind = kind, name = name, value = v, text = EV.Fmt(v)}
        end

        if e.GetNetworkVars then
            local ok, t = pcall(e.GetNetworkVars, e)
            if ok and istable(t) then
                for k, v in pairs(t) do Add("DT", k, v) end
            end
        end

        for _, src in ipairs({{"NW", "GetNWVarTable"}, {"NW2", "GetNW2VarTable"}}) do
            local fn = e[src[2]]
            if fn then
                local ok, t = pcall(fn, e)
                if ok and istable(t) then
                    for k, v in pairs(t) do
                        if istable(v) and v.type ~= nil and v.value ~= nil then v = v.value end
                        Add(src[1], k, v)
                    end
                end
            end
        end

        table.sort(out, function(a, b)
            if a.kind ~= b.kind then return a.kind < b.kind end
            return a.name < b.name
        end)

        return out
    end

    -- every NWVar name on the map: {kind, name, count, text = an example}, most common first
    -- (cached for a second, it walks every entity)
    function EV.AllVarNames()
        local now = RealTime()
        if EV.allVars and now < (EV.allVarsNext or 0) then return EV.allVars end
        EV.allVarsNext = now + 1

        local by, list = {}, {}
        for _, e in ipairs(ents.GetAll()) do
            if IsValid(e) and e:EntIndex() > 0 then
                for _, v in ipairs(EV.NWVars(e)) do
                    local k = v.kind .. " " .. v.name
                    local row = by[k]

                    if not row then
                        row = {kind = v.kind, name = v.name, count = 0, text = v.text .. "  (" .. e:GetClass() .. ")"}
                        by[k] = row
                        list[#list + 1] = row
                    end

                    row.count = row.count + 1
                end
            end
        end

        table.sort(list, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)

        EV.allVars = list
        return list
    end

    -- data/nyx/nwvars.txt: a summary of every name, then every entity with its vars
    function EV.DumpVars()
        local lines, names = {}, {}

        for _, e in ipairs(ents.GetAll()) do
            if IsValid(e) and e:EntIndex() > 0 then
                local vars = EV.NWVars(e)

                if #vars > 0 then
                    lines[#lines + 1] = string.format("%s #%d  %s", e:GetClass(), e:EntIndex(),
                        e:IsPlayer() and e:Nick() or (e:GetModel() or ""))

                    for _, v in ipairs(vars) do
                        lines[#lines + 1] = string.format("    [%s] %s = %s", v.kind, v.name, v.text)
                        local k = "[" .. v.kind .. "] " .. v.name
                        names[k] = (names[k] or 0) + 1
                    end
                end
            end
        end

        local keys = table.GetKeys(names)
        table.sort(keys, function(a, b) return names[a] > names[b] end)

        local head = {"-- every NWVar, by how many entities have it"}
        for _, k in ipairs(keys) do head[#head + 1] = string.format("%5d  %s", names[k], k) end

        file.CreateDir("nyx")
        file.Write("nyx/nwvars.txt", table.concat(head, "\n") .. "\n\n" .. table.concat(lines, "\n"))

        EV.status = string.format("%d names dumped to data/nyx/nwvars.txt", #keys)
        return #keys
    end

    -- nyx_nwvars [entindex | all]: no argument = what is under the crosshair
    concommand.Add("nyx_nwvars", function(_, _, args)
        if args[1] == "all" then
            print("[nyx] " .. EV.DumpVars() .. " names -> data/nyx/nwvars.txt")
            return
        end

        local e = tonumber(args[1] or "") and Entity(tonumber(args[1]))
        if not e then
            local me = LocalPlayer()
            e = IsValid(me) and me:GetEyeTrace().Entity
        end
        if not IsValid(e) then print("[nyx] no entity") return end

        print(string.format("[nyx] %s #%d", e:GetClass(), e:EntIndex()))
        for _, v in ipairs(EV.NWVars(e)) do print(string.format("    [%s] %s = %s", v.kind, v.name, v.text)) end
    end)

    -- search ------------------------------------------------------------------------------
    -- Typed by polling the keyboard (the menu has no text entry widget, same as the model
    -- browser). Matches the shown name, the class, the model, "#123" / "123" as the entity
    -- index, and with searchNW on also NWVar names and values.

    EV.search = ""
    EV.searchFocus = nil

    -- string.lower only knows ASCII; Cyrillic capitals are folded here by their UTF-8 bytes:
    -- А-П D0 90-9F -> D0 B0-BF, Р-Я D0 A0-AF -> D1 80-8F, Ё D0 81 -> D1 91
    function EV.Lower(s)
        return (string.gsub(string.lower(s), "\208([\128-\175])", function(c)
            local b = string.byte(c)
            if b == 129 then return "\209\145" end
            if b >= 144 and b <= 159 then return "\208" .. string.char(b + 32) end
            if b >= 160 then return "\209" .. string.char(b - 32) end
        end))
    end

    -- a key-repeat reader: a key already held when it is first asked about does not fire
    function EV.NewKeys()
        local st = {}

        return function(code)
            local s = st[code]
            local down = input.IsKeyDown(code)

            if not s then
                st[code] = {down = down, rep = 0}
                return false
            end

            if not down then s.down = false return false end

            local now = SysTime()
            if not s.down then
                s.down, s.rep = true, now + 0.4
                return true
            end

            if now >= s.rep then
                s.rep = now + 0.04
                return true
            end

            return false
        end
    end

    function EV.Matches(e, text, q)
        local idx = string.match(q, "^#?(%d+)$")
        if idx and e:EntIndex() == tonumber(idx) then return true end

        if string.find(EV.Lower(text), q, 1, true) then return true end
        if string.find(string.lower(e:GetClass()), q, 1, true) then return true end

        local m = e:GetModel()
        if m and string.find(string.lower(m), q, 1, true) then return true end

        if ev.searchNW then
            for _, v in ipairs(EV.NWVars(e)) do
                if string.find(EV.Lower(v.name), q, 1, true) or string.find(EV.Lower(v.text), q, 1, true) then
                    return true
                end
            end
        end

        return false
    end

    function EV.SetSearch(t)
        EV.search = t or ""
        page = 1
        EV.Refresh()
    end

    -- the game must not see what is typed
    AddHook("PlayerBindPress", "entsearch", function()
        if EV.searchFocus and IsValid(menu) then return true end
    end)

    -- from code (the x, a pick from the crosshair, the NWVar window): the field shows it too
    function EV.SetSearchText(t)
        if IsValid(EV.searchEntry) then EV.searchEntry:SetText(t or "") end
        EV.SetSearch(t)
    end

    -- is pnl on screen: it and every parent visible (a hidden tab hides its widgets)
    function EV.Shown(pnl)
        while IsValid(pnl) do
            if not pnl:IsVisible() then return false end
            pnl = pnl:GetParent()
        end
        return true
    end

    -- Typing goes into a DTextEntry of its own, made a popup and laid exactly over the field: a
    -- popup gets the keyboard from the OS on its own (any layout, Russian included, paste,
    -- selection), while the menu keeps its keyboard off so WASD still works. (A text entry inside
    -- the menu never kept the focus: the menu has keyboard input disabled.)
    function EV.EditSearch(p)
        if IsValid(EV.searchEntry) then EV.searchEntry:Remove() end

        local te = vgui.Create("DTextEntry")
        EV.searchEntry, EV.searchFocus = te, te

        local x, y = p:LocalToScreen(0, 0)
        te:SetPos(x + 1, y + 1)
        te:SetSize(p:GetWide() - 20, p:GetTall() - 2)
        te:SetFont("NyxUI")
        te:SetText(EV.search)
        te:SetUpdateOnType(true)
        if te.SetAllowNonAsciiCharacters then te:SetAllowNonAsciiCharacters(true) end
        te:MakePopup()
        te:RequestFocus()
        te:SetCaretPos(utf8.len(EV.search) or #EV.search)
        te.born = RealTime()

        local function Close()
            if EV.searchFocus == te then EV.searchFocus = nil end
            if IsValid(te) then te:Remove() end
        end

        te.OnChange = function(self)
            local t = self:GetValue() or ""
            if #t > 80 then
                t = string.sub(t, 1, 80)
                self:SetText(t)
            end
            EV.SetSearch(t)
        end

        te.OnEnter = function() Close() end

        -- right after opening the focus can bounce once (the click that opened it); take it back
        te.OnLoseFocus = function(self)
            if RealTime() - self.born < 0.25 then
                self:RequestFocus()
                return
            end
            Close()
        end

        te.Paint = function(self, w, h)
            surface.SetDrawColor(C.field)
            surface.DrawRect(0, 0, w, h)
            self:DrawTextEntryText(C.textHi, Color(C.accent.r, C.accent.g, C.accent.b, 120), C.textHi)
        end

        te.Think = function(self)
            if not IsValid(menu) or menu.closing or not EV.Shown(p) then Close() return end

            -- stays on the field when the page scrolls or the window is dragged
            local px, py = p:LocalToScreen(0, 0)
            if px + 1 ~= self:GetX() or py + 1 ~= self:GetY() then self:SetPos(px + 1, py + 1) end

            if input.IsKeyDown(KEY_ESCAPE) then
                gui.HideGameUI()
                Close()
                return
            end

            if RealTime() - self.born > 0.25 and input.IsMouseDown(MOUSE_LEFT) and not self:IsHovered() then
                Close()
            end
        end
    end

    function EV.AddSearch(g)
        local p = WidgetPanel(g, 20)
        p:SetCursor("beam")

        p.Paint = function(self, w, h)
            local editing = IsValid(EV.searchEntry)

            surface.SetDrawColor(C.field)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(editing and C.accent or C.groupBorder)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            if not editing then
                if EV.search == "" then
                    draw.SimpleText(ev.searchNW and "search: name, class, model, #id, nwvars" or "search: name, class, model, #id",
                        "NyxUI", 6, h / 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                else
                    draw.SimpleText(EV.search, "NyxUI", 6, h / 2, C.textHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end

            if EV.search ~= "" then
                draw.SimpleText("x", "NyxUIBold", w - 9, h / 2, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        p.OnMousePressed = function(self, code)
            if code ~= MOUSE_LEFT then return end

            -- the x clears it
            if EV.search ~= "" and self:CursorPos() > self:GetWide() - 18 then
                EV.SetSearchText("")
                return
            end

            EV.EditSearch(self)
        end

        SEARCH.Register("Entity search", p, "list")
    end

    -- picked from the crosshair: the list shows it - filter / search loosened if they hide it,
    -- its group opened, the page turned to it, the row flashing for a moment
    function EV.Reveal(e)
        local me = LocalPlayer()
        if not IsValid(e) or not IsValid(me) then return end

        local cat = Category(e, me)
        if not cat then
            EV.status = "selected - it has no row (player / held weapon / part of the map)"
            return
        end

        if ev.filter ~= "all" and ev.filter ~= "any" and ev.filter ~= cat then ev.filter = "all" end
        if ev.filter == "all" and cat == "any" then ev.filter = "any" end

        local key = MV.EntKey(e)
        if EV.search ~= "" and not EV.Matches(e, RowText(e, cat, key), EV.Lower(EV.search)) then
            EV.SetSearchText("")
        end

        EV.expanded[key or ("#" .. e:EntIndex())] = true
        EV.Refresh()

        for i, r in ipairs(EV.Rows()) do
            if r.ent == e then
                page = math.ceil(i / PER_PAGE)
                EV.flash, EV.flashAt = e, RealTime()
                return
            end
        end

        EV.status = "selected - out of the list's range (Entity ESP max distance)"
    end

    -- NWVar window ----------------------------------------------------------------------------
    -- A panel over the menu, drawn like it. "Selected": every var of the selected entity, live;
    -- click a row = copy "name = value". "All entities": every var name on the map with how
    -- many entities carry it; click = search the list for it (NWVar search switched on).

    function EV.OpenVars(mode)
        if IsValid(EV.varPanel) then EV.varPanel:Remove() end
        if not IsValid(menu) then return end

        local PW, PH, ROW, TOP, BOTTOM = 580, 430, 16, 50, 34
        local b = vgui.Create("Panel", menu)
        EV.varPanel = b
        b:SetSize(PW, PH)
        b:Center()
        b:MoveToFront()

        b.mode = mode or "sel"
        b.scroll, b.rows, b.nextBuild, b.msg = 0, {}, 0, ""

        local Fire = EV.NewKeys()
        local function Visible() return math.floor((PH - TOP - BOTTOM) / ROW) end

        -- clickable areas: {x, y, w, h, label, fn, active()}
        local tabs = {
            {12, 24, 80, 18, "Selected", function() b.mode, b.scroll, b.nextBuild = "sel", 0, 0 end, function() return b.mode == "sel" end},
            {96, 24, 100, 18, "All entities", function() b.mode, b.scroll, b.nextBuild = "all", 0, 0 end, function() return b.mode == "all" end},
        }
        local buttons = {
            {12, PH - 28, 110, 20, "Copy all", function()
                local out = {}
                for _, v in ipairs(b.rows) do
                    out[#out + 1] = b.mode == "sel" and string.format("[%s] %s = %s", v.kind, v.name, v.text)
                        or string.format("%5d  [%s] %s  e.g. %s", v.count, v.kind, v.name, v.text)
                end
                SetClipboardText(table.concat(out, "\n"))
                b.msg = "copied " .. #out .. " lines"
            end},
            {128, PH - 28, 180, 20, "Dump all to nwvars.txt", function()
                b.msg = EV.DumpVars() .. " names -> data/nyx/nwvars.txt"
            end},
            {PW - 82, PH - 28, 70, 20, "Close", function() b:Remove() end},
        }

        local function Inside(a, mx, my)
            return mx >= a[1] and mx <= a[1] + a[3] and my >= a[2] and my <= a[2] + a[4]
        end

        local function Build()
            if b.mode == "sel" then
                local e = EV.sel
                b.title = IsValid(e) and string.format("NWVars - %s #%d", e:GetClass(), e:EntIndex()) or "NWVars - nothing selected"
                b.rows = IsValid(e) and EV.NWVars(e) or {}
            else
                b.rows = EV.AllVarNames()
                b.title = "NWVars - every entity (" .. #b.rows .. " names)"
            end

            b.scroll = math.Clamp(b.scroll, 0, math.max(#b.rows - Visible(), 0))
        end

        b.Think = function(self)
            if not IsValid(menu) or menu.closing then self:Remove() return end
            if Fire(KEY_ESCAPE) then
                gui.HideGameUI()
                self:Remove()
                return
            end

            if RealTime() >= self.nextBuild then
                self.nextBuild = RealTime() + 0.25
                Build()
            end
        end

        b.Paint = function(self, w, h)
            surface.SetDrawColor(C.bg)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(C.accent)
            surface.DrawRect(0, 0, w, 2)
            surface.SetDrawColor(C.groupBorder)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText(self.title or "", "NyxUIBold", 12, 7, C.textHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            local mx, my = self:CursorPos()

            for _, a in ipairs(tabs) do
                local on = a[7]()
                surface.SetDrawColor(on and C.accent or (Inside(a, mx, my) and C.textDim or C.groupBorder))
                surface.DrawOutlinedRect(a[1], a[2], a[3], a[4], 1)
                draw.SimpleText(a[5], "NyxUI", a[1] + a[3] / 2, a[2] + a[4] / 2, on and C.textHi or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            -- list
            local listY, listH = TOP, h - TOP - BOTTOM
            surface.SetDrawColor(C.field)
            surface.DrawRect(12, listY, w - 24, listH)
            surface.SetDrawColor(C.groupBorder)
            surface.DrawOutlinedRect(12, listY, w - 24, listH, 1)

            if #self.rows == 0 then
                draw.SimpleText(self.mode == "sel" and "no networked vars (or nothing selected)" or "no NWVars on the map",
                    "NyxUI", w / 2, listY + listH / 2, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            local hover = (mx > 12 and mx < w - 12 and my > listY and my < listY + listH)
                and math.floor((my - listY - 2) / ROW) + 1 or nil

            for i = 1, Visible() do
                local v = self.rows[self.scroll + i]
                if not v then break end

                local y = listY + 2 + (i - 1) * ROW
                if i == hover then
                    surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 35)
                    surface.DrawRect(13, y, w - 26, ROW)
                end

                local kindCol = v.kind == "DT" and C.accent or (v.kind == "NW" and Color(90, 200, 255) or Color(255, 190, 70))
                draw.SimpleText(v.kind, "NyxUISmall", 18, y + 2, kindCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(string.sub(v.name, 1, 28), "NyxUI", 52, y + 1, C.textHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

                if self.mode == "all" then
                    draw.SimpleText("x" .. v.count, "NyxUISmall", 250, y + 2, C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    draw.SimpleText(string.sub(v.text, 1, 46), "NyxUI", 292, y + 1, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                else
                    draw.SimpleText(string.sub(v.text, 1, 52), "NyxUI", 250, y + 1, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end
            end

            -- scroll position
            local total = #self.rows
            if total > Visible() then
                local bh = math.max(20, listH * Visible() / total)
                local by = listY + (listH - bh) * self.scroll / math.max(total - Visible(), 1)
                surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 120)
                surface.DrawRect(w - 16, by, 3, bh)
            end

            for _, a in ipairs(buttons) do
                surface.SetDrawColor(Inside(a, mx, my) and C.fieldHover or C.field)
                surface.DrawRect(a[1], a[2], a[3], a[4])
                surface.SetDrawColor(Inside(a, mx, my) and C.accent or C.groupBorder)
                surface.DrawOutlinedRect(a[1], a[2], a[3], a[4], 1)
                draw.SimpleText(a[5], "NyxUI", a[1] + a[3] / 2, a[2] + a[4] / 2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            draw.SimpleText(self.msg, "NyxUISmall", 316, h - 18, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        b.OnMousePressed = function(self, code)
            if code ~= MOUSE_LEFT then return end
            local mx, my = self:CursorPos()

            for _, a in ipairs(tabs) do
                if Inside(a, mx, my) then a[6]() return end
            end
            for _, a in ipairs(buttons) do
                if Inside(a, mx, my) then a[6]() return end
            end

            if my <= TOP or my >= PH - BOTTOM then return end
            local v = self.rows[self.scroll + math.floor((my - TOP - 2) / ROW) + 1]
            if not v then return end

            if self.mode == "sel" then
                SetClipboardText(v.name .. " = " .. v.text)
                self.msg = "copied " .. v.name
            else
                ev.searchNW = true
                EV.SetSearchText(v.name)
                self.msg = "list searched for " .. v.name
            end
        end

        b.OnMouseWheeled = function(self, d)
            self.scroll = math.Clamp(self.scroll - d * 3, 0, math.max(#self.rows - Visible(), 0))
            return true
        end

        Build()
    end

    -- picked entities + every entity of a picked kind, at most 256
    function EV.Collect(single, kinds)
        local out = {}
        for e in pairs(single) do
            if IsValid(e) then out[#out + 1] = e end
        end

        if next(kinds) then
            for _, e in ipairs(ents.GetAll()) do
                if #out >= 256 then break end
                if IsValid(e) and e:EntIndex() > 0 and not single[e] then
                    local key = MV.EntKey(e)
                    if key and kinds[key] then out[#out + 1] = e end
                end
            end
        end

        return out
    end

    -- both lists are rebuilt twice a second (and at once after a change, EV.Refresh)
    function EV.ChamTargets()
        local now = RealTime()
        if now < (EV.chamNext or 0) then return EV.chamCache end
        EV.chamNext = now + 0.5

        EV.chamCache = EV.Collect(EV.chamEnt, EV.chamKind)
        return EV.chamCache
    end

    function EV.EspTargets()
        local now = RealTime()
        if now < (EV.espNext or 0) then return EV.espCache end
        EV.espNext = now + 0.5

        EV.espCache = EV.Collect(EV.espEnt, EV.espKind)
        return EV.espCache
    end

    -- health of an entity: gRust's networked HP first, then the engine's; nil when it has none
    function EV.Health(e)
        if e.GetHP and e.GetMaxHP then
            local hp, max = e:GetHP(), e:GetMaxHP()
            if isnumber(hp) and isnumber(max) and max > 0 then return hp, max end
        end

        local max = e:GetMaxHealth()
        if max and max > 1 and e:Health() > 0 then return e:Health(), max end
    end

    -- wallhack: drawn over everything, so walls don't matter; dormant entities are skipped
    -- (their position is the last one the server sent, often far from the truth)
    AddHook("HUDPaint", "entesp", function()
        if IsHidden() then return end

        local list = EV.EspTargets()
        if not list or #list == 0 then return end

        local me = LocalPlayer()
        if not IsValid(me) then return end

        local myPos = me:GetPos()
        local col = Color(ev.espR, ev.espG, ev.espB, 255)
        local sw, sh = ScrW(), ScrH()

        for _, e in ipairs(list) do
            if not IsValid(e) or e:IsDormant() then continue end

            local metres = myPos:Distance(e:GetPos()) * 0.01905
            if metres > ev.espMax then continue end

            -- the line works off-screen too: it aims at the centre while that is in front of you
            if ev.espLine then
                local c = e:WorldSpaceCenter():ToScreen()
                if c.visible then
                    surface.SetDrawColor(0, 0, 0, 160)
                    surface.DrawLine(sw / 2 + 1, sh, c.x + 1, c.y)
                    surface.SetDrawColor(col)
                    surface.DrawLine(sw / 2, sh, c.x, c.y)
                end
            end

            local x, y, w, h = GetScreenBox(e)
            if not x then continue end

            if ev.espBox then
                surface.SetDrawColor(COL_BOXBG)
                surface.DrawOutlinedRect(x - 1, y - 1, w + 2, h + 2, 1)
                surface.DrawOutlinedRect(x + 1, y + 1, w - 2, h - 2, 1)
                surface.SetDrawColor(col)
                surface.DrawOutlinedRect(x, y, w, h, 1)
            end

            if ev.espName then
                local key = MV.EntKey(e)
                local name = (key and MV.entNames[key]) or (e:IsPlayer() and e:Nick()) or WorldLabel(e, WorldCategory(e))
                draw.SimpleTextOutlined(name, "NyxESP", x + w / 2, y - 3, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, COL_BLACK)
            end

            local lineY = y + h + 2

            if ev.espHealth then
                local hp, max = EV.Health(e)
                if hp then
                    local f = math.Clamp(hp / max, 0, 1)
                    local bh = math.max(h, 10)

                    surface.SetDrawColor(COL_BOXBG)
                    surface.DrawRect(x - 6, y - 1, 4, bh + 2)
                    surface.SetDrawColor(math.floor(255 * (1 - f)), math.floor(255 * f), 40, 255)
                    surface.DrawRect(x - 5, y + bh * (1 - f), 2, bh * f)

                    draw.SimpleTextOutlined(math.floor(hp) .. " hp", "NyxESP", x + w / 2, lineY, col,
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, COL_BLACK)
                    lineY = lineY + 11
                end
            end

            if ev.espDist then
                draw.SimpleTextOutlined(math.floor(metres) .. "m", "NyxESP", x + w / 2, lineY, col,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, COL_BLACK)
            end
        end
    end)

    AddHook("PreDrawHalos", "entespglow", function()
        if not ev.espGlow or IsHidden() then return end

        local list = EV.EspTargets()
        if not list or #list == 0 then return end

        local glow = {}
        for _, e in ipairs(list) do
            if IsValid(e) and not e:IsDormant() then glow[#glow + 1] = e end
            if #glow >= 64 then break end
        end

        if #glow > 0 then halo.Add(glow, Color(ev.espR, ev.espG, ev.espB), 2, 2, 1, true, true) end
    end)

    -- Drawn after the world: through walls the depth test is simply off. Without it, the depth
    -- range is pulled in a hair so this pass wins against the engine's own draw of the same
    -- model (equal depth fails the test) while anything really in front still hides it.
    AddHook("PostDrawTranslucentRenderables", "entchams", function(depth, sky)
        if depth or sky or IsHidden() then return end

        local list = EV.ChamTargets()
        if not list or #list == 0 then return end

        local mat = CHAMS_MATS[ev.chamMat] or CHAMS_MATS.flat
        local a = math.min(ev.chamAlpha, 254)

        for _, e in ipairs(list) do
            if IsValid(e) and not e:IsDormant() and not e:GetNoDraw() then
                if ev.chamWalls then
                    DrawCham(e, mat, ev.chamR, ev.chamG, ev.chamB, a, true)
                else
                    render.DepthRange(0, 0.998)
                    DrawCham(e, mat, ev.chamR, ev.chamG, ev.chamB, a, false)
                    render.DepthRange(0, 1)
                end
            end
        end
    end)

    function EV.Select(e)
        EV.sel = e
        EV.status = string.format("selected %s #%d", e:GetClass(), e:EntIndex())
    end

    function EV.Pick()
        local me = LocalPlayer()
        if not IsValid(me) then return end

        local tr = util.TraceLine({
            start = me:EyePos(), endpos = me:EyePos() + realAng:Forward() * 32768,
            filter = me, mask = MASK_SHOT,
        })

        if IsValid(tr.Entity) and not tr.Entity:IsWorld() then
            EV.Select(tr.Entity)
            EV.Reveal(tr.Entity)
        else
            EV.status = "nothing under the crosshair"
        end
    end

    local function AddEntList(g)
        local rowH = 15
        local p = WidgetPanel(g, 16 + 8 + PER_PAGE * rowH)
        p:SetCursor("hand")

        local function rowAt(y)
            local i = math.floor((y - 16 - 4) / rowH) + 1
            if i >= 1 and i <= PER_PAGE then return i end
        end

        p.Paint = function(self, w, h)
            local list = EV.Rows()
            local pages = math.max(1, math.ceil(#list / PER_PAGE))
            if page > pages then page = pages end

            draw.SimpleText(string.format("Entities: %d  (%d / %d)", EV.total, page, pages), "NyxUI", 0, 0, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            surface.SetDrawColor(C.field)
            surface.DrawRect(0, 16, w, h - 16)
            surface.SetDrawColor(C.groupBorder)
            surface.DrawOutlinedRect(0, 16, w, h - 16, 1)

            local hover
            if self:IsHovered() then
                local _, my = self:CursorPos()
                hover = rowAt(my)
            end

            for i = 1, PER_PAGE do
                local r = list[(page - 1) * PER_PAGE + i]
                if not r then break end

                local y = 16 + 4 + (i - 1) * rowH
                local col = r.cat == "player" and PLAYER_COL or WORLD_COLORS[r.cat] or ANY_COL

                if r.group then
                    if i == hover then col = C.textHi end
                elseif not IsValid(r.ent) then
                    col = C.textDim
                elseif r.ent == EV.sel then
                    surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 45)
                    surface.DrawRect(1, y - 1, w - 2, rowH)
                    surface.SetDrawColor(C.accent)
                    surface.DrawRect(1, y - 1, 2, rowH)
                elseif i == hover then
                    col = C.textHi
                end

                -- just picked from the crosshair: the row pulses for a moment
                if not r.group and EV.flash and r.ent == EV.flash then
                    local age = RealTime() - EV.flashAt
                    if age < 1.6 then
                        local a = (1 - age / 1.6) * (0.5 + 0.5 * math.sin(RealTime() * 18))
                        surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 130 * a)
                        surface.DrawRect(1, y - 1, w - 2, rowH)
                    end
                end

                -- group: "+ name  x12" (open: "-"), its members indented under it
                local x, text, maxLen = 8, r.text, 30
                if r.group then
                    text = (EV.expanded[r.key] and "- " or "+ ") .. r.text
                    maxLen = 24
                elseif r.child then
                    x, maxLen = 22, 27
                    surface.SetDrawColor(C.groupBorder)
                    surface.DrawRect(12, y + 6, 6, 1)
                end

                draw.SimpleText(string.sub(text, 1, maxLen), "NyxUI", x, y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

                local right = w - 6
                draw.SimpleText((r.group and "~" or "") .. math.floor(r.dist * 0.01905) .. "m", "NyxUISmall", right, y + 1, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
                right = right - 36

                if r.group then
                    draw.SimpleText("x" .. r.count, "NyxUISmall", right, y + 1, C.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
                    right = right - 30
                end

                -- marks: filled square = chams (its colour), hollow square = wallhack (its colour)
                if EV.HasChams(r) then
                    surface.SetDrawColor(ev.chamR, ev.chamG, ev.chamB, 255)
                    surface.DrawRect(right - 7, y + 3, 7, 7)
                    right = right - 11
                end

                if EV.HasEsp(r) then
                    surface.SetDrawColor(ev.espR, ev.espG, ev.espB, 255)
                    surface.DrawOutlinedRect(right - 7, y + 3, 7, 7, 1)
                end
            end
        end

        -- left: open a group / select an entity (again: preview); right: chams / rename menu
        p.OnMousePressed = function(self, code)
            if code ~= MOUSE_LEFT and code ~= MOUSE_RIGHT then return end

            local _, my = self:CursorPos()
            local i = rowAt(my)
            local r = i and EV.Rows()[(page - 1) * PER_PAGE + i]
            if not r then return end

            if code == MOUSE_RIGHT then
                EV.RowMenu(r)
                return
            end

            if r.group then
                EV.expanded[r.key] = not EV.expanded[r.key] or nil
                EV.Refresh()
                return
            end

            if not IsValid(r.ent) then return end
            if r.ent == EV.sel then EV.Open(r.ent) else EV.Select(r.ent) end
        end

        SEARCH.Register("Entity list", p, "list")
    end

    -- one compact row for the filter: left click = next, right click = previous
    local function AddFilter(g)
        local p = WidgetPanel(g, 20)
        p:SetCursor("hand")

        local function Index()
            for i, f in ipairs(FILTERS) do
                if f[2] == ev.filter then return i end
            end
            return 1
        end

        p.Paint = function(self, w, h)
            surface.SetDrawColor(self:IsHovered() and C.fieldHover or C.field)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(C.groupBorder)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText("Show", "NyxUI", 8, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("< " .. FILTERS[Index()][1] .. " >", "NyxUI", w - 8, h / 2, C.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        p.OnMousePressed = function(self, code)
            local step = (code == MOUSE_RIGHT) and -1 or 1
            ev.filter = FILTERS[(Index() - 1 + step) % #FILTERS + 1][2]
            rowsNext, page = 0, 1
        end

        SEARCH.Register("Entity filter", p, "list")
    end

    -- the copy ------------------------------------------------------------------------------

    local function IsBrush(m)
        return not isstring(m) or m == "" or string.sub(m, 1, 1) == "*"
    end

    local function NewModel(path, parent)
        local c = ClientsideModel(path, RENDERGROUP_OPAQUE)
        if not IsValid(c) then return nil end

        c:SetNoDraw(true)              -- only the viewer draws it
        c.nyxCopy = true

        if parent then
            c:SetParent(parent)
            c:AddEffects(EF_BONEMERGE)
        else
            c:SetPos(vector_origin)
        end

        return c
    end

    -- the copy's skeleton is the bone matrices taken from the real entity (see Capture)
    local function CopyBones(e, n)
        local bones = e.nyxBones
        if not bones then return end

        for i = 0, n - 1 do
            local m = bones[i]
            if m then e:SetBoneMatrix(i, m) end
        end
    end

    -- world bone matrices of src, moved so its origin sits at the copy's (0, 0, 0)
    local function Capture(c, src)
        local n = src:GetBoneCount()
        if not n or n <= 0 then return end

        src:SetupBones()
        local org = src:GetPos()
        local bones = {}

        for i = 0, n - 1 do
            local m = src:GetBoneMatrix(i)
            if m then
                m:SetTranslation(m:GetTranslation() - org)
                bones[i] = m
            end
        end

        c.nyxBones = bones
        c:InvalidateBoneCache()
    end

    -- everything about the look that isn't the pose
    local function Sync(c, src)
        c:SetAngles(src:GetAngles())
        c:SetSkin(src:GetSkin() or 0)

        for _, bg in ipairs(src:GetBodyGroups() or {}) do
            c:SetBodygroup(bg.id, src:GetBodygroup(bg.id))
        end

        c:SetMaterial(src:GetMaterial() or "")
        local mats = src:GetMaterials()
        for i = 0, (mats and #mats or 0) - 1 do c:SetSubMaterial(i, src:GetSubMaterial(i)) end

        c:SetColor(src:GetColor())
        c:SetRenderMode(src:GetRenderMode())
        c:SetModelScale(src:GetModelScale() or 1, 0)

        -- the pose for models without usable bone matrices (on the client GetPoseParameter is 0..1)
        c:SetSequence(src:GetSequence())
        c:SetCycle(src:GetCycle())

        for i = 0, src:GetNumPoseParameters() - 1 do
            local name = src:GetPoseParameterName(i)
            local lo, hi = src:GetPoseParameterRange(i)
            if name and lo and hi then
                c:SetPoseParameter(name, math.Remap(src:GetPoseParameter(name), 0, 1, lo, hi))
            end
        end
    end

    local function ClearCopy(v)
        if IsValid(v.copy) then v.copy:Remove() end
        if IsValid(v.wcopy) then v.wcopy:Remove() end
        v.copy, v.wcopy, v.copyModel, v.wModel = nil, nil, nil, nil
    end

    -- keeps the copy (and its weapon) in step with the source; called every frame
    local function Refresh(v)
        local src = v.src

        if not IsValid(src) then
            v.gone = true          -- the copy stays as it was last
            return
        end
        v.gone = false

        local m = src:GetModel()
        v.brush = IsBrush(m)

        if v.brush then
            ClearCopy(v)
        elseif v.copyModel ~= m or not IsValid(v.copy) then
            ClearCopy(v)
            v.copyModel = m
            v.copy = NewModel(m)

            if v.copy then
                v.copy:AddCallback("BuildBonePositions", CopyBones)
                Sync(v.copy, src)
                Capture(v.copy, src)
            end
        elseif ev.live then
            if RealTime() >= (v.nextSync or 0) then
                v.nextSync = RealTime() + 0.1
                Sync(v.copy, src)
            end
            Capture(v.copy, src)
        end

        -- no model file to copy (or it would not load): the real entity is drawn instead
        if not v.copy then v.brush = true end

        -- the weapon in its hands, bonemerged onto the copy
        if v.copy and (ev.live or not v.wInit) then
            v.wInit = true

            local wep = src.GetActiveWeapon and src:GetActiveWeapon()
            local wm = IsValid(wep) and wep:GetModel() or nil
            if wm == "" then wm = nil end

            if wm ~= v.wModel then
                if IsValid(v.wcopy) then v.wcopy:Remove() end
                v.wcopy = wm and NewModel(wm, v.copy) or nil
                v.wModel = wm
                if IsValid(v.wcopy) then v.wcopy:SetSkin(wep:GetSkin() or 0) end
            end
        end

        -- where the camera looks: the bounds' centre, in the copy's space (or the world's)
        local origin = v.brush and src:GetPos() or vector_origin
        local mins, maxs = src:OBBMins(), src:OBBMaxs()

        v.center = LocalToWorld(src:OBBCenter(), angle_zero, origin, src:GetAngles())
        v.radius = math.max((maxs - mins):Length() * 0.5, 6)
        v.floorZ = origin.z + mins.z
    end

    -- the viewer ------------------------------------------------------------------------------

    local function Draw3D(v, x, y, w, h)
        if not v.center then return end

        local drawReal = v.brush and IsValid(v.src)
        if not drawReal and not IsValid(v.copy) then return end

        local sx, sy = v:LocalToScreen(x, y)
        local fov = 40
        local ang = Angle(v.pitch, v.yaw, 0)
        local dist = v.radius / math.sin(math.rad(fov / 2)) * v.zoom
        local pos = v.center - ang:Forward() * dist

        cam.Start3D(pos, ang, fov, sx, sy, w, h, 1, dist + v.radius * 4 + 1000)
            render.ClearDepth()

            if ev.lit then
                render.SuppressEngineLighting(true)
                render.SetLightingOrigin(v.center)
                render.ResetModelLighting(0.3, 0.3, 0.32)
                render.SetModelLighting(BOX_TOP, 1, 1, 1)
                render.SetModelLighting(BOX_FRONT, 0.7, 0.7, 0.75)
                render.SetModelLighting(BOX_RIGHT, 0.45, 0.45, 0.5)
            else
                -- the map's light at the spot where the real one stands
                render.SetLightingOrigin(IsValid(v.src) and v.src:GetPos() or v.center)
            end

            render.SetColorModulation(1, 1, 1)
            render.SetBlend(1)

            if drawReal then
                v.src:DrawModel()
            else
                v.copy:DrawModel()
                if IsValid(v.wcopy) then v.wcopy:DrawModel() end
            end

            render.SuppressEngineLighting(false)

            -- floor grid under it
            local c, r, gz = v.center, v.radius * 1.4, v.floorZ
            for i = -4, 4 do
                local o = r * i / 4
                render.DrawLine(Vector(c.x + o, c.y - r, gz), Vector(c.x + o, c.y + r, gz), GRID_COL, true)
                render.DrawLine(Vector(c.x - r, c.y + o, gz), Vector(c.x + r, c.y + o, gz), GRID_COL, true)
            end
        cam.End3D()
    end

    local function ResetView(v)
        v.yaw = (IsValid(v.src) and v.src:GetAngles().y or 0) + 150   -- the front, a bit from the side
        v.pitch, v.zoom = 12, 1
    end

    function EV.Open(ent)
        if not IsValid(ent) then
            EV.status = "nothing selected"
            return
        end

        EV.Select(ent)
        if IsValid(viewer) then viewer:Remove() end

        local W, H = 440, 500
        local v = vgui.Create("Panel")
        viewer = v
        v:SetSize(W, H)

        -- next to the menu (left of it when there is no room on the right)
        local x, y = (ScrW() - W) / 2, (ScrH() - H) / 2
        if IsValid(menu) then
            local mx, my = menu:GetPos()
            x, y = mx + menu:GetWide() + 8, my
            if x + W > ScrW() then x = math.max(0, mx - W - 8) end
        end
        v:SetPos(x, math.Clamp(y, 0, math.max(ScrH() - H, 0)))

        v:MakePopup()
        v:SetKeyboardInputEnabled(false)

        v.src = ent
        v.class, v.idx = ent:GetClass(), ent:EntIndex()
        ResetView(v)

        v.OnRemove = function(self)
            ClearCopy(self)
            if viewer == self then viewer = nil end
        end

        v.Think = function(self)
            -- goes with the menu (and with an unload, which removes the menu)
            if not IsValid(menu) then self:Remove() return end

            if self.moving then
                self:SetPos(gui.MouseX() - self.moving[1], gui.MouseY() - self.moving[2])
            end

            if self.turning then
                local mx, my = gui.MouseX(), gui.MouseY()
                self.yaw = self.yaw - (mx - self.turning[1]) * 0.6
                self.pitch = math.Clamp(self.pitch + (my - self.turning[2]) * 0.4, -85, 85)
                self.turning = {mx, my}
            elseif ev.spin then
                self.yaw = self.yaw + FrameTime() * 35
            end

            Refresh(self)
        end

        -- title bar: drag / close; the view: drag = turn, wheel = zoom, right click = reset
        v.OnMousePressed = function(self, code)
            local cx, cy = self:CursorPos()

            if code == MOUSE_RIGHT then ResetView(self) return end
            if code ~= MOUSE_LEFT then return end

            if cy < TITLE_H then
                if cx > self:GetWide() - 22 then self:Remove() return end

                local px, py = self:GetPos()
                self.moving = {gui.MouseX() - px, gui.MouseY() - py}
            else
                self.turning = {gui.MouseX(), gui.MouseY()}
            end

            self:MouseCapture(true)
        end

        v.OnMouseReleased = function(self)
            self.moving, self.turning = nil, nil
            self:MouseCapture(false)
        end

        v.OnMouseWheeled = function(self, delta)
            self.zoom = math.Clamp(self.zoom * (delta > 0 and 0.88 or 1.14), 0.25, 5)
            return true
        end

        v.Paint = function(self, w, h)
            if IsHidden() then return end

            surface.SetDrawColor(C.bg)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            for gx = 1, w - 3, 2 do
                local r, g, b = GradientAt((gx - 1) / (w - 3))
                surface.SetDrawColor(r, g, b, 255)
                surface.DrawRect(gx, 1, 2, 2)
            end

            draw.SimpleText(string.format("3D viewer  -  %s #%d", self.class, self.idx), "NyxUIBold", 8, TITLE_H / 2 + 1, C.textHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            local cx = self:CursorPos()
            local hotX = self:IsHovered() and cx > w - 22 and select(2, self:CursorPos()) < TITLE_H
            draw.SimpleText("x", "NyxUIBold", w - 11, TITLE_H / 2 + 1, hotX and C.accent or C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            -- the view
            local vx, vy, vw, vh = 8, TITLE_H + 4, w - 16, h - TITLE_H - INFO_H - 12
            surface.SetDrawColor(6, 6, 6, 255)
            surface.DrawRect(vx, vy, vw, vh)

            Draw3D(self, vx, vy, vw, vh)

            surface.SetDrawColor(C.groupBorder)
            surface.DrawOutlinedRect(vx, vy, vw, vh, 1)

            -- info under it
            local src = self.src
            local iy = vy + vh + 6
            local mode = self.gone and "source gone, copy frozen" or (self.brush and "brush entity: drawing the real one"
                or (ev.live and "live copy" or "frozen copy"))

            local lines = {{mode, C.accent}}

            if IsValid(src) then
                local me = LocalPlayer()
                local d = IsValid(me) and math.floor(me:GetPos():Distance(src:GetPos()) * 0.01905) or 0
                local seq = src:GetSequence() or 0

                lines[#lines + 1] = {"model  " .. (src:GetModel() or "?"), C.text}
                lines[#lines + 1] = {string.format("%dm   hp %d   skin %d   bones %d   scale %.2f", d, src:Health(),
                    src:GetSkin() or 0, src:GetBoneCount() or 0, src:GetModelScale() or 1), C.text}
                lines[#lines + 1] = {string.format("seq %s   cycle %.2f%s", src:GetSequenceName(seq) or seq, src:GetCycle() or 0,
                    self.wModel and ("   weapon " .. (string.match(self.wModel, "([^/]+)%.mdl$") or "")) or ""), C.text}
            end

            lines[#lines + 1] = {"drag: turn   wheel: zoom   right click: reset", C.textDim}

            for i, l in ipairs(lines) do
                draw.SimpleText(string.sub(l[1], 1, 64), "NyxUI", 10, iy + (i - 1) * 14, l[2], TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
        end
    end

    function EV.CopyModel()
        local e = EV.sel
        if not IsValid(e) then EV.status = "nothing selected" return end

        SetClipboardText(e:GetModel() or e:GetClass())
        EV.status = "copied " .. (e:GetModel() or e:GetClass())
    end

    -- halo on the selected entity
    AddHook("PreDrawHalos", "entsel", function()
        if not ev.highlight or IsHidden() or not IsValid(menu) then return end

        local e = EV.sel
        if IsValid(e) and not e:IsDormant() then halo.Add({e}, C.accent, 2, 2, 2, true, true) end
    end)

    -- the tab ------------------------------------------------------------------------------

    function EV.BuildPage(left, right)
        local g = NewGroup(left, "Entities")
        EV.AddSearch(g)
        AddEntList(g)
        AddFilter(g)
        AddCheck(g, "Search in NWVars too", ev, "searchNW")
        AddCheck(g, "Show players", ev, "showPlayers")
        AddButton(g, "Next page", function()
            local pages = math.max(1, math.ceil(#EV.Rows() / PER_PAGE))
            page = page % pages + 1
        end)
        AddButton(g, "Pick from crosshair", EV.Pick)
        AddButton(g, "Collapse all groups", function()
            EV.expanded = {}
            EV.Refresh()
        end)
        AddLabel(g, "Same kind = one row, click opens it")
        AddLabel(g, "Right click: chams / wallhack / rename")
        EndGroup(g)

        g = NewGroup(left, "Entity chams")
        AddList(g, "Material", ev, "chamMat", CHAMS_CHOICES)
        AddColor(g, "Color", ev, "chamR", "chamG", "chamB")
        AddSlider(g, "Alpha", ev, "chamAlpha", 20, 255, 0)
        AddCheck(g, "Through walls", ev, "chamWalls")
        AddButton(g, "Chams on / off: selected", function()
            if IsValid(EV.sel) and not EV.sel:IsPlayer() then EV.ToggleChamEnt(EV.sel) end
        end)
        AddButton(g, "Chams on / off: selected's kind", function()
            local key = IsValid(EV.sel) and MV.EntKey(EV.sel)
            if key then EV.ToggleChamKind(key) end
        end)
        AddButton(g, "Rename selected's kind", function()
            local key = IsValid(EV.sel) and MV.EntKey(EV.sel)
            if key then EV.Rename(key, EV.sel:GetClass()) end
        end)
        AddButton(g, "Clear all entity chams", function()
            EV.chamEnt = setmetatable({}, {__mode = "k"})
            EV.chamKind = {}
            EV.SaveData()
            EV.Refresh()
        end)
        AddLabel(g, function()
            return string.format("%d with chams  |  %d renamed", #(EV.ChamTargets() or {}), table.Count(MV.entNames))
        end)
        EndGroup(g)

        g = NewGroup(right, "Entity wallhack")
        AddCheck(g, "Box", ev, "espBox")
        AddCheck(g, "Name", ev, "espName")
        AddCheck(g, "Health", ev, "espHealth")
        AddCheck(g, "Distance", ev, "espDist")
        AddCheck(g, "Snapline", ev, "espLine")
        AddCheck(g, "Glow through walls", ev, "espGlow")
        AddColor(g, "Color", ev, "espR", "espG", "espB")
        AddSlider(g, "Max distance", ev, "espMax", 10, 5000, 0, "m")
        AddButton(g, "Wallhack on / off: selected", function()
            if IsValid(EV.sel) and not EV.sel:IsPlayer() then EV.ToggleEspEnt(EV.sel) end
        end)
        AddButton(g, "Wallhack on / off: selected's kind", function()
            local key = IsValid(EV.sel) and MV.EntKey(EV.sel)
            if key then EV.ToggleEspKind(key) end
        end)
        AddButton(g, "Clear all entity wallhack", function()
            EV.espEnt = setmetatable({}, {__mode = "k"})
            EV.espKind = {}
            EV.SaveData()
            EV.Refresh()
        end)
        AddLabel(g, function()
            return string.format("%d with wallhack", #(EV.EspTargets() or {}))
        end)
        EndGroup(g)

        local w = cfg.world
        g = NewGroup(right, "Entity ESP")
        AddCheck(g, "Entity ESP", w, "enabled", function(p)
            AddCheck(p, "NPCs", w, "npc")
            AddCheck(p, "Loose weapons", w, "weapon")
            AddCheck(p, "Props", w, "prop")
            AddCheck(p, "Vehicles", w, "vehicle")
            AddCheck(p, "Items / ammo", w, "item")
            AddCheck(p, "Doors", w, "door")
            AddCheck(p, "Scripted entities", w, "other")
            AddCheck(p, "Box", w, "box")
            AddCheck(p, "Name", w, "name")
            AddCheck(p, "Distance", w, "distance")
            AddSlider(p, "Max distance", w, "maxDist", 50, 5000, 0, "m")
        end)
        AddCheck(g, "Entity glow", w, "glow")
        AddCheck(g, "Highlight selected", ev, "highlight")
        EndGroup(g)

        g = NewGroup(right, "3D viewer")
        AddLabel(g, function()
            local e = EV.sel
            if not IsValid(e) then return "nothing selected" end
            return string.format("%s #%d", e:GetClass(), e:EntIndex())
        end, C.accent)
        AddButton(g, "Preview", function() EV.Open(EV.sel) end)
        AddCheck(g, "Live copy (follows the real one)", ev, "live")
        AddCheck(g, "Auto rotate", ev, "spin")
        AddCheck(g, "Studio light", ev, "lit")
        AddButton(g, "Copy model path", EV.CopyModel)
        AddLabel(g, function() return EV.status end)
        EndGroup(g)

        g = NewGroup(right, "NWVars")
        AddLabel(g, function()
            local e = EV.sel
            if not IsValid(e) then return "nothing selected" end
            return string.format("%s #%d: %d vars", e:GetClass(), e:EntIndex(), #EV.NWVars(e))
        end, C.accent)
        AddButton(g, "NWVars of selected", function() EV.OpenVars("sel") end)
        AddButton(g, "NWVars of every entity", function() EV.OpenVars("all") end)
        AddButton(g, "Dump all to data/nyx/nwvars.txt", EV.DumpVars)
        EndGroup(g)
    end
end

local TABS = {"Rage", "Anti-aim", "Legit", "Visuals", "Movement", "Misc", "Config", "Players", "Entities"}

-- extrapolation settings popup, the same for the aimbot and the rage bot (cfg.extrap is shared)
function BT.X.Menu(p)
    local e = cfg.extrap
    AddCheck(p, "Lag compensation breakers", e, "lcBreak")
    AddLabel(p, "Hitscan: only targets moving >64u per")
    AddLabel(p, "update are led (the rest are rewound)")
    AddList(p, "Projectile lead", e, "projectile", {{"Off", "off"}, {"Known weapons", "auto"}, {"Every weapon", "always"}})
    AddSlider(p, "Projectile speed", e, "projSpeed", 500, 10000, 0, " u/s")
    AddSlider(p, "Projectile gravity", e, "projGravity", 0, 1, 2, "x")
    AddCheck(p, "Air strafe curve", e, "strafe")
    AddCheck(p, "Bhop landings", e, "bhop")
    AddSlider(p, "Max lead", e, "maxTicks", 4, 64, 0, " ticks")
    AddCheck(p, "Draw path", e, "draw")
    AddColor(p, "Path color", e, "r", "g", "b")
    AddLabel(p, BT.X.Status, C.accent)
    AddLabel(p, BT.ModStatus, C.accent)
end

-- Model browser: every scanned model, filtered by what is typed, with a turning preview of the
-- one under the mouse. Click = wear it. key = "selfModel" | "othersModel".
-- Typing is read by polling, like the function search (the menu has no text entry widget).
do
    local CHARS = {}
    for i = 0, 9 do CHARS[KEY_0 + i] = tostring(i) end
    for i = 0, 25 do CHARS[KEY_A + i] = string.char(97 + i) end
    CHARS[KEY_SPACE], CHARS[KEY_MINUS], CHARS[KEY_SLASH], CHARS[KEY_PERIOD] = " ", "_", "/", "."

    local KEYS = {}
    for code in pairs(CHARS) do KEYS[#KEYS + 1] = code end
    KEYS[#KEYS + 1] = KEY_BACKSPACE
    KEYS[#KEYS + 1] = KEY_ESCAPE

    local browser = nil

    -- while it is open the game must not see the keys being typed
    AddHook("PlayerBindPress", "modelbrowser", function()
        if IsValid(browser) then return true end
    end)

    function MV.mdl.Browse(key)
        local M = MV.mdl
        if IsValid(browser) then browser:Remove() end
        if not IsValid(menu) then return end

        if not M.scan.done then M.StartScan() end

        local PW, PH, ROW, LIST_W, TOP = 620, 430, 18, 380, 58
        local b = vgui.Create("Panel", menu)
        browser = b
        b:SetSize(PW, PH)
        b:Center()
        b:MoveToFront()                     -- keys are polled; the game binds are blocked above

        b.text, b.scroll, b.hover, b.all = "", 0, nil, false
        b.keys = {}
        for _, code in ipairs(KEYS) do b.keys[code] = {down = input.IsKeyDown(code), rep = 0} end

        local function Fire(code)
            local s = b.keys[code]
            if not input.IsKeyDown(code) then s.down = false return false end

            local now = SysTime()
            if not s.down then
                s.down, s.rep = true, now + 0.4
                return true
            end
            if now >= s.rep then
                s.rep = now + 0.04
                return true
            end
            return false
        end

        local function Rows() return math.floor((PH - TOP - 8) / ROW) end
        local function List() return M.Find(b.text, b.all) end

        -- preview of the hovered (or the worn) model
        local prev = vgui.Create("DModelPanel", b)
        prev:SetPos(LIST_W + 16, TOP)
        prev:SetSize(PW - LIST_W - 24, PH - TOP - 40)
        prev:SetFOV(32)
        prev:SetCamPos(Vector(90, 0, 40))
        prev:SetLookAt(Vector(0, 0, 36))
        prev.shown = nil
        function prev:LayoutEntity(ent)
            ent:SetAngles(Angle(0, RealTime() * 40 % 360, 0))
        end
        function prev:Think()
            local want = b.hover or cfg.model[key]
            if want and want ~= self.shown then
                self.shown = want
                self:SetModel(want)
            end
        end

        b.Think = function(self)
            if not IsValid(menu) or menu.closing then self:Remove() return end

            local changed = false
            for code, ch in pairs(CHARS) do
                if Fire(code) and #self.text < 40 then
                    self.text = self.text .. ch
                    changed = true
                end
            end
            if Fire(KEY_BACKSPACE) and #self.text > 0 then
                self.text = string.sub(self.text, 1, -2)
                changed = true
            end
            if Fire(KEY_ESCAPE) then
                gui.HideGameUI()
                self:Remove()
                return
            end
            if changed then self.scroll = 0 end
        end

        local function RowAt(self)
            local x, y = self:CursorPos()
            if x < 8 or x > LIST_W or y < TOP then return end

            local i = self.scroll + math.floor((y - TOP) / ROW) + 1
            if i <= #List() then return i end
        end

        b.OnCursorMoved = function(self)
            local i = RowAt(self)
            self.hover = i and List()[i] or nil
        end

        b.OnCursorExited = function(self) self.hover = nil end

        b.OnMouseWheeled = function(self, d)
            local maxScroll = math.max(#List() - Rows(), 0)
            self.scroll = math.Clamp(self.scroll - d * 3, 0, maxScroll)
            self:OnCursorMoved()
        end

        b.OnMousePressed = function(self, code)
            local x, y = self:CursorPos()

            -- close (top right) and the "all models" switch
            if y < 22 and x > PW - 26 then self:Remove() return end
            if y >= 26 and y < 46 and x > PW - 150 then
                self.all, self.scroll = not self.all, 0
                return
            end

            local i = RowAt(self)
            if code ~= MOUSE_LEFT or not i then return end

            local path = List()[i]
            cfg.model[key] = path
            cfg.model[key == "selfModel" and "self" or "others"] = true
            M.Say(true, (key == "selfModel" and "self" or "others") .. " model: " .. path)
        end

        b.Paint = function(self, w, h)
            surface.SetDrawColor(C.tabBg)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            surface.SetDrawColor(C.accent)
            surface.DrawRect(1, 1, w - 2, 1)

            local title = key == "selfModel" and "Model browser - local" or "Model browser - others"
            draw.SimpleText(title, "NyxUIBold", 10, 6, C.textHi)
            draw.SimpleText("x", "NyxUIBold", w - 14, 5, C.textDim)

            -- search field
            surface.SetDrawColor(C.field)
            surface.DrawRect(8, 26, LIST_W - 8, 20)
            surface.SetDrawColor(C.accent)
            surface.DrawOutlinedRect(8, 26, LIST_W - 8, 20, 1)
            local shown = self.text ~= "" and self.text or "type to filter: rust, combine, csgo..."
            draw.SimpleText(shown, "NyxUI", 14, 36, self.text ~= "" and C.textHi or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            draw.SimpleText(self.all and "[x] all models" or "[ ] all models", "NyxUI", w - 140, 36,
                self.all and C.accent or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            local list = List()
            local S = M.scan
            local status = S.done and (#list .. " found / " .. #S.all .. " models")
                or ("scanning... " .. S.dirs .. " folders, " .. #S.all .. " models")
            draw.SimpleText(status, "NyxUISmall", LIST_W + 16, h - 30, C.textDim)
            draw.SimpleText("wheel = scroll, click = wear, Esc = close", "NyxUISmall", LIST_W + 16, h - 16, C.textDim)

            local rows = Rows()
            for r = 1, rows do
                local i = self.scroll + r
                local p = list[i]
                if not p then break end

                local y = TOP + (r - 1) * ROW
                local worn = p == cfg.model[key]

                if p == self.hover or worn then
                    surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, worn and 60 or 30)
                    surface.DrawRect(8, y, LIST_W - 8, ROW)
                end

                -- file name bright, its folder dim
                local name = string.GetFileFromFilename(p)
                local dir = string.sub(string.GetPathFromFilename(p), 8)     -- without "models/"
                draw.SimpleText(name, "NyxUI", 12, y + ROW / 2, worn and C.accent or C.textHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(dir, "NyxUISmall", LIST_W - 4, y + ROW / 2, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end

            -- scrollbar
            if #list > rows then
                local trackH = rows * ROW
                local barH = math.max(trackH * rows / #list, 12)
                local barY = TOP + (trackH - barH) * self.scroll / math.max(#list - rows, 1)
                surface.SetDrawColor(C.accent)
                surface.DrawRect(LIST_W + 2, barY, 3, barH)
            end
        end

        WrapPaint(b)
        WrapPaint(prev)
    end
end

local function BuildMenu()
    local MIN_W, MIN_H = 600, 440
    local W = math.Clamp(math.floor(cfg.menu.w), MIN_W, math.max(MIN_W, ScrW() - 20))
    local H = math.Clamp(math.floor(cfg.menu.h), MIN_H, math.max(MIN_H, ScrH() - 20))

    -- the tab column shares the height out, so all eight tabs fit at any size
    local TAB_W, TAB_Y = 86, 28
    local TAB_H = math.Clamp(math.floor((H - TAB_Y - 8) / #TABS), 40, 58)

    local frame = vgui.Create("Panel")
    menu = frame
    frame:SetSize(W, H)
    -- back where it was when it was closed last (kept on screen if the resolution changed)
    if cfg.menu.x >= 0 and cfg.menu.y >= 0 then
        frame:SetPos(math.Clamp(cfg.menu.x, 0, math.max(ScrW() - W, 0)), math.Clamp(cfg.menu.y, 0, math.max(ScrH() - H, 0)))
    else
        frame:Center()
    end
    frame:MakePopup()
    frame:SetKeyboardInputEnabled(false)   -- keep WASD working while the menu is open

    -- Opening and closing: the whole window fades while sliding a few pixels. baseX / baseY is
    -- where the window really sits (the drag handle moves those), the slide is added on top.
    frame.baseX, frame.baseY = frame:GetPos()
    frame.fade = 0
    frame.closing = false
    frame:SetAlpha(0)

    frame.Paint = function(self, w, h)
        surface.SetDrawColor(C.bg)
        surface.DrawRect(0, 0, w, h)

        BG.Draw(w, h)           -- the animated picture, under everything else

        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- the gradient line flows along the top edge (it bounces back at the ends)
        local flow = cfg.menu.anim and CurTime() * 0.07 * cfg.menu.speed or 0
        for x = 1, w - 3, 2 do
            local t = ((x - 1) / (w - 3) + flow) % 2
            if t > 1 then t = 2 - t end

            local r, g, b = GradientAt(t)
            surface.SetDrawColor(r, g, b, 255)
            surface.DrawRect(x, 1, 2, 2)
        end

        surface.SetDrawColor(C.groupBorder)
        surface.DrawRect(TAB_W - 1, 3, 1, h - 4)
    end

    frame.Think = function(self)
        PollBinding()

        -- opened with Ctrl+F while the menu was closed: the search comes up on the first frame
        if self.wantSearch and SEARCH.toggle then
            self.wantSearch = nil
            SEARCH.toggle()
        end

        self.fade = ANIM.Step(self.fade, self.closing and 0 or 1, 11)

        self:SetAlpha(255 * self.fade)
        self:SetPos(self.baseX, self.baseY + (1 - self.fade) * 20)

        if self.closing and self.fade <= 0.01 then self:Remove() end
    end

    frame.OnKeyCodePressed = function(self, key)
        if binding then FinishBinding(key) end
    end

    frame.OnRemove = function()
        -- remembered for the next open (baseX / baseY: without the open / close slide)
        cfg.menu.x, cfg.menu.y = math.floor(frame.baseX), math.floor(frame.baseY)

        binding = nil
        popup = nil
        colorPopup = nil
        if SEARCH.close then SEARCH.close() end
        SEARCH.toggle, SEARCH.close = nil, nil
        if menu == frame then menu = nil end
    end

    -- drag handle (top strip)
    local handle = vgui.Create("Panel", frame)
    handle:SetPos(0, 0)
    handle:SetSize(W, 24)
    handle:SetCursor("sizeall")
    handle.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end
        local mx, my = frame:CursorPos()
        self.off = {mx, my}
        self:MouseCapture(true)
    end
    handle.OnMouseReleased = function(self)
        self.off = nil
        self:MouseCapture(false)
    end
    handle.Think = function(self)
        if not self.off then return end

        -- the frame's own Think puts the window at baseX / baseY (plus the open / close slide)
        frame.baseX = gui.MouseX() - self.off[1]
        frame.baseY = gui.MouseY() - self.off[2]
    end

    -- pages
    local pages = {}
    local PAGE_X, PAGE_Y = TAB_W + 12, 36
    local PAGE_W, PAGE_H = W - PAGE_X - 12, H - PAGE_Y - 12
    local COL_W = math.floor((PAGE_W - 16) / 2)

    for i = 1, #TABS do
        local page = vgui.Create("Panel", frame)
        page:SetPos(PAGE_X, PAGE_Y)
        page:SetSize(PAGE_W, PAGE_H)
        page:SetVisible(i == lastTab)
        pages[i] = page

        -- Scrolling: the mouse wheel anywhere over the page moves its groups up / down (widgets
        -- that use the wheel themselves, like the 3D viewer, keep it). Groups keep their built
        -- position in g.baseY and are drawn at baseY - scroll; the page clips what is outside.
        -- The scroll eases toward scrollTo, and a thin bar on the right shows where you are.
        page.scroll, page.scrollTo, page.applied = 0, 0, 0

        function page:ContentH()
            local h = 0
            for _, g in ipairs(self:GetChildren()) do
                if g.baseY then h = math.max(h, g.baseY + g:GetTall()) end
            end
            return h
        end

        function page:MaxScroll()
            return math.max(0, self:ContentH() - self:GetTall() + 8)
        end

        function page:ScrollBy(d)
            self.scrollTo = math.Clamp(self.scrollTo + d, 0, self:MaxScroll())
        end

        -- brings panel p (anywhere inside this page) into view, a third from the top
        function page:ScrollToPanel(p)
            if not IsValid(p) then return end
            local _, py = self:ScreenToLocal(p:LocalToScreen(0, 0))
            if py >= 6 and py + p:GetTall() <= self:GetTall() - 6 then return end
            self.scrollTo = math.Clamp(self.scrollTo + py - self:GetTall() / 3, 0, self:MaxScroll())
            self.scroll = self.scrollTo          -- jump, so the search outline lands on it at once
        end

        page.OnMouseWheeled = function(self, d)
            if self:MaxScroll() <= 0 then return end
            ClosePopup()                          -- a popup is placed against the old position
            self:ScrollBy(-d * 60)
            return true
        end

        function page:ScrollThink()
            -- the window may have been resized taller: no scrolling past the end
            self.scrollTo = math.Clamp(self.scrollTo, 0, self:MaxScroll())

            local d = self.scrollTo - self.scroll
            if math.abs(d) < 0.5 then
                self.scroll = self.scrollTo
            else
                self.scroll = self.scroll + d * math.min(1, FrameTime() * 16)
            end

            local s = math.floor(self.scroll + 0.5)
            if s == self.applied then return end
            self.applied = s

            for _, g in ipairs(self:GetChildren()) do
                if g.baseY then g:SetPos(g:GetX(), g.baseY - s) end
            end
        end

        page.PaintOver = function(self, w, h)
            local max = self:MaxScroll()
            if max <= 0 then return end

            local content = max + h
            local bh = math.max(24, h * h / content)
            local by = (h - bh) * self.scroll / max

            surface.SetDrawColor(C.groupBorder)
            surface.DrawRect(w - 3, 0, 3, h)
            surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 200)
            surface.DrawRect(w - 3, by, 3, bh)
        end

        -- a page slides in from the right and fades up when it is shown (page.t is reset on a
        -- tab click); Think only runs while the page is visible
        page.t = 1
        page.Think = function(self)
            self:ScrollThink()

            if not cfg.menu.anim then
                self.t = 1
                self:SetAlpha(255)
                self:SetPos(PAGE_X, PAGE_Y)
                return
            end

            self.t = math.min(1, self.t + FrameTime() * 4.5 * cfg.menu.speed)

            local e = 1 - (1 - self.t) ^ 3          -- ease out
            self:SetAlpha(255 * e)
            self:SetPos(PAGE_X + (1 - e) * 18, PAGE_Y)
        end
    end

    SEARCH.index = {}

    local function Cols(page)
        -- every page starts here, so this is also where the search index learns which tab is
        -- being built
        for n, pg in ipairs(pages) do
            if pg == page then SEARCH.tab = n end
        end

        -- kind tells the live resize how the column follows the window (see Layout)
        return {page = page, x = 0, y = 0, w = COL_W, kind = "left"},
            {page = page, x = COL_W + 16, y = 0, w = COL_W, kind = "right"}
    end

    -- rage
    do
        local left, right = Cols(pages[1])
        local r = cfg.rage

        local g = NewGroup(left, "Rage aimbot")
        AddCheck(g, "Enabled", r, "enabled", function(p)
            AddSlider(p, "Field of view", r, "fov", 1, 180, 0, "\194\176")
            AddSlider(p, "Max distance", r, "maxDist", 10, 1000, 0, "m")
        end)
        AddCheck(g, "Draw FOV", r, "drawFov", function(p)
            AddColor(p, "Color", r, "fovR", "fovG", "fovB")
        end)
        AddCheck(g, "Draw target point", r, "drawTarget")
        AddCheck(g, "Auto fire", r, "autoFire")
        AddCheck(g, "Hold fire (full auto)", r, "holdFire")
        AddCheck(g, "Auto stop", r, "autoStop")
        AddCheck(g, "Visible only", r, "visOnly")
        AddCheck(g, "Autowall", r, "autowall", function(p)
            AddSlider(p, "Penetration power", r, "wallPower", 5, 150, 0, "u")
            AddSlider(p, "Max walls", r, "wallCount", 1, 4, 0)
            AddLabel(p, "Shoot through:")
            AddCheck(p, "Glass", r.wall, "glass")
            AddCheck(p, "Wood", r.wall, "wood")
            AddCheck(p, "Plastic / electronics", r.wall, "plastic")
            AddCheck(p, "Thin (vents, grates, foliage)", r.wall, "thin")
            AddCheck(p, "Tile", r.wall, "tile")
            AddCheck(p, "Dirt / sand / grass", r.wall, "dirt")
            AddCheck(p, "Other / unknown", r.wall, "other")
            AddCheck(p, "Concrete", r.wall, "concrete")
            AddCheck(p, "Metal", r.wall, "metal")
            AddLabel(p, "Cost = thickness x hardness")
            AddLabel(p, "Needs Visible only on")
            AddCheck(p, "SWB / M9K: weapon's own rules", r, "weaponWall")
            AddLabel(p, "(their real penetration code)")
        end)
        AddCheck(g, "Skip while reloading", r, "skipReload")
        AddCheck(g, "Auto reload", r, "autoReload")
        AddCheck(g, "Recoil compensation", r, "recoilOn", function(p)
            AddSlider(p, "Strength", r, "recoil", 0, 2, 1, "x")
        end)
        AddCheck(g, "Velocity prediction", r, "predictOn", function(p)
            AddSlider(p, "Lead", r, "predict", 1, 10, 0, " ticks")
        end)
        AddCheck(g, "Extrapolation", r, "extrapOn", BT.X.Menu)
        EndGroup(g)

        local bt = cfg.backtrack
        g = NewGroup(left, "Backtrack")
        AddCheck(g, "Backtrack (both aimbots)", bt, "enabled", function(p)
            AddSlider(p, "Max age", bt, "ms", 20, 200, 0, "ms")
            AddCheck(p, "Draw records", bt, "draw")
            AddLabel(p, "Shoots where he was, if he is")
            AddLabel(p, "hidden now but was visible")
            AddLabel(p, "inside the window. Server")
            AddLabel(p, "takes ~200 ms at most.")
            AddLabel(p, "With gmcl_nyx: records are server")
            AddLabel(p, "ticks (simulation time) and the tick")
            AddLabel(p, "is written by the module.")
            AddLabel(p, BT.ModStatus, C.accent)
        end)
        EndGroup(g)

        g = NewGroup(left, "Filters")
        AddCheck(g, "Team check", r, "teamCheck")
        AddCheck(g, "Ignore steam friends", r, "ignoreFriends")
        AddCheck(g, "Target only (Players tab)", r, "targetOnly")
        AddCheck(g, "Ignore bots", r, "ignoreBots")
        AddCheck(g, "Ignore admins", r, "ignoreAdmins")
        AddCheck(g, "Ignore frozen", r, "ignoreFrozen")
        AddCheck(g, "Ignore noclip", r, "ignoreNoclip")
        AddCheck(g, "Ignore spawn protection", r, "ignoreGod")
        AddCheck(g, "Ignore in vehicles", r, "ignoreVehicle")
        AddCheck(g, "Ignore invisible (nodraw)", r, "ignoreNodraw")
        AddSlider(g, "Max targets (0 = all)", r, "maxTargets", 0, 10, 0)
        EndGroup(g)

        g = NewGroup(right, "Hitboxes")
        AddCheck(g, "Head", r, "head")
        AddCheck(g, "Chest", r, "chest")
        AddCheck(g, "Pelvis", r, "pelvis")
        AddCheck(g, "Arms", r, "arms")
        AddCheck(g, "Legs", r, "legs")
        AddCheck(g, "Real hitboxes (not bones)", r, "realHitboxes")
        AddCheck(g, "Multipoint", r, "multipoint", function(p)
            AddSlider(p, "Point scale", r, "mpScale", 0.1, 1, 2, "x")
            AddCheck(p, "Head", r, "mpHead")
            AddCheck(p, "Chest / pelvis", r, "mpBody")
            AddCheck(p, "Arms / legs", r, "mpLimbs")
            AddLabel(p, "8 corners per hitbox box, pulled")
            AddLabel(p, "toward its centre by the scale")
            AddLabel(p, "Many traces: use Max targets")
        end)
        AddSlider(g, "Body-aim below HP (0 = off)", r, "bodyBelow", 0, 100, 0)
        AddSlider(g, "Minimum damage (0 = off)", r, "minDamage", 0, 150, 0)
        AddCheck(g, "Min damage override", r, "minDmgOverride", function(p)
            AddSlider(p, "Override value", r, "minDmgOverrideValue", 0, 150, 0)
            AddLabel(p, "Right-click the checkbox: bind it")
            AddLabel(p, "Damage is estimated (weapon dmg,")
            AddLabel(p, "head x2, less through walls)")
        end)
        AddCheck(g, "Force body aim (BAIM)", r, "forceBaim")
        EndGroup(g)

        g = NewGroup(right, "Target selection")
        AddList(g, "Priority", r, "priority", {{"Closest (distance)", "distance"}, {"Lowest health", "health"}, {"Closest to crosshair", "fov"}})
        EndGroup(g)

        -- applies to whoever either aimbot is currently on, not to the whole server
        local rs = cfg.resolver
        g = NewGroup(right, "Resolver")
        AddCheck(g, "Resolver (aim target only)", rs, "enabled", function(p)
            AddList(p, "Per shot", rs, "mode", {
                {"+ step degrees", "step"}, {"List -180..180 by 60", "list"},
            })
            AddSlider(p, "Step", rs, "step", 5, 90, 0, "\194\176")
            AddSlider(p, "Reset after", rs, "reset", 1, 20, 0, "s")
            AddCheck(p, "Pitch resolver", rs, "pitch")
            AddCheck(p, "Memory resolver", rs, "memory")
            AddSlider(p, "Memory: misses allowed", rs, "memoryMisses", 1, 8, 0)
            AddSlider(p, "Memory: keep for", rs, "memoryTime", 10, 900, 0, "s")
            AddLabel(p, RS.Status)
            AddButton(p, "Clear memory", RS.Clear)
        end)
        EndGroup(g)

        local ns = cfg.nospread
        g = NewGroup(right, "No spread")
        AddCheck(g, "No spread (HL2 weapons)", ns, "enabled", function(p)
            AddSlider(p, "Seed offset", ns, "seedOffset", -3, 3, 0)
            AddSlider(p, "Cone scale", ns, "scale", 0.25, 2, 2, "x")
            AddLabel(p, NS.StatusLine)
            AddLabel(p, "pistol / smg1 / ar2; .357 is exact")
            AddLabel(p, "shotgun pellets can't be aligned")
            AddCheck(p, "SWB / CW 2.0 (experimental)", ns, "bases")
            AddLabel(p, "seeded by command number - only")
            AddLabel(p, "right if the base rolls it so")
        end)
        EndGroup(g)

        local nr = cfg.norecoil
        g = NewGroup(right, "No recoil")
        AddCheck(g, "No recoil (your own shots)", nr, "enabled", function(p)
            AddSlider(p, "Strength", nr, "scale", 0, 2, 1, "x")
            AddLabel(p, "Silent: the screen still kicks,")
            AddLabel(p, "the bullets don't")
        end)
        AddCheck(g, "Skip M9K / HL2 pistol / bb / unclen8", nr, "exceptions")
        AddLabel(g, "they don't kick through the punch")
        AddLabel(g, "(also used by both aimbots)")
        EndGroup(g)
    end

    -- anti-aim
    do
        local left, right = Cols(pages[2])
        local aa = cfg.aa

        -- widgets below edit whichever profile is selected (or "stand" when shared)
        local function Profile()
            return aa.sameForAll and aa.states.stand or aa.states[aa.sel]
        end
        local cur = setmetatable({}, {
            __index = function(_, k) return Profile()[k] end,
            __newindex = function(_, k, v) Profile()[k] = v end,
        })

        local g = NewGroup(left, "Anti-aim")
        AddCheck(g, "Enabled", aa, "enabled", function(p)
            AddCheck(p, "Real view while shooting", aa, "realOnShoot")
            AddCheck(p, "On shot (real view on the shot tick only)", aa, "onShot")
            AddCheck(p, "Hide shots (low cmdrate while firing)", aa, "hideShots")
            AddSlider(p, "Hide shots cmdrate", aa, "hideRate", 10, 66, 0)
            AddCheck(p, "Real view while using (E)", aa, "offOnUse")
            AddCheck(p, "Off with physgun / toolgun", aa, "offWithTools")
            AddSlider(p, "Roll", cur, "roll", -50, 50, 0, "\194\176")
            AddSlider(p, "Yaw noise", cur, "noise", 0, 90, 0, "\194\176")
            AddCheck(p, "Desync: real on choked ticks (module)", aa, "desync")
            AddCheck(p, "LBY breaker", aa, "lby")
            AddSlider(p, "LBY delta", aa, "lbyDelta", -180, 180, 0, "\194\176")
            AddSlider(p, "LBY interval", aa, "lbyInterval", 0.1, 3, 2, "s")
        end)
        AddCheck(g, "Indicator", aa, "indicator")
        AddCheck(g, "Same profile for all states", aa, "sameForAll")
        AddList(g, "Editing profile", aa, "sel", {{"Standing", "stand"}, {"Moving", "move"}, {"In air", "air"}})
        EndGroup(g)

        g = NewGroup(left, "Pitch")
        AddList(g, "Mode", cur, "pitchMode", {
            {"None (real)", "none"}, {"Down 89", "down"}, {"Up -89", "up"}, {"Zero", "zero"},
            {"Jitter up/down", "jitter"}, {"Random", "random"}, {"Custom", "custom"},
        })
        AddSlider(g, "Custom pitch", cur, "pitchValue", -89, 89, 0, "\194\176")
        EndGroup(g)

        g = NewGroup(right, "Yaw")
        AddList(g, "Base", cur, "yawBase", {{"View", "view"}, {"Static (world)", "static"}, {"At nearest enemy", "target"}})
        AddSlider(g, "Offset", cur, "yawOffset", -180, 180, 0, "\194\176")
        AddButton(g, "Modifier settings...", function()
            OpenSettingsPopup("Yaw modifier", function(p)
                AddSlider(p, "Range", cur, "modRange", 0, 180, 0, "\194\176")
                AddSlider(p, "Speed (spin / sway)", cur, "modSpeed", -1000, 1000, 0, " deg/s")
                AddSlider(p, "Interval", cur, "modInterval", 1, 32, 0, " ticks")
                AddSlider(p, "Switch offset", cur, "switchOffset", -180, 180, 0, "\194\176")
            end)
        end)
        EndGroup(g)

        g = NewGroup(right, "Modifier")
        AddList(g, "Mode", cur, "yawMod", {
            {"None", "none"}, {"Jitter", "jitter"}, {"Random", "random"},
            {"Spin", "spin"}, {"Sway", "sway"}, {"Switch", "switch"},
        })
        EndGroup(g)

        g = NewGroup(right, "Manual yaw")
        AddCheck(g, "Left  (right-click: bind)", aa, "manualLeft")
        AddCheck(g, "Right (right-click: bind)", aa, "manualRight")
        AddCheck(g, "Back  (right-click: bind)", aa, "manualBack")
        EndGroup(g)

        g = NewGroup(right, "Fake lag")
        AddCheck(g, "Fake lag", aa, "fakelag", function(p)
            AddList(p, "Mode", aa, "flMode", {
                {"Static", "static"}, {"Adaptive (by speed)", "adaptive"}, {"Jitter", "jitter"},
                {"In air only", "air"}, {"Moving only", "moving"},
            })
            AddSlider(p, "Choke (max)", aa, "flChoke", 1, 14, 0, " ticks")
            AddCheck(p, "Off while shooting", aa, "flOffShooting")
            AddLabel(p, "With gmcl_nyx: real packet choke.")
            AddLabel(p, "Without: cl_cmdrate (the server clamps")
            AddLabel(p, "it to sv_mincmdrate, needs FPS above")
            AddLabel(p, "the packet rate).")
            AddLabel(p, BT.NetStatus, C.accent)
        end)
        AddLabel(g, MV.FakeLagStatus, C.accent)
        EndGroup(g)
    end

    -- legit aim
    do
        local left, right = Cols(pages[3])
        local aim = cfg.aim

        local g = NewGroup(left, "Aimbot")
        AddCheck(g, "Enabled", aim, "enabled", function(p)
            AddSlider(p, "Field of view", aim, "fov", 1, 90, 0, "\194\176")
            AddSlider(p, "Max distance", aim, "maxDist", 10, 1000, 0, "m")
        end)
        AddKeybind(g, "Aim key", aim, "key")
        AddCheck(g, "Silent aim", aim, "silent", function(p)
            AddCheck(p, "Only when shooting", aim, "fireOnly")
            AddSlider(p, "Smoothing (silent off)", aim, "smooth", 1, 30, 0)
        end)
        AddCheck(g, "Auto fire", aim, "autoFire")
        AddCheck(g, "Sticky target", aim, "sticky")
        EndGroup(g)

        g = NewGroup(left, "Filters")
        AddCheck(g, "Visibility check", aim, "visCheck")
        AddCheck(g, "Team check", aim, "teamCheck")
        AddCheck(g, "Ignore steam friends", aim, "ignoreFriends")
        AddCheck(g, "Target only (Players tab)", aim, "targetOnly")
        EndGroup(g)

        g = NewGroup(right, "Hitbox")
        AddList(g, "Target hitbox", aim, "hitbox", {{"Head", "head"}, {"Chest", "chest"}, {"Pelvis", "pelvis"}})
        AddCheck(g, "Fallback if blocked", aim, "fallback")
        EndGroup(g)

        g = NewGroup(right, "Target selection")
        AddList(g, "Priority", aim, "priority", {{"Closest to crosshair", "fov"}, {"Distance", "distance"}, {"Lowest health", "health"}})
        EndGroup(g)

        g = NewGroup(right, "Accuracy")
        AddCheck(g, "Recoil compensation", aim, "recoilOn", function(p)
            AddSlider(p, "Strength", aim, "recoil", 0, 2, 1, "x")
        end)
        AddCheck(g, "Velocity prediction", aim, "predictOn", function(p)
            AddSlider(p, "Lead", aim, "predict", 1, 10, 0, " ticks")
        end)
        AddCheck(g, "Extrapolation", aim, "extrapOn", BT.X.Menu)
        AddCheck(g, "Humanize", aim, "humanizeOn", function(p)
            AddSlider(p, "Wobble", aim, "humanize", 0, 6, 1, "u")
        end)
        EndGroup(g)

        g = NewGroup(right, "Indicators")
        AddCheck(g, "Draw FOV", aim, "drawFov")
        AddCheck(g, "Draw target", aim, "drawTarget")
        EndGroup(g)
    end

    -- visuals
    do
        local left, right = Cols(pages[4])
        local esp = cfg.esp

        local g = NewGroup(left, "Players")
        AddCheck(g, "ESP", esp, "enabled", function(p)
            AddColor(p, "Box / text color", esp, "r", "g", "b")
            AddCheck(p, "Team colors", esp, "teamColor")
            AddCheck(p, "Hide teammates", esp, "teamCheck")
            AddCheck(p, "Dormant players", esp, "dormant")
            AddSlider(p, "Dormant time", esp, "dormantTime", 1, 30, 0, "s")
            AddSlider(p, "Max distance", esp, "maxDist", 100, 10000, 0, "m")
        end)
        AddCheck(g, "Box", esp, "box")
        AddCheck(g, "Name", esp, "name")
        AddCheck(g, "Health bar", esp, "health", function(p)
            AddCheck(p, "HP number", esp, "hpText")
            AddList(p, "Number position", esp, "hpPos", {
                {"Beside the bar (follows it)", "follow"}, {"Above the bar", "top"}, {"Under the box", "below"},
            })
            AddCheck(p, "As percent", esp, "hpPercent")
            AddCheck(p, "Hide at full HP", esp, "hpHideFull")
            AddList(p, "Number color", esp, "hpColor", {
                {"Like the bar (green - red)", "bar"}, {"ESP text color", "text"}, {"Custom", "custom"},
            })
            AddColor(p, "Custom color", esp, "hpR", "hpG", "hpB")
        end)
        AddCheck(g, "Weapon", esp, "weapon")
        AddCheck(g, "Distance", esp, "distance")
        EndGroup(g)

        local ch = cfg.chams
        local matChoices = CHAMS_CHOICES      -- every look that loaded, see the chams block

        -- Every target (players / local player / hands) has its own tab in the popup. The tab
        -- buttons rebuild the popup, and each tab edits its own fields directly, so a colour is
        -- always the colour of the target named at the top (no hidden "currently editing" mode).
        local TARGETS = {{"Players", "players"}, {"Local", "self"}, {"Hands", "hands"}}

        -- a row of buttons, one per choice; onChange runs after the value changed
        local function AddSegments(p, tbl, key, choices, onChange)
            local pnl = WidgetPanel(p, 20)
            pnl:SetCursor("hand")

            pnl.Paint = function(self, w, h)
                local cw = w / #choices

                for i, choice in ipairs(choices) do
                    local x = (i - 1) * cw
                    local on = tbl[key] == choice[2]

                    surface.SetDrawColor(on and C.accent or C.field)
                    surface.DrawRect(x + 1, 0, cw - 2, h)
                    surface.SetDrawColor(C.boxBorder)
                    surface.DrawOutlinedRect(x + 1, 0, cw - 2, h, 1)
                    draw.SimpleText(choice[1], "NyxUI", x + cw / 2, h / 2, on and C.bg or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

            pnl.OnMousePressed = function(self, code)
                if code ~= MOUSE_LEFT then return end

                local x = self:CursorPos()
                local choice = choices[math.floor(x / (self:GetWide() / #choices)) + 1]

                if choice and tbl[key] ~= choice[2] then
                    tbl[key] = choice[2]
                    onChange()
                end
            end
        end

        local BuildChams

        local function OpenChams()
            OpenSettingsPopup("Chams", BuildChams)
        end

        BuildChams = function(p)
            if ch.edit ~= "players" and ch.edit ~= "self" and ch.edit ~= "hands" then
                ch.edit = "players"
            end

            AddSegments(p, ch, "edit", TARGETS, OpenChams)

            if ch.edit == "players" then
                AddLabel(p, "Other players", C.accent)
                AddCheck(p, "Draw on players", ch, "players")
                AddList(p, "Material", ch, "material", matChoices)
                AddSlider(p, "Alpha", ch, "alpha", 20, 254, 0)
                AddColor(p, "Visible color", ch, "visR", "visG", "visB")
                AddCheck(p, "Through walls", ch, "throughWalls")
                AddColor(p, "Behind walls color", ch, "hidR", "hidG", "hidB")
                AddCheck(p, "Hide teammates", ch, "teamCheck")
            elseif ch.edit == "self" then
                AddLabel(p, "Local player (3rd person)", C.accent)
                AddCheck(p, "Draw on local player", ch, "self")
                AddList(p, "Material", ch, "selfMaterial", matChoices)
                AddSlider(p, "Alpha", ch, "selfAlpha", 20, 254, 0)
                AddColor(p, "Color", ch, "selfR", "selfG", "selfB")
            else
                AddLabel(p, "First person hands / weapon", C.accent)
                AddCheck(p, "Hands", ch, "hands")
                AddCheck(p, "Weapon / viewmodel", ch, "weapon")
                AddList(p, "Material", ch, "handMaterial", matChoices)
                AddSlider(p, "Alpha", ch, "handAlpha", 20, 254, 0)
                AddColor(p, "Color", ch, "handR", "handG", "handB")
            end
        end

        g = NewGroup(left, "Chams")
        AddCheck(g, "Chams", ch, "enabled", BuildChams)
        EndGroup(g)

        local tr = cfg.tracers
        g = NewGroup(left, "Tracers")
        AddCheck(g, "Bullet tracers", tr, "enabled", function(p)
            AddSlider(p, "Lifetime", tr, "life", 0.2, 5, 1, "s")
            AddSlider(p, "Width", tr, "width", 1, 12, 0)
            AddColor(p, "Color", tr, "r", "g", "b")
        end)
        EndGroup(g)

        local ht = cfg.hits
        g = NewGroup(left, "Hits")
        AddCheck(g, "Hitmarker (crosshair)", ht, "marker")
        AddCheck(g, "Hitmarker (where it hit)", ht, "world")
        AddCheck(g, "Damage numbers", ht, "numbers")
        AddCheck(g, "Hit logs (screen)", ht, "logs", function(p)
            AddCheck(p, "Log misses (aimbot shots)", ht, "logMiss")
            AddSlider(p, "Line time", ht, "logTime", 1, 15, 0, "s")
        end)
        AddCheck(g, "Hit logs (console)", ht, "console")
        AddList(g, "Hit sound", ht, "sound", {
            {"Off", "off"}, {"Click", "buttons/button15.wav"}, {"Blip", "buttons/blip1.wav"},
            {"Bell", "buttons/bell1.wav"}, {"Pop", "garrysmod/balloon_pop_cute.wav"},
        })
        AddColor(g, "Marker color", ht, "r", "g", "b")
        AddLabel(g, "Headshot = orange, kill = red")
        EndGroup(g)

        local xi = cfg.xind
        g = NewGroup(left, "Crosshair indicators")
        AddCheck(g, "Indicators", xi, "enabled")
        AddButton(g, "Change title", function()
            Derma_StringRequest("Indicator title", "Text of the first line (and the hit log tag)", xi.name, function(t)
                t = string.Trim(t or "")
                if t ~= "" then xi.name = string.sub(t, 1, 24) end
            end)
        end)
        AddLabel(g, function() return "Title now: " .. xi.name end, C.accent)
        AddColor(g, "Title color", xi, "r", "g", "b")
        AddCheck(g, "Movement state (AIR ...)", xi, "state")
        AddCheck(g, "Minimum damage", xi, "minDamage")
        AddCheck(g, "Active features (BAIM ...)", xi, "features")
        AddSlider(g, "Distance below crosshair", xi, "offset", 8, 120, 0, "px")
        EndGroup(g)

        local kf = cfg.killfx
        g = NewGroup(left, "Kill effects")
        AddCheck(g, "Kill effects", kf, "enabled", function(p)
            AddCheck(p, "Shockwave rings", kf, "ring")
            AddCheck(p, "Spark burst", kf, "burst")
            AddCheck(p, "Lightning strike", kf, "bolt")
            AddCheck(p, "Rising orbs", kf, "souls")
            AddCheck(p, "Kill text / streak", kf, "text")
            AddCheck(p, "Screen flash", kf, "flash")
            AddCheck(p, "Energy explosion", kf, "sparks")
            AddCheck(p, "Light pillar", kf, "pillar")
            AddCheck(p, "Vortex", kf, "vortex")
            AddCheck(p, "Fireworks", kf, "fireworks")
            AddCheck(p, "Confetti", kf, "confetti")
            AddCheck(p, "Wire dome", kf, "dome")
            AddCheck(p, "Ghost rising", kf, "ghost")
            AddCheck(p, "Hitmarker", kf, "hitmarker")
            AddCheck(p, "Streak banner", kf, "banner")
            AddCheck(p, "Screen shake", kf, "shake")
            AddCheck(p, "Scorch mark", kf, "scorch")
            AddList(p, "Ragdoll", kf, "ragdoll", {
                {"Off", "off"}, {"Gold", "gold"}, {"Ice", "ice"}, {"Color", "color"}, {"Dissolve", "dissolve"},
                {"Neon wireframe", "neon"}, {"Chrome", "chrome"}, {"Energy", "energy"}, {"Void", "void"},
                {"Pulse", "pulse"}, {"Self-illum", "selfillum"},
            })
            AddList(p, "Sound", kf, "sound", {
                {"Off", "off"}, {"Bell", "buttons/bell1.wav"}, {"Pop", "garrysmod/balloon_pop_cute.wav"},
                {"Zap", "ambient/energy/zap1.wav"}, {"Disintegrate", "weapons/physcannon/energy_disintegrate4.wav"},
                {"Explosion", "ambient/explosions/explode_4.wav"}, {"Blip", "buttons/blip1.wav"},
                {"Combine ball", "weapons/physcannon/energy_sing_explosion2.wav"},
                {"Citadel", "ambient/levels/citadel/weapon_disintegrate2.wav"},
            })
            AddCheck(p, "Rainbow", kf, "rainbow")
            AddColor(p, "Color", kf, "r", "g", "b")
            AddSlider(p, "Duration", kf, "life", 0.5, 5, 1, "s")
            AddSlider(p, "Sparks", kf, "count", 8, 120, 0)
            AddSlider(p, "Size", kf, "scale", 0.5, 2.5, 1, "x")
            AddButton(p, "Preview", KFX.Preview)
        end)
        AddButton(g, "Preview kill effect", KFX.Preview)
        EndGroup(g)

        local gl = cfg.glow
        g = NewGroup(left, "Glow")
        AddCheck(g, "Player glow", gl, "enabled", function(p)
            AddCheck(p, "Through walls", gl, "throughWalls")
            AddCheck(p, "Hide teammates", gl, "teamCheck")
            AddSlider(p, "Width", gl, "width", 1, 8, 0)
            AddColor(p, "Color", gl, "r", "g", "b")
        end)
        AddCheck(g, "Local player glow", gl, "self", function(p)
            AddColor(p, "Color", gl, "selfR", "selfG", "selfB")
        end)
        AddLabel(g, "Local glow: third person / free camera")
        EndGroup(g)

        g = NewGroup(left, "Custom model")
        AddCheck(g, "Local model", cfg.model, "self")
        AddLabel(g, function() return "  " .. MV.mdl.Label(cfg.model.selfModel) end, C.accent)
        AddButton(g, "< Previous (local)", function() MV.mdl.Step("selfModel", -1) end)
        AddButton(g, "Next > (local)", function() MV.mdl.Step("selfModel", 1) end)
        AddButton(g, "Browse all models (local)...", function() MV.mdl.Browse("selfModel") end)
        AddCheck(g, "Other players", cfg.model, "others", function(p)
            AddCheck(p, "Skip teammates", cfg.model, "teamCheck")
        end)
        AddLabel(g, function() return "  " .. MV.mdl.Label(cfg.model.othersModel) end, C.accent)
        AddButton(g, "< Previous (others)", function() MV.mdl.Step("othersModel", -1) end)
        AddButton(g, "Next > (others)", function() MV.mdl.Step("othersModel", 1) end)
        AddButton(g, "Browse all models (others)...", function() MV.mdl.Browse("othersModel") end)
        AddButton(g, "Models folder (copy path)", MV.mdl.CopyFolder)
        AddButton(g, "Rescan models", function()
            MV.mdl.scan.done = false
            MV.mdl.StartScan()
        end)
        AddLabel(g, function()
            local S = MV.mdl.scan
            if S.queue then return "scanning... " .. #S.all .. " models" end
            return #MV.mdl.List() .. " registered, " .. #S.all .. " scanned"
        end)
        AddLabel(g, "Any path: nyx_model self <path>")
        AddLabel(g, "Only you see it")
        EndGroup(g)

        g = NewGroup(right, "Camera")
        AddCheck(g, "Third person", cfg.view, "thirdperson", function(p)
            AddSlider(p, "Distance", cfg.view, "distance", 30, 300, 0)
            AddSlider(p, "Shoulder", cfg.view, "shoulder", -60, 60, 0)
            AddSlider(p, "Height", cfg.view, "height", -30, 60, 0)
        end)
        AddCheck(g, "FOV override", cfg.view, "fovOn", function(p)
            AddSlider(p, "Field of view", cfg.view, "fov", 60, 120, 0, "\194\176")
        end)
        AddCheck(g, "Free camera", cfg.free, "enabled", function(p)
            AddSlider(p, "Speed", cfg.free, "speed", 100, 3000, 0, " u/s")
            AddSlider(p, "Sprint boost", cfg.free, "boost", 1, 10, 1, "x")
        end)
        AddCheck(g, "Aspect ratio", cfg.view, "aspectOn", function(p)
            AddSlider(p, "Ratio (w / h)", cfg.view, "aspect", 0.5, 3, 2)
        end)
        EndGroup(g)

        local vmc = cfg.vm
        g = NewGroup(right, "Viewmodel")
        AddCheck(g, "Viewmodel offset", vmc, "offsetOn", function(p)
            AddSlider(p, "X (forward)", vmc, "x", -30, 30, 1)
            AddSlider(p, "Y (right)", vmc, "y", -30, 30, 1)
            AddSlider(p, "Z (up)", vmc, "z", -30, 30, 1)
        end)
        AddCheck(g, "Viewmodel FOV", vmc, "fovOn", function(p)
            AddSlider(p, "Field of view", vmc, "fov", 30, 130, 0, "\194\176")
        end)
        EndGroup(g)

        local w = cfg.world
        local rm = cfg.removals
        g = NewGroup(right, "Removals")
        AddCheck(g, "Removals", rm, "enabled", function(p)
            AddLabel(p, "View")
            AddCheck(p, "No screen shake", rm, "shake")
            AddCheck(p, "No view punch (recoil kick)", rm, "punch")
            AddCheck(p, "No viewmodel bob / sway", rm, "bob")
            AddCheck(p, "Hide viewmodel", rm, "viewmodel")

            AddLabel(p, "World")
            AddCheck(p, "No fog", rm, "fog")
            AddCheck(p, "No motion blur", rm, "motionBlur")
            AddCheck(p, "No decals", rm, "decals")
            AddCheck(p, "No shell ejection", rm, "shells")
            AddCheck(p, "Hide ragdolls", rm, "ragdolls")

            AddLabel(p, "HUD")
            AddCheck(p, "Damage indicator", rm, "hudDamage")
            AddCheck(p, "Crosshair", rm, "hudCrosshair")
            AddCheck(p, "Health / suit", rm, "hudHealth")
            AddCheck(p, "Ammo", rm, "hudAmmo")
            AddCheck(p, "Weapon selection", rm, "hudWeapons")
            AddCheck(p, "Pickup history", rm, "hudPickup")
            AddCheck(p, "Kill feed", rm, "hudKillfeed")
        end)
        EndGroup(g)

        -- entity ESP / glow live on the Entities tab
        g = NewGroup(right, "World")
        AddCheck(g, "Fullbright", w, "fullbright")
        AddCheck(g, "Night mode", w, "night", function(p)
            AddSlider(p, "Darkness", w, "nightAmount", 0.1, 0.95, 2)
            AddCheck(p, "Dim the screen too", w, "nightScreen")
            AddLabel(p, WL.Status)
            AddButton(p, "Re-apply", WL.Force)
        end)
        AddCheck(g, "Custom time", w, "timeOn", function(p)
            AddSlider(p, "Hour", w, "timeHour", 0, 24, 1, "h")
            AddLabel(p, function()
                local h = w.timeHour % 24
                return string.format("Time: %02d:%02d", math.floor(h), math.floor((h % 1) * 60))
            end, C.accent)
            AddCheck(p, "Day cycle (runs by itself)", w, "timeCycle")
            AddSlider(p, "Cycle speed", w, "timeSpeed", 1, 120, 0, " h/min")
            AddCheck(p, "Tint the screen too", w, "timeScreen")
            AddLabel(p, "Map light, sky, dusk, stars, sun")
            AddLabel(p, "Overrides night mode while on")
            AddLabel(p, WL.Status)
            AddButton(p, "Re-apply", WL.Force)
        end)
        AddCheck(g, "Custom fog", w, "fogOn", function(p)
            AddColor(p, "Fog color", w, "fogR", "fogG", "fogB")
            AddSlider(p, "Start", w, "fogStart", 0, 8000, 0, "u")
            AddSlider(p, "End", w, "fogEnd", 100, 20000, 0, "u")
            AddSlider(p, "Density", w, "fogDensity", 0.05, 1, 2)
        end)
        AddCheck(g, "Remove fog", w, "noFog")
        AddCheck(g, "Solid color sky", w, "skySolid", function(p)
            AddColor(p, "Sky color", w, "solidR", "solidG", "solidB")
        end)
        AddButton(g, "Skybox changer...", function()
            OpenSettingsPopup("Skybox", function(p)
                AddList(p, "Skybox", w, "skyPreset", SKY_PRESETS)
                AddCheck(p, "Tint", w, "skyTint")
                AddColor(p, "Tint color", w, "skyR", "skyG", "skyB")
                AddLabel(p, WL.SkyStatus)
                AddButton(p, "Re-apply", WL.Force)
            end)
        end)
        AddButton(g, "Sky picture (my photos)...", function()
            OpenSettingsPopup("Sky picture", function(p)
                AddCheck(p, "Use my picture", w, "skyPic")
                BG.AddPicker(p, w, "skyPicFile", SKYPIC.Select)
                AddButton(p, "Next page", BG.NextPage)
                AddButton(p, "Refresh list", BG.Refresh)
                AddSlider(p, "Rotation", w, "skyPicRot", -30, 30, 1, " deg/s")
                AddSlider(p, "Brightness", w, "skyPicBright", 0.2, 2, 2, "x")
                AddLabel(p, SKYPIC.Status)
                AddLabel(p, "Pictures: data/nyx/bg/ (png, jpg)")
                AddLabel(p, "or: nyx_sky_url <link> [name]")
            end)
        end)
        EndGroup(g)
    end

    -- movement
    do
        local left, right = Cols(pages[5])

        local g = NewGroup(left, "Bunny hop")
        AddCheck(g, "Bunny hop", cfg.move, "bhop")
        AddLabel(g, "Hold jump, the hop is re-pressed on landing")
        EndGroup(g)

        local m = cfg.move
        g = NewGroup(left, "Edge bug")
        AddCheck(g, "Edge bug", m, "edgebug", function(p)
            AddSlider(p, "Predict ticks", m, "ebTicks", 2, 64, 0, " ticks")
            AddCheck(p, "Advanced search (keys + mouse)", m, "ebAdvanced")
            AddSlider(p, "Turn scale", m, "ebTurnScale", 0, 1, 2, "x")
            AddSlider(p, "Mouse lock", m, "ebLock", 0, 0.95, 2)
            AddCheck(p, "Draw predicted fall", m, "ebDraw")
            AddCheck(p, "Indicator", m, "ebIndicator")
            AddLabel(p, "Tries stand / duck, with and")
            AddLabel(p, "without your keys; replays the")
            AddLabel(p, "one that clips the fall on an edge.")
        end)
        AddCheck(g, "Advanced edge bug (steer)", m, "ebSteer", function(p)
            AddSlider(p, "Search lines", m, "ebLines", 2, 64, 0)
            AddSlider(p, "Spread", m, "ebSpread", 5, 180, 0, "\194\176")
            AddSlider(p, "Search fan every", m, "ebFanEvery", 1, 8, 0, " ticks")
            AddLabel(p, "When your own keys find nothing,")
            AddLabel(p, "a fan of strafe directions (ducked")
            AddLabel(p, "and standing) is simulated and the")
            AddLabel(p, "soonest edge bug is flown to.")
            AddLabel(p, "More lines = more CPU per tick.")
        end)
        AddCheck(g, "Texture bug", m, "texturebug", function(p)
            AddSlider(p, "Press 1", m, "tbFwd1", 0, 5, 2)
            AddSlider(p, "Press 2", m, "tbFwd2", 0, 5, 2)
            AddSlider(p, "Angle start", m, "tbAngleStart", 0, 90, 0, "\194\176")
            AddSlider(p, "Angle end", m, "tbAngleEnd", 1, 180, 0, "\194\176")
            AddSlider(p, "Angle step", m, "tbWiggle", 0.25, 10, 2, "\194\176")
            AddSlider(p, "Wall hug under", m, "tbHug", 0, 5, 2, "u")
            AddSlider(p, "Wall scan step", m, "tbZStep", 1, 16, 0, "u")
            AddCheck(p, "Also try the other duck state", m, "tbBothDuck")
            AddSlider(p, "Candidates per tick", m, "tbBudget", 10, 600, 0)
            AddSlider(p, "Catch within", m, "tbAhead", 1, 8, 0, " ticks")
            AddCheck(p, "Quarter-hull ground check", m, "simQuads")
            AddLabel(p, MV.TBStatus, C.accent)
            AddLabel(p, "Fall along a wall holding the key:")
            AddLabel(p, "tiny presses at angles to the wall")
            AddLabel(p, "until the tick ends at +-half gravity.")
            AddLabel(p, "Smaller step = finer, more CPU.")
        end)
        AddCheck(g, "Wall hang (any wall)", m, "wallhang", function(p)
            AddSlider(p, "Close in from", m, "whApproach", 0, 16, 1, "u")
            AddLabel(p, MV.WHStatus, C.accent)
            AddLabel(p, "The texture bug's catch on any wall:")
            AddLabel(p, "slanted walls count, a wall the hull")
            AddLabel(p, "touches is found too, and presses along")
            AddLabel(p, "the map axes are tried (diagonals).")
            AddLabel(p, "Search settings: those of Texture bug.")
        end)
        AddLabel(g, MV.Status, C.accent)
        AddLabel(g, "Right-click the check: bind it (hold)")
        EndGroup(g)

        g = NewGroup(right, "Autostrafe")
        AddCheck(g, "Autostrafe", cfg.move, "autostrafe", function(p)
            AddList(p, "Mode", cfg.move, "strafeMode", {{"Directional", "directional"}, {"Mouse", "mouse"}})
            AddLabel(p, "Directional: toward your WASD keys")
            AddLabel(p, "Mouse: the way you move the mouse")
        end)
        EndGroup(g)

        g = NewGroup(right, "Circle strafe")
        AddCheck(g, "Adaptive circle strafe", cfg.move, "circle", function(p)
            AddList(p, "Direction", cfg.move, "circleSide", {{"Left", "left"}, {"Right", "right"}})
            AddCheck(p, "Flip on walls", cfg.move, "circleAvoid")
            AddSlider(p, "Min speed", cfg.move, "circleMinSpeed", 0, 300, 0, " u/s")
            AddLabel(p, "Right-click the checkbox: bind (hold)")
        end)
        AddLabel(g, "In the air; the circle follows speed")
        EndGroup(g)

        g = NewGroup(right, "Airstuck")
        AddCheck(g, "Airstuck (module)", m, "airstuck", function(p)
            AddSlider(p, "Hold at most", m, "asMax", 0.2, 20, 1, "s")
            AddLabel(p, "No packet goes out while held, so the")
            AddLabel(p, "server stops moving you. Long holds")
            AddLabel(p, "time out (sv_timeout) - keep it short.")
            AddLabel(p, "Right-click the checkbox: bind (hold)")
        end)
        AddLabel(g, MV.FakeLagStatus, C.accent)
        AddLabel(g, BT.ModStatus)
        EndGroup(g)

        g = NewGroup(left, "Network")
        AddList(g, "Interpolation", cfg.interp, "mode", {
            {"Default (restore)", "default"},
            {"Minimal lerp", "low"},
            {"Off (no interpolation)", "off"},
            {"Smooth (ratio 3)", "smooth"},
        })
        AddLabel(g, NET.Status)
        EndGroup(g)
    end

    -- misc
    do
        local left, right = Cols(pages[6])

        local tn = cfg.taunt
        local g = NewGroup(right, "Taunt spam")
        AddCheck(g, "Taunt spam", tn, "enabled", function(p)
            AddCheck(p, "Keep moving during taunts", tn, "move")
            AddList(p, "Taunt", tn, "name", TAUNTS)
            AddSlider(p, "Interval", tn, "interval", 0.1, 5, 1, "s")
        end)
        AddCheck(g, "Hide taunts in first person", tn, "hideFirst")
        EndGroup(g)

        local bs = cfg.bagspam
        g = NewGroup(right, "Item bags")
        AddCheck(g, "Item bag spam", bs, "enabled", function(p)
            AddCheck(p, "Turn onto the bag (silent)", bs, "aim")
            AddList(p, "Send mode", bs, "mode", {
                {"As is", "none"},
                {"Spread (max rate)", "rate"},
                {"Burst (many uses per tick)", "burst"},
                {"Net burst (gRust.Interact)", "net"},
            })
            AddSlider(p, "Burst cmdrate", bs, "burstRate", 5, 40, 0)
            AddSlider(p, "Net: messages per burst", bs, "netCount", 1, 50, 0)
            AddSlider(p, "Net: wait per bag", bs, "netWait", 0.1, 5, 1, "s")
            AddSlider(p, "Reach", bs, "range", 30, 200, 0, "u")
            AddLabel(p, BAG.Status)
            AddLabel(p, "Burst: low cmdrate + high FPS = more")
            AddLabel(p, "uses in one tick. fps_max 0 in console.")
            AddLabel(p, "Right-click the check: bind it to Hold")
            AddLabel(p, "Class: console  nyx_bag_class <class>")
            AddLabel(p, "(default rust_itembag)")
        end)
        EndGroup(g)

        local nl, log = cfg.netlog, BAG.Log
        g = NewGroup(right, "Net logger")
        AddCheck(g, "Log net messages", nl, "enabled", function(p)
            AddCheck(p, "Print to console live", nl, "print")
            AddCheck(p, "Also log incoming (with every read)", nl, "incoming")
            AddButton(p, "Dump last 40 to console", function() log.Dump(40) end)
            AddButton(p, "Ignore the last message", log.IgnoreLast)
            AddButton(p, "Replay the last sent", log.ReplayLast)
            AddButton(p, "Save to data/nyx/netlog.txt", log.Save)
            AddButton(p, "Clear", log.Clear)
            AddLabel(p, "Marker before an action, then do it:")
            AddLabel(p, "what follows is what it sent.")
            AddLabel(p, "bind a key: bind f6 nyx_net_mark")
            AddLabel(p, "Window: bind f7 nyx_net_menu")
            AddLabel(p, "Console: nyx_net_replay <#> [times]")
            AddLabel(p, "         nyx_net_lua <#> (copies it)")
        end)
        AddButton(g, "Open log window", log.ToggleWindow)
        AddButton(g, "Insert marker", log.Mark)
        AddLabel(g, log.Status, C.accent)
        EndGroup(g)

        local ks = cfg.killsay
        g = NewGroup(right, "Killsay")
        AddCheck(g, "Killsay (trashtalk)", ks, "enabled", function(p)
            AddList(p, "Language", ks, "set", {
                {"English", "english"}, {"Russian", "russian"}, {"Both", "both"}, {"Custom text", "custom"},
            })
            AddSlider(p, "Delay", ks, "delay", 0, 5, 1, "s")
            AddLabel(p, KS.Status)
            AddLabel(p, "Custom: console  nyx_killsay <text>")
            AddLabel(p, "{name} = the victim's name")
        end)
        EndGroup(g)

        g = NewGroup(right, "Animation (local)")
        AddCheck(g, "T-pose everyone", cfg.tpose, "enabled", function(p)
            AddCheck(p, "Include yourself", cfg.tpose, "includeSelf")
            AddLabel(p, "Visual only: the aimbot then uses")
            AddLabel(p, "eye / body-centre points, not bones")
        end)
        AddCheck(g, "Sequence override", cfg.seq, "enabled", function(p)
            AddSlider(p, "Sequence index", cfg.seq, "index", 0, 400, 0)
            AddLabel(p, function()
                local me = LocalPlayer()
                if not IsValid(me) then return "" end
                local idx = math.Clamp(math.floor(cfg.seq.index), 0, math.max(me:GetSequenceCount() - 1, 0))
                return "Name: " .. tostring(me:GetSequenceName(idx))
            end)
            AddLabel(p, "Only you see it (third person)")
        end)
        EndGroup(g)

        local g = NewGroup(left, "Anti screengrab")
        AddCheck(g, "Anti SS", cfg.misc, "antiSS")
        AddLabel(g, "Hides ESP, FOV circle, third person and")
        AddLabel(g, "this menu from render.Capture / jpeg")
        AddLabel(g, function() return "Captures hidden: " .. SSG.hidden end, C.accent)
        AddCheck(g, "Grab alert", cfg.misc, "ssAlert", function(p)
            AddCheck(p, "Shutter sound", cfg.misc, "ssSound")
            AddCheck(p, "Show + save the grab", cfg.misc, "ssPreview")
            AddLabel(p, "Saved to data/nyx/grabs/")
        end)
        AddLabel(g, function() return "Grabs seen: " .. SSG.grabs end, C.accent)
        AddButton(g, "Show last grab", function() SSG.time = RealTime() end)
        EndGroup(g)

        local wm = cfg.watermark
        g = NewGroup(left, "Watermark")
        AddCheck(g, "Watermark", wm, "enabled", function(p)
            AddList(p, "Style", wm, "style", {{"Bar", "bar"}, {"Skeet panel", "skeet"}})
            AddList(p, "Corner", wm, "corner", {
                {"Top left", "tl"}, {"Top right", "tr"}, {"Bottom left", "bl"}, {"Bottom right", "br"},
            })
            AddCheck(p, "Info panel (angle / ping)", wm, "info")
            AddCheck(p, "User name", wm, "showUser")
            AddCheck(p, "Server (bar)", wm, "showServer")
            AddCheck(p, "FPS (bar)", wm, "showFps")
            AddCheck(p, "Ping", wm, "showPing")
            AddCheck(p, "Tickrate (bar)", wm, "showTick")
            AddCheck(p, "Time", wm, "showTime")
            AddColor(p, "Accent color", wm, "r", "g", "b")
        end)
        EndGroup(g)

        local kl, sl = cfg.keylist, cfg.speclist
        g = NewGroup(left, "HUD lists")
        AddCheck(g, "Keybind list", kl, "enabled", function(p)
            AddSlider(p, "Position X", kl, "xPct", 0, 95, 0, "%")
            AddSlider(p, "Position Y", kl, "yPct", 0, 95, 0, "%")
            AddCheck(p, "Also list inactive binds", kl, "showInactive")
        end)
        AddCheck(g, "Spectator list", sl, "enabled", function(p)
            AddSlider(p, "Position X", sl, "xPct", 0, 95, 0, "%")
            AddSlider(p, "Position Y", sl, "yPct", 0, 95, 0, "%")
        end)
        local ind = cfg.indicator
        AddCheck(g, "Speed / bind indicator", ind, "enabled", function(p)
            AddCheck(p, "Speed", ind, "speed")
            AddColor(p, "Speed color", ind, "r", "g", "b")
            AddCheck(p, "Green / red on gain / loss", ind, "gainColor")
            AddCheck(p, "Active binds", ind, "binds")
            AddCheck(p, "All binds (not only movement)", ind, "allBinds")
            AddSlider(p, "Position Y", ind, "yPct", 30, 95, 0, "%")
            AddSlider(p, "Speed size", ind, "scale", 0.5, 4, 2, "x")
            AddSlider(p, "Binds size", ind, "bindScale", 0.5, 4, 2, "x")
            AddLabel(p, "Binds show when set to hold /")
            AddLabel(p, "toggle with a key (right-click).")
        end)
        EndGroup(g)

        g = NewGroup(left, "Menu")
        AddCheck(g, "Menu animations", cfg.menu, "anim", function(p)
            AddSlider(p, "Speed", cfg.menu, "speed", 0.3, 3, 1, "x")
        end)
        AddLabel(g, "Right-click a checkbox  -  bind it")
        AddLabel(g, "Arrow on a row  -  its settings")
        AddLabel(g, "INSERT  -  toggle menu")
        AddLabel(g, "CTRL+F  -  search functions")
        AddButton(g, "Reset menu size", function()
            cfg.menu.w, cfg.menu.h = 660, 520
            if IsValid(menu) and menu.Resize then menu.Resize(660, 520) end
        end)
        AddButton(g, "Unload", function() NyxUnload() end)
        EndGroup(g)
    end

    -- config
    do
        local left, right = Cols(pages[7])

        local g = NewGroup(left, "Configs")
        CFGS.AddSlots(g)
        AddButton(g, "Save to slot", CFGS.Save)
        AddButton(g, "Load slot", CFGS.Load)
        AddButton(g, "Delete slot", CFGS.Delete)
        AddButton(g, "Reset all to defaults", CFGS.Reset)
        AddLabel(g, CFGS.Status, C.accent)
        EndGroup(g)

        g = NewGroup(right, "Console")
        AddLabel(g, "nyx_config_save <name>")
        AddLabel(g, "nyx_config_load <name>")
        AddLabel(g, "nyx_config_list")
        AddLabel(g, "Files: garrysmod/data/nyx/")
        AddLabel(g, "Saved: every setting + all binds")
        EndGroup(g)

        local bgc = cfg.bg
        g = NewGroup(right, "Background")
        AddCheck(g, "Background picture", bgc, "enabled", function(p)
            AddSlider(p, "Opacity", bgc, "opacity", 0.05, 1, 2)
            AddList(p, "Animation", bgc, "mode", {
                {"Static", "static"}, {"Drift (pan + zoom)", "drift"}, {"Pulse", "pulse"}, {"Drift + pulse", "both"},
            })
            AddSlider(p, "Speed", bgc, "speed", 0.1, 4, 1, "x")
            AddCheck(p, "Twinkling dots", bgc, "twinkle")
            AddColor(p, "Tint", bgc, "r", "g", "b")
        end)
        BG.AddPicker(g)
        AddButton(g, "Next page", BG.NextPage)
        AddButton(g, "Refresh list", BG.Refresh)
        AddButton(g, "Delete selected", BG.DeleteSelected)
        AddLabel(g, BG.Status, C.accent)
        AddLabel(g, "Put png / jpg in data/nyx/bg/")
        AddLabel(g, "or: nyx_bg_url <link> [name]")
        EndGroup(g)
    end

    -- players
    do
        SEARCH.tab = 8
        PL.BuildPage(pages[8])
    end

    -- entities
    do
        local left, right = Cols(pages[9])
        PL.EV.BuildPage(left, right)
    end

    SEARCH.tab = nil           -- popups built from here on are not part of the index

    -- tab column
    local tabs = {}

    for i = 1, #TABS do
        local tab = vgui.Create("Panel", frame)
        tabs[i] = tab
        tab:SetPos(0, TAB_Y + (i - 1) * TAB_H)
        tab:SetSize(TAB_W, TAB_H)
        tab:SetCursor("hand")

        tab.sel, tab.hov = (lastTab == i) and 1 or 0, 0

        tab.Paint = function(self, w, h)
            self.sel = ANIM.Step(self.sel, lastTab == i and 1 or 0, 12)
            self.hov = ANIM.Step(self.hov, self:IsHovered() and 1 or 0, 12)

            if self.sel > 0 then
                surface.SetDrawColor(C.tabBg.r, C.tabBg.g, C.tabBg.b, 255 * self.sel)
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(C.groupBorder.r, C.groupBorder.g, C.groupBorder.b, 255 * self.sel)
                surface.DrawRect(0, 0, w - 1, 1)
                surface.DrawRect(0, h - 1, w - 1, 1)

                -- accent bar on the left edge grows from the middle
                local bh = (h - 16) * self.sel
                surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 255 * self.sel)
                surface.DrawRect(0, (h - bh) / 2, 3, bh)
            end

            -- icon colour eases dim -> hover -> selected
            local col = ANIM.Mix(ANIM.Mix(C.textDim, C.text, self.hov), C.textHi, self.sel)
            ICONS[i](w / 2 + self.sel * 2, h / 2, col)
        end

        tab.OnMousePressed = function(self, code)
            if code ~= MOUSE_LEFT then return end
            ClosePopup()

            if lastTab ~= i then
                lastTab = i
                pages[i].t = 0                  -- the new page animates in
            end

            for j, page in ipairs(pages) do
                page:SetVisible(j == i)
            end
        end
    end

    -- function search (Ctrl+F) ------------------------------------------------------------

    local searchPanel = nil
    local flash = nil               -- {panel, t0}: outline around the function that was picked

    -- the outline is its own click-through panel on top of the pages
    local glow = vgui.Create("Panel", frame)
    glow:SetPos(0, 0)
    glow:SetSize(W, H)
    glow:SetMouseInputEnabled(false)

    glow.Paint = function(self, w, h)
        if not flash then return end

        local age = CurTime() - flash.t0
        if age > 2.6 then
            flash = nil
            return
        end

        local target = flash.panel
        if not IsValid(target) or not target:IsVisible() then return end

        local sx, sy = target:LocalToScreen(0, 0)
        local x, y = frame:ScreenToLocal(sx, sy)

        local pulse = 0.5 + 0.5 * math.sin(age * 9)
        local a = 255 * (1 - age / 2.6) * (0.4 + 0.6 * pulse)

        surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, a)
        surface.DrawOutlinedRect(x - 4, y - 3, target:GetWide() + 8, target:GetTall() + 6, 2)
    end

    local function CloseSearch()
        if IsValid(searchPanel) then searchPanel:Remove() end
        searchPanel = nil
    end

    SEARCH.close = CloseSearch

    -- go to the tab of the result, outline the function, and open its popup if it lives in one
    local function GoTo(r)
        CloseSearch()
        ClosePopup()

        if lastTab ~= r.tab then
            lastTab = r.tab
            pages[r.tab].t = 0
        end

        for j, page in ipairs(pages) do
            page:SetVisible(j == r.tab)
        end

        local target = r.via and r.via.panel or r.panel
        if IsValid(target) then
            pages[r.tab]:ScrollToPanel(target)   -- the function may sit below the visible part
            pages[r.tab]:ScrollThink()
            flash = {panel = target, t0 = CurTime()}
        end

        if r.via then r.via.open() end
    end

    local function Matches(query)
        local out, seen = {}, {}
        query = string.lower(string.Trim(query))
        if query == "" then return out end

        for _, e in ipairs(SEARCH.index) do
            local name = string.lower(e.text)
            local pos = string.find(name, query, 1, true)
            local viaPos = e.via and string.find(string.lower(e.via.text), query, 1, true)

            if pos or viaPos then
                local label = e.text .. "|" .. e.tab .. "|" .. (e.via and e.via.text or "")

                if not seen[label] then
                    seen[label] = true

                    local score = (pos == 1) and 0 or (pos and 1 or 2)
                    if e.kind == "group" then score = score + 0.5 end

                    out[#out + 1] = {entry = e, score = score}
                end
            end
        end

        table.sort(out, function(a, b)
            if a.score ~= b.score then return a.score < b.score end
            return a.entry.text < b.entry.text
        end)

        return out
    end

    -- Typing is read by polling the keys, the same way the bind capture reads them. A real text
    -- field inside the menu never received the keyboard (the menu keeps it off so WASD works),
    -- so the search keeps its own text and the keys it needs are checked every frame.
    local SEARCH_CHARS = {}                       -- key code -> character
    for i = 0, 9 do SEARCH_CHARS[KEY_0 + i] = tostring(i) end
    for i = 0, 25 do SEARCH_CHARS[KEY_A + i] = string.char(97 + i) end
    SEARCH_CHARS[KEY_SPACE] = " "
    SEARCH_CHARS[KEY_MINUS] = "-"
    SEARCH_CHARS[KEY_SLASH] = "/"

    local SEARCH_KEYLIST = {}
    for code in pairs(SEARCH_CHARS) do SEARCH_KEYLIST[#SEARCH_KEYLIST + 1] = code end
    table.sort(SEARCH_KEYLIST)

    local SEARCH_CTRL = {KEY_BACKSPACE, KEY_ENTER, KEY_PAD_ENTER, KEY_ESCAPE, KEY_UP, KEY_DOWN}

    -- while the search is open the game must not see the keys that are being typed
    AddHook("PlayerBindPress", "searchblock", function()
        if IsValid(searchPanel) then return true end
    end)

    local function OpenSearch()
        if IsValid(searchPanel) then return end

        local PW, ROW_H, MAX_ROWS = 380, 20, 9

        local sp = vgui.Create("Panel", frame)
        searchPanel = sp
        sp:SetSize(PW, 50)
        sp:SetPos(TAB_W + (W - TAB_W - PW) / 2, 34)
        sp:SetAlpha(0)
        sp:MoveToFront()

        sp.fade = 0
        sp.text = ""
        sp.results = {}
        sp.sel = 1

        local function Refresh()
            local all = Matches(sp.text)

            sp.results = {}
            for i = 1, math.min(#all, MAX_ROWS) do
                sp.results[i] = all[i].entry
            end

            sp.sel = 1
            sp:SetTall(50 + math.max(#sp.results, 1) * ROW_H + 6)
        end

        -- key state: a key that is already down when the search opens (the F of Ctrl+F) does not
        -- type; a held key repeats after a short delay
        local state = {}
        do
            local now = SysTime()

            for _, code in ipairs(SEARCH_KEYLIST) do state[code] = {down = input.IsKeyDown(code), rep = now + 0.4} end
            for _, code in ipairs(SEARCH_CTRL) do state[code] = {down = input.IsKeyDown(code), rep = now + 0.4} end
        end

        local function Fire(code)
            local s = state[code]

            if not input.IsKeyDown(code) then
                s.down = false
                return false
            end

            local now = SysTime()

            if not s.down then
                s.down = true
                s.rep = now + 0.4
                return true
            end

            if now >= s.rep then
                s.rep = now + (code == KEY_BACKSPACE and 0.03 or 0.045)
                return true
            end

            return false
        end

        sp.Think = function(self)
            if not IsValid(frame) or frame.closing then
                CloseSearch()
                return
            end

            self.fade = ANIM.Step(self.fade, 1, 14)
            self:SetAlpha(255 * self.fade)

            local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
            local changed = false

            for _, code in ipairs(SEARCH_KEYLIST) do
                if Fire(code) and not ctrl and #self.text < 32 then
                    self.text = self.text .. SEARCH_CHARS[code]
                    changed = true
                end
            end

            if Fire(KEY_BACKSPACE) and #self.text > 0 then
                self.text = string.sub(self.text, 1, -2)
                changed = true
            end

            if changed then Refresh() end

            if Fire(KEY_DOWN) then self.sel = math.min(self.sel + 1, math.max(#self.results, 1)) end
            if Fire(KEY_UP) then self.sel = math.max(self.sel - 1, 1) end

            local enter = Fire(KEY_ENTER)
            if Fire(KEY_PAD_ENTER) then enter = true end

            if Fire(KEY_ESCAPE) then
                CloseSearch()
                gui.HideGameUI()
                return
            end

            if enter and self.results[self.sel] then GoTo(self.results[self.sel]) end
        end

        sp.Paint = function(self, w, h)
            surface.SetDrawColor(C.tabBg)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            surface.SetDrawColor(C.accent)
            surface.DrawRect(1, 1, w - 2, 1)

            draw.SimpleText("Search functions", "NyxUIBold", 10, 8, C.textHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("Enter = go, Esc = close", "NyxUISmall", w - 10, 9, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

            -- the text field
            surface.SetDrawColor(C.field)
            surface.DrawRect(10, 24, w - 20, 20)
            surface.SetDrawColor(C.accent)
            surface.DrawOutlinedRect(10, 24, w - 20, 20, 1)

            draw.SimpleText(self.text, "NyxUI", 16, 34, C.textHi, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            if math.floor(SysTime() * 2) % 2 == 0 then
                surface.SetFont("NyxUI")
                local tw = surface.GetTextSize(self.text)

                surface.SetDrawColor(C.textHi)
                surface.DrawRect(16 + tw + 1, 28, 1, 12)
            end

            if #self.results == 0 then
                local msg = self.text == "" and "Type a name: aim, chams, fog, bhop..." or "Nothing found"
                draw.SimpleText(msg, "NyxUI", 12, 56 + 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                return
            end

            for i, e in ipairs(self.results) do
                local y = 50 + (i - 1) * ROW_H

                if i == self.sel then
                    surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 40)
                    surface.DrawRect(1, y, w - 2, ROW_H)
                    surface.SetDrawColor(C.accent)
                    surface.DrawRect(1, y, 2, ROW_H)
                end

                draw.SimpleText(e.text, "NyxUI", 12, y + ROW_H / 2, i == self.sel and C.textHi or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                local where = TABS[e.tab] .. (e.via and ("  >  " .. e.via.text) or "")
                draw.SimpleText(where, "NyxUISmall", w - 10, y + ROW_H / 2, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end

        local function RowAt(self)
            local _, y = self:CursorPos()
            local i = math.floor((y - 50) / ROW_H) + 1
            if i >= 1 and i <= #self.results then return i end
        end

        sp.OnCursorMoved = function(self)
            local i = RowAt(self)
            if i then self.sel = i end
        end

        sp.OnMousePressed = function(self, code)
            if code ~= MOUSE_LEFT then return end

            local i = RowAt(self)
            if i then GoTo(self.results[i]) end
        end

        Refresh()
        WrapPaint(sp)
    end

    SEARCH.toggle = function()
        if IsValid(searchPanel) then
            CloseSearch()
        else
            OpenSearch()
        end
    end

    -- resizing ------------------------------------------------------------------------
    -- Live: every frame of the drag the panels that exist are moved and resized, nothing is
    -- rebuilt. Widget heights never depend on the width, so a group keeps its y and only its
    -- x / width change; every widget fills its group (14 px margin each side) and paints from
    -- its own size. Columns follow their kind: left / right split the page in two, "fill"
    -- (the Players page) takes whatever is right of its x.
    local GRIP = 14
    local grip = vgui.Create("Panel", frame)
    grip:SetSize(GRIP, GRIP)
    grip:SetPos(W - GRIP, H - GRIP)
    grip:SetCursor("sizenwse")

    local function Layout(w, h)
        W, H = w, h
        PAGE_W, PAGE_H = W - PAGE_X - 12, H - PAGE_Y - 12
        COL_W = math.floor((PAGE_W - 16) / 2)
        TAB_H = math.Clamp(math.floor((H - TAB_Y - 8) / #TABS), 40, 58)

        frame:SetSize(W, H)
        handle:SetWide(W)
        glow:SetSize(W, H)
        grip:SetPos(W - GRIP, H - GRIP)

        for i, tab in ipairs(tabs) do
            tab:SetPos(0, TAB_Y + (i - 1) * TAB_H)
            tab:SetSize(TAB_W, TAB_H)
        end

        for _, page in ipairs(pages) do
            page:SetSize(PAGE_W, PAGE_H)

            for _, g in ipairs(page:GetChildren()) do
                local c = g.col

                if c then
                    if c.kind == "left" then
                        c.w = COL_W
                    elseif c.kind == "right" then
                        c.x, c.w = COL_W + 16, COL_W
                    elseif c.kind == "fill" then
                        c.w = math.max(PAGE_W - c.x, 200)
                    end

                    g:SetPos(c.x, g:GetY())
                    g:SetWide(c.w)

                    for _, widget in ipairs(g:GetChildren()) do widget:SetWide(c.w - 28) end
                end
            end
        end

        if IsValid(searchPanel) then
            searchPanel:SetPos(TAB_W + (W - TAB_W - searchPanel:GetWide()) / 2, searchPanel:GetY())
        end
    end

    frame.Resize = function(w, h)
        Layout(math.Clamp(w, MIN_W, math.max(MIN_W, ScrW() - 20)), math.Clamp(h, MIN_H, math.max(MIN_H, ScrH() - 20)))
        cfg.menu.w, cfg.menu.h = W, H
    end

    grip.Paint = function(self, w, h)
        local col = (self:IsHovered() or self.drag) and C.accent or C.textDim
        surface.SetDrawColor(col)

        for i = 0, 2 do
            local o = 4 + i * 4
            surface.DrawLine(w - 2, h - o, w - o, h - 2)
        end
    end

    grip.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end

        ClosePopup()        -- a popup is placed against the old size
        self.drag = {gui.MouseX(), gui.MouseY(), W, H}
        self:MouseCapture(true)
    end

    grip.Think = function(self)
        if not self.drag then return end

        local d = self.drag
        local w, h = d[3] + gui.MouseX() - d[1], d[4] + gui.MouseY() - d[2]

        -- only when the clamped size actually changes
        local cw = math.Clamp(w, MIN_W, math.max(MIN_W, ScrW() - 20))
        local ch = math.Clamp(h, MIN_H, math.max(MIN_H, ScrH() - 20))
        if cw ~= W or ch ~= H then frame.Resize(cw, ch) end
    end

    grip.OnMouseReleased = function(self)
        self.drag = nil
        self:MouseCapture(false)
    end

    grip:MoveToFront()

    WrapPaint(frame)
end

local function ToggleMenu()
    if IsValid(menu) then
        if menu.closing then
            menu.closing = false             -- opened again while it was still fading out
        elseif cfg.menu.anim then
            ClosePopup()
            menu.closing = true              -- its Think fades it out and removes it
        else
            menu:Remove()
        end
    else
        BuildMenu()
    end
end

-- ---------------------------------------------------------------------------
-- watermark: "bar" is one rounded strip (name | user | server | fps | ping | tick | time),
-- "skeet" a flat panel with the gradient line (name | user | delay | time). The optional info
-- panel under it shows the anti-aim angle difference, packet loss, ping and tickrate.
-- ---------------------------------------------------------------------------

do
    local fps = 60
    local COL_BG = Color(13, 13, 13, 232)
    local COL_TEXT = Color(225, 225, 225, 255)
    local COL_DIM = Color(110, 110, 110, 255)
    local PAD, BAR_H, GAP, INFO_H = 10, 22, 4, 40

    AddHook("HUDPaint", "watermark", function()
        local wm = cfg.watermark
        if not wm.enabled or IsHidden() then return end

        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        fps = fps + (1 / math.max(RealFrameTime(), 0.001) - fps) * 0.05

        local accent = Color(wm.r, wm.g, wm.b, 255)
        local ping = ply:Ping()
        local tick = math.floor(1 / engine.TickInterval() + 0.5)

        -- segments: {text, colour}
        local segs = {{wm.name, accent}}

        if wm.style == "skeet" then
            if wm.showUser then segs[#segs + 1] = {ply:Nick(), COL_TEXT} end
            if wm.showPing then segs[#segs + 1] = {"delay: " .. ping .. "ms", COL_TEXT} end
            if wm.showTime then segs[#segs + 1] = {os.date("%H:%M:%S"), COL_TEXT} end
        else
            if wm.showUser then segs[#segs + 1] = {ply:Nick(), COL_TEXT} end
            if wm.showServer then segs[#segs + 1] = {game.GetIPAddress(), COL_TEXT} end
            if wm.showFps then segs[#segs + 1] = {math.floor(fps + 0.5) .. " FPS", COL_TEXT} end
            if wm.showPing then segs[#segs + 1] = {ping .. " ms", COL_TEXT} end
            if wm.showTick then segs[#segs + 1] = {tick .. " tick", COL_TEXT} end
            if wm.showTime then segs[#segs + 1] = {os.date("%H:%M:%S"), COL_TEXT} end
        end

        -- layout
        surface.SetFont("NyxUI")
        local sepW = surface.GetTextSize(" | ")
        local textW = 0

        for i, s in ipairs(segs) do
            s[3] = surface.GetTextSize(s[1])
            textW = textW + s[3] + (i > 1 and sepW or 0)
        end

        local w = textW + PAD * 2
        local infoW = math.max(w, 170)
        local totalH = BAR_H + (wm.info and (GAP + INFO_H) or 0)

        local right = wm.corner == "tr" or wm.corner == "br"
        local top = wm.corner == "tl" or wm.corner == "tr"

        local x = right and (ScrW() - w - 10) or 10
        local y = top and 10 or (ScrH() - totalH - 10)

        -- the strip
        if wm.style == "skeet" then
            surface.SetDrawColor(COL_BG)
            surface.DrawRect(x, y, w, BAR_H)
            surface.SetDrawColor(50, 50, 50, 255)
            surface.DrawOutlinedRect(x, y, w, BAR_H, 1)

            for gx = 0, w - 1, 2 do
                local r, g, b = GradientAt(gx / w)
                surface.SetDrawColor(r, g, b, 255)
                surface.DrawRect(x + gx, y, 2, 2)
            end
        else
            draw.RoundedBox(5, x, y, w, BAR_H, COL_BG)
            surface.SetDrawColor(accent.r, accent.g, accent.b, 170)
            surface.DrawRect(x + 7, y + BAR_H - 2, w - 14, 1)
        end

        local tx, ty = x + PAD, y + BAR_H / 2
        for i, s in ipairs(segs) do
            if i > 1 then
                draw.SimpleText(" | ", "NyxUI", tx, ty, COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                tx = tx + sepW
            end

            draw.SimpleText(s[1], "NyxUI", tx, ty, s[2], TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            tx = tx + s[3]
        end

        -- the info panel
        if wm.info then
            local ix = right and (ScrW() - infoW - 10) or 10
            local iy = y + BAR_H + GAP

            surface.SetDrawColor(COL_BG)
            surface.DrawRect(ix, iy, infoW, INFO_H)
            surface.SetDrawColor(50, 50, 50, 255)
            surface.DrawOutlinedRect(ix, iy, infoW, INFO_H, 1)
            surface.SetDrawColor(accent)
            surface.DrawRect(ix + 1, iy + 1, infoW - 2, 1)

            -- row 1: how far the sent yaw is from your real one, and packet loss
            local fake = aaActive and math.abs(math.NormalizeAngle((MV.aaYaw or sentAng.y) - realAng.y)) or 0
            draw.SimpleText(string.format("FAKE (%.1f\194\176)", fake), "NyxUI", ix + 8, iy + 12, accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("LOSS " .. ply:PacketLoss() .. "%", "NyxUI", ix + infoW - 8, iy + 12, COL_TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

            -- row 2: IO, a three bar quality meter, then ping / tickrate
            local bars = ping < 60 and 3 or (ping < 140 and 2 or 1)
            draw.SimpleText("IO", "NyxUI", ix + 8, iy + 28, COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            for i = 1, 3 do
                local bh = 3 + i * 3
                if i <= bars then
                    surface.SetDrawColor(accent)
                else
                    surface.SetDrawColor(55, 55, 55, 255)
                end
                surface.DrawRect(ix + 28 + (i - 1) * 6, iy + 33 - bh, 4, bh)
            end

            draw.SimpleText(string.format("%dms / %dhz", ping, tick), "NyxUI", ix + infoW - 8, iy + 28, COL_TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- HUD lists: active keybinds, and the players spectating you. Both are small panels in the
-- watermark's style (dark box, gradient line, title); their rows ease in and out, and the panel
-- grows / shrinks with them, so a bind switching on or somebody starting to watch is animated.
-- ---------------------------------------------------------------------------

do
    local COL_BG = Color(13, 13, 13, 228)
    local COL_TEXT = Color(225, 225, 225, 255)
    local COL_DIM = Color(110, 110, 110, 255)
    local PAD, TITLE_H, ROW_H, MIN_W = 8, 20, 16, 130

    local stores = {keys = {}, spec = {}}   -- per list: row id -> {text, right, col, order, vis}
    local shown = {keys = 0, spec = 0}      -- eased visibility of each whole panel

    -- rows: array of {id, text, right, col, order}; returns the animated row list
    local function Rows(listId, rows)
        local store = stores[listId]
        local seen = {}

        for _, r in ipairs(rows) do
            seen[r.id] = true

            local s = store[r.id]
            if not s then
                s = {vis = 0}
                store[r.id] = s
            end

            s.text, s.right, s.col, s.order = r.text, r.right, r.col, r.order or 0
        end

        local list = {}
        for id, s in pairs(store) do
            s.vis = ANIM.Step(s.vis, seen[id] and 1 or 0, 10)

            if not seen[id] and s.vis <= 0.01 then
                store[id] = nil
            else
                list[#list + 1] = s
            end
        end

        table.sort(list, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.text < b.text
        end)

        return list
    end

    local function DrawList(listId, title, x, y, rows)
        local list = Rows(listId, rows)

        shown[listId] = ANIM.Step(shown[listId], #list > 0 and 1 or 0, 10)
        if shown[listId] <= 0.01 then return end

        local a = shown[listId]

        surface.SetFont("NyxUI")
        local w = MIN_W
        local h = TITLE_H + 4

        for _, s in ipairs(list) do
            local tw = surface.GetTextSize(s.text) + PAD * 2
            if s.right then tw = tw + surface.GetTextSize(s.right) + 14 end

            w = math.max(w, tw)
            h = h + ROW_H * s.vis
        end

        surface.SetDrawColor(13, 13, 13, 228 * a)
        surface.DrawRect(x, y, w, h)
        surface.SetDrawColor(50, 50, 50, 255 * a)
        surface.DrawOutlinedRect(x, y, w, h, 1)

        for gx = 0, w - 1, 2 do
            local r, g, b = GradientAt(gx / w)
            surface.SetDrawColor(r, g, b, 255 * a)
            surface.DrawRect(x + gx, y, 2, 2)
        end

        draw.SimpleText(title, "NyxUIBold", x + PAD, y + 5, Color(255, 255, 255, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local ry = y + TITLE_H + 2
        for _, s in ipairs(list) do
            local c = s.col or COL_TEXT
            local al = 255 * s.vis * a
            local slide = (1 - s.vis) * -14

            draw.SimpleText(s.text, "NyxUI", x + PAD + slide, ry + 2, Color(c.r, c.g, c.b, al), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            if s.right then
                draw.SimpleText(s.right, "NyxUISmall", x + w - PAD + slide, ry + 3, Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, al), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            end

            ry = ry + ROW_H * s.vis
        end
    end

    AddHook("HUDPaint", "lists", function()
        if IsHidden() then return end

        local me = LocalPlayer()
        if not IsValid(me) then return end

        local sw, sh = ScrW(), ScrH()

        -- keybind list: every feature with a hotkey, listed while it is on
        local kl = cfg.keylist
        local keyRows = {}

        if kl.enabled then
            for _, e in ipairs(bindList) do
                if e.mode ~= "always" and e.code then
                    local active = e.tbl[e.key] and true or false

                    if active or kl.showInactive then
                        keyRows[#keyRows + 1] = {
                            id = e,
                            text = e.name or e.key,
                            right = "[" .. MODE_SHORT[e.mode] .. " " .. KeyName(e.code) .. "]",
                            col = active and C.accent or COL_DIM,
                            order = active and 0 or 1,
                        }
                    end
                end
            end
        end

        DrawList("keys", "keybinds", sw * kl.xPct / 100, sh * kl.yPct / 100, keyRows)

        -- spectator list: dead / observing players whose target is you
        local sl = cfg.speclist
        local specRows = {}

        if sl.enabled then
            local modeTag = {[OBS_MODE_IN_EYE] = "1st person", [OBS_MODE_CHASE] = "3rd person", [OBS_MODE_ROAMING] = "free cam"}

            for _, v in ipairs(player.GetAll()) do
                if v ~= me and v:GetObserverMode() ~= OBS_MODE_NONE and v:GetObserverTarget() == me then
                    local col = COL_TEXT
                    if FR.IsTarget(v) then
                        col = FR.targetColor
                    elseif FR.Is(v) then
                        col = FR.color
                    end

                    specRows[#specRows + 1] = {
                        id = v,
                        text = v:Nick(),
                        right = modeTag[v:GetObserverMode()],
                        col = col,
                    }
                end
            end
        end

        DrawList("spec", "spectators", sw * sl.xPct / 100, sh * sl.yPct / 100, specRows)
    end)
end

-- ---------------------------------------------------------------------------
-- speed / bind indicator: the horizontal speed as a big number under the crosshair and, below
-- it, the short names of the binds that are on right now ("eb" while the edge bug key is held;
-- green once an edge bug is lined up). Only binds set to hold / toggle / release with a key show.
-- ---------------------------------------------------------------------------

do
    -- fonts per pixel size, made the first time a size is needed (the scale slider)
    local fonts = {}

    local function Font(kind, size)
        local name = "NyxInd" .. kind .. size
        if not fonts[name] then
            surface.CreateFont(name, {font = "Verdana", size = size, weight = kind == "Speed" and 800 or 700, antialias = true})
            fonts[name] = true
        end
        return name
    end

    -- cfg table + key -> short name; movement first, anything else only with "all binds"
    local SHORT = {
        {cfg.move, "edgebug", "eb"}, {cfg.move, "ebSteer", "aeb"}, {cfg.move, "texturebug", "tb"},
        {cfg.move, "wallhang", "wh"}, {cfg.aa, "fakelag", "fl"}, {cfg.move, "airstuck", "stuck"},
        {cfg.move, "bhop", "bhop"}, {cfg.move, "autostrafe", "as"},
        {cfg.move, "circle", "cs"},
    }
    local OTHER = {
        {cfg.aim, "enabled", "aim"}, {cfg.rage, "enabled", "rage"}, {cfg.aa, "enabled", "aa"},
        {cfg.view, "thirdperson", "tp"}, {cfg.free, "enabled", "fc"}, {cfg.bagspam, "enabled", "bag"},
    }

    local function ShortName(e)
        for _, s in ipairs(SHORT) do
            if s[1] == e.tbl and s[2] == e.key then return s[3], true end
        end

        for _, s in ipairs(OTHER) do
            if s[1] == e.tbl and s[2] == e.key then return s[3], false end
        end

        -- anything else: the bind's name, lowercase, first word
        local name = string.lower(tostring(e.name or e.key))
        return string.match(name, "^(%S+)") or name, false
    end

    local lastSpeed, gainT, trend = 0, 0, 0

    AddHook("HUDPaint", "indicator", function()
        local ind = cfg.indicator
        if not ind.enabled or IsHidden() then return end

        local me = LocalPlayer()
        if not IsValid(me) or not me:Alive() then return end

        local x = ScrW() / 2
        local y = ScrH() * ind.yPct / 100

        local s = math.Clamp(ind.scale, 0.5, 4)
        local bs = math.Clamp(ind.bindScale, 0.5, 4)
        local speedSize, bindSize = math.floor(26 * s + 0.5), math.floor(20 * bs + 0.5)
        local outline = s >= 1.75 and 2 or 1
        local bindOutline = bs >= 1.75 and 2 or 1

        if ind.speed then
            local speed = math.floor(me:GetVelocity():Length2D() + 0.5)
            local col = Color(ind.r, ind.g, ind.b, 255)

            -- speeding up / slowing down, held for a moment so it doesn't flicker
            if ind.gainColor then
                local now = CurTime()
                if speed ~= lastSpeed then
                    trend = speed > lastSpeed and 1 or -1
                    gainT = now
                    lastSpeed = speed
                end
                if now - gainT < 0.15 then
                    col = trend > 0 and Color(90, 255, 120, 255) or Color(255, 80, 80, 255)
                end
            end

            draw.SimpleTextOutlined(tostring(speed), Font("Speed", speedSize), x, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, outline, Color(0, 0, 0, 160))
            y = y + speedSize
        end

        if ind.binds then
            local names = {}

            for _, e in ipairs(bindList) do
                if e.mode ~= "always" and e.code and e.tbl[e.key] then
                    local short, movement = ShortName(e)

                    if movement or ind.allBinds then
                        local col = Color(255, 255, 255, 255)
                        -- green: an edge bug is lined up / the texture bug caught this tick
                        local live = ((short == "eb" or short == "aeb") and MV.plan)
                            or (short == "tb" and (string.find(MV.TB.status, "hit", 1, true)
                                or string.find(MV.TB.status, "holding", 1, true) or string.find(MV.TB.status, "caught", 1, true)))
                            or (short == "wh" and (string.find(MV.WH.status, "hit", 1, true)
                                or string.find(MV.WH.status, "holding", 1, true) or string.find(MV.WH.status, "caught", 1, true)))
                        if live then col = Color(90, 255, 120, 255) end
                        names[#names + 1] = {short, col}
                    end
                end
            end

            for _, n in ipairs(names) do
                draw.SimpleTextOutlined(n[1], Font("Bind", bindSize), x, y, n[2], TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, bindOutline, Color(0, 0, 0, 160))
                y = y + bindSize + 1
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- hits: hitmarker (crosshair + where it landed), damage numbers, hit / miss log, and the
-- crosshair indicators (title, movement state, min damage, BAIM ...).
-- player_hurt only says who hurt whom and the health left: the damage is the drop from the
-- health seen before, the hitgroup comes from where the aimbot aimed when it shot (nearest bone
-- to its aim point) or, for your own shots, from a trace along your view.
-- Also MV.EstDamage / MV.MinDamage for the rage bot's minimum damage.
-- A function of its own: the main chunk is at Lua's 200 locals.
-- ---------------------------------------------------------------------------

do
local function Build()
    local H = {
        hp = setmetatable({}, {__mode = "k"}),   -- player -> {cur, old, at}
        marks = {},                               -- crosshair markers {t, kind}
        world = {},                               -- {pos, t, dmg, kind}
        logs = {},                                -- {text, col, t, victim}
        shots = {},                               -- aimbot shots waiting for a hit {ent, t, pos, box, wall}
    }

    -- damage of the default HL2 weapons for the player (GMod's skill values); scripted weapons
    -- say it themselves in SWEP.Primary.Damage
    local WEAPON_DMG = {
        weapon_pistol = 12, weapon_357 = 75, weapon_smg1 = 12, weapon_ar2 = 11,
        weapon_shotgun = 56, weapon_crossbow = 100, weapon_crowbar = 25, weapon_stunstick = 40,
    }

    local GROUP_NAME = {
        [HITGROUP_HEAD] = "head", [HITGROUP_CHEST] = "chest", [HITGROUP_STOMACH] = "stomach",
        [HITGROUP_LEFTARM] = "left arm", [HITGROUP_RIGHTARM] = "right arm",
        [HITGROUP_LEFTLEG] = "left leg", [HITGROUP_RIGHTLEG] = "right leg",
    }

    -- An estimate (the client can't know the server's damage): the weapon's damage (all pellets),
    -- x2 on the head like GMod's base gamemode, less through a wall the more of it there is.
    function MV.EstDamage(ply, hitbox, wallCost)
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then return 0 end

        local base = WEAPON_DMG[wep:GetClass()]
        local pr = wep.Primary
        if istable(pr) and isnumber(pr.Damage) and pr.Damage > 0 then
            base = pr.Damage * ((isnumber(pr.NumShots) and pr.NumShots > 1) and pr.NumShots or 1)
        end

        -- GMod's base gamemode: head x2, arms / legs x0.25, the rest x1
        local mult = hitbox == "head" and 2 or ((hitbox == "arms" or hitbox == "legs") and 0.25 or 1)
        local dmg = (base or 20) * mult
        if wallCost then
            dmg = dmg * math.Clamp(1 - wallCost / math.max(cfg.rage.wallPower, 1) * 0.6, 0.2, 1)
        end
        return dmg
    end

    function MV.MinDamage()
        local r = cfg.rage
        if r.minDmgOverride then return r.minDmgOverrideValue end
        return r.minDamage
    end

    -- head / chest / stomach: the bone nearest to where the aimbot aimed
    local BONES = {
        {"ValveBiped.Bip01_Head1", "head"}, {"ValveBiped.Bip01_Spine2", "chest"}, {"ValveBiped.Bip01_Pelvis", "stomach"},
    }

    local function BoxAt(ent, pos)
        local best, bestD = "body", math.huge
        for _, b in ipairs(BONES) do
            local id = ent:LookupBone(b[1])
            local bp = id and ent:GetBonePosition(id)
            if bp then
                local d = bp:DistToSqr(pos)
                if d < bestD then best, bestD = b[2], d end
            end
        end
        return best
    end

    local function TraceGroup(me, v)
        local tr = util.TraceLine({
            start = me:EyePos(), endpos = me:EyePos() + realAng:Forward() * 32768, filter = me, mask = MASK_SHOT,
        })
        if tr.Entity == v then return GROUP_NAME[tr.HitGroup] or "body", tr.HitPos end
        return "body", nil
    end

    -- A line is kept when either output wants it (screen or console). The console gets it 0.15 s
    -- later (Think below), after the pellets of the same shot have been added into it.
    local function Log(text, col, victim)
        local h = cfg.hits
        if not h.logs and not h.console then return end

        table.insert(H.logs, {text = text, col = col, t = RealTime(), victim = victim})
        if #H.logs > 8 then table.remove(H.logs, 1) end
    end

    AddHook("Think", "hitlogconsole", function()
        if not cfg.hits.console then return end

        local now = RealTime()
        for _, l in ipairs(H.logs) do
            if not l.printed and now - l.t >= 0.15 then
                l.printed = true
                MsgC(Color(cfg.xind.r, cfg.xind.g, cfg.xind.b), "[" .. cfg.xind.name .. "] ", l.col, l.text, "\n")
            end
        end
    end)

    -- a shot went out (tracers / clip watch call NotifyShot): if the aimbot picked the target
    -- this very moment, it waits here for its hit
    function RS.OnShot()
        if not IsValid(aimTargetEnt) or not lastAimPos or CurTime() - lastAimTime > 0.15 then return end

        H.shots[#H.shots + 1] = {
            ent = aimTargetEnt, t = CurTime(), pos = lastAimPos,
            box = BoxAt(aimTargetEnt, lastAimPos), wall = lastAimWall,
        }
        if #H.shots > 16 then table.remove(H.shots, 1) end
    end

    -- health of every player, with the value before the last change (the hurt event and the
    -- new health can arrive in either order)
    AddHook("Think", "hitshp", function()
        local now = CurTime()

        for _, v in ipairs(player.GetAll()) do
            local rec = H.hp[v]
            local hp = v:Health()

            if not rec then
                H.hp[v] = {cur = hp, old = hp, at = 0}
            elseif rec.cur ~= hp then
                rec.old, rec.cur, rec.at = rec.cur, hp, now
            end
        end

        -- aimbot shots that got no hit in time: a miss
        local me = LocalPlayer()
        local wait = 0.35 + (IsValid(me) and me:Ping() / 1000 or 0.1)

        for i = #H.shots, 1, -1 do
            local s = H.shots[i]
            if now - s.t > wait then
                table.remove(H.shots, i)

                if cfg.hits.logMiss and IsValid(s.ent) and s.ent:Alive() then
                    local why = s.wall and "wall" or (cfg.resolver.enabled and "resolver" or "spread")
                    Log(string.format("Missed %s (%s, aimed at the %s)", s.ent:Nick(), why, s.box),
                        Color(255, 120, 120), s.ent)
                end
            end
        end
    end)

    AddHook("player_hurt", "hitlog", function(data)
        local me = LocalPlayer()
        if not IsValid(me) or data.attacker ~= me:UserID() or data.userid == data.attacker then return end

        local v = Player(data.userid)
        if not IsValid(v) then return end

        local left = tonumber(data.health) or v:Health()
        local rec = H.hp[v]
        local before = left
        if rec then
            if rec.cur > left then
                before = rec.cur
            elseif CurTime() - rec.at < 0.5 then
                before = rec.old
            end
        end
        local dmg = math.max(before - left, 0)
        if rec then rec.cur, rec.old, rec.at = left, left, CurTime() end

        -- the aimbot shot this hit belongs to, if any
        local shot
        for i = #H.shots, 1, -1 do
            if H.shots[i].ent == v then
                shot = table.remove(H.shots, i)
                break
            end
        end

        local group, pos
        if shot then
            group, pos = shot.box, shot.pos
        else
            group, pos = TraceGroup(me, v)
        end
        pos = pos or v:WorldSpaceCenter()

        local kill = left <= 0
        local kind = kill and "kill" or (group == "head" and "head" or "hit")
        local now = RealTime()

        H.marks[#H.marks + 1] = {t = now, kind = kind}
        if #H.marks > 4 then table.remove(H.marks, 1) end

        H.world[#H.world + 1] = {pos = pos, t = now, dmg = dmg, kind = kind}
        if #H.world > 24 then table.remove(H.world, 1) end

        local h = cfg.hits
        if h.sound ~= "off" then surface.PlaySound(h.sound) end

        -- pellets of one shot land in the same frame: one line for all of them
        local last = H.logs[#H.logs]
        if last and last.victim == v and now - last.t < 0.1 and last.dmg then
            last.dmg = last.dmg + dmg
            last.text = string.format("%s %s in the %s for %d (%d left)", kill and "Killed" or "Hit", v:Nick(), group, last.dmg, math.max(left, 0))
            return
        end

        Log(string.format("%s %s in the %s for %d (%d left)", kill and "Killed" or "Hit", v:Nick(), group, dmg, math.max(left, 0)),
            kill and Color(255, 90, 90) or Color(235, 235, 235), v)
        if H.logs[#H.logs] then H.logs[#H.logs].dmg = dmg end
    end)

    -- pixel look: small Tahoma with antialiasing off (hard 1 px edges), the 1 px black outline
    -- comes from SimpleTextOutlined; new names so a re-run doesn't keep the old smooth fonts
    surface.CreateFont("NyxHitLogPx2", {font = "Tahoma", size = 11, weight = 700, antialias = false})   -- the indicators' face
    surface.CreateFont("NyxHitNumPx", {font = "Tahoma", size = 13, weight = 800, antialias = false})
    surface.CreateFont("NyxXIndPx", {font = "Tahoma", size = 11, weight = 700, antialias = false})

    local function MarkColor(kind, a)
        local h = cfg.hits
        if kind == "kill" then return Color(255, 70, 70, a) end
        if kind == "head" then return Color(255, 170, 60, a) end
        return Color(h.r, h.g, h.b, a)
    end

    -- an X of four strokes, gap from the centre, pushed out as it fades
    local function DrawX(x, y, gap, len, col)
        draw.NoTexture()
        for i = 0, 3 do
            local deg = 45 + i * 90
            local d = gap + len / 2
            local px = x + math.cos(math.rad(deg)) * d
            local py = y + math.sin(math.rad(deg)) * d

            surface.SetDrawColor(0, 0, 0, col.a * 0.7)
            surface.DrawTexturedRectRotated(px, py, len + 2, 3, -deg)
            surface.SetDrawColor(col)
            surface.DrawTexturedRectRotated(px, py, len, 1.5, -deg)
        end
    end

    AddHook("HUDPaint", "hits", function()
        if IsHidden() then return end

        local h = cfg.hits
        local now = RealTime()
        local cx, cy = ScrW() / 2, ScrH() / 2

        -- crosshair marker
        if h.marker then
            for i = #H.marks, 1, -1 do
                local m = H.marks[i]
                local age = now - m.t
                if age > 0.45 then
                    table.remove(H.marks, i)
                else
                    local a = 255 * (1 - age / 0.45)
                    DrawX(cx, cy, 5 + age * 18, 7, MarkColor(m.kind, a))
                end
            end
        end

        -- where it landed: a small X, the damage rising above it
        for i = #H.world, 1, -1 do
            local w = H.world[i]
            local age = now - w.t

            if age > 1.6 then
                table.remove(H.world, i)
            else
                local a = 255 * math.Clamp(1 - (age - 0.9) / 0.7, 0, 1)

                if h.world and age < 0.8 then
                    local sp = w.pos:ToScreen()
                    if sp.visible then DrawX(sp.x, sp.y, 2, 5, MarkColor(w.kind, 255 * (1 - age / 0.8))) end
                end

                if h.numbers and w.dmg > 0 then
                    local sp = (w.pos + Vector(0, 0, 8 + age * 30)):ToScreen()
                    if sp.visible then
                        draw.SimpleTextOutlined("-" .. w.dmg, "NyxHitNumPx", sp.x, sp.y, MarkColor(w.kind, a),
                            TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, a * 0.8))
                    end
                end
            end
        end

        -- log, top left: the newest at the bottom, each fading out at the end of its time
        if h.logs then
            local y = 8
            local title = Color(cfg.xind.r, cfg.xind.g, cfg.xind.b)

            for i = 1, #H.logs do
                local l = H.logs[i]
                local age = now - l.t
                local a = math.Clamp((h.logTime - age) / 0.5, 0, 1)
                local slide = math.Clamp(age / 0.15, 0, 1)        -- slides in from the left

                if a > 0 then
                    local x = 8 - (1 - slide) * 30
                    surface.SetFont("NyxHitLogPx2")
                    local tag = "[" .. cfg.xind.name .. "] "
                    local tw = surface.GetTextSize(tag)

                    draw.SimpleTextOutlined(tag, "NyxHitLogPx2", x, y, Color(title.r, title.g, title.b, 255 * a * slide),
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200 * a * slide))
                    draw.SimpleTextOutlined(l.text, "NyxHitLogPx2", x + tw, y, Color(l.col.r, l.col.g, l.col.b, 255 * a * slide),
                        TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200 * a * slide))
                    y = y + 12
                end
            end

            for i = #H.logs, 1, -1 do
                if now - H.logs[i].t > h.logTime then table.remove(H.logs, i) end
            end
        end

        -- crosshair indicators
        local xi = cfg.xind
        if not xi.enabled then return end

        local me = LocalPlayer()
        if not IsValid(me) or not me:Alive() then return end

        local outline = Color(0, 0, 0, 200)

        -- minimum damage: small, top right of the crosshair (the override in the accent colour)
        if xi.minDamage and cfg.rage.enabled then
            local md = MV.MinDamage()
            local col = cfg.rage.minDmgOverride and Color(xi.r, xi.g, xi.b) or Color(255, 255, 255)
            draw.SimpleTextOutlined(md > 0 and tostring(md) or "-", "NyxXIndPx", cx + 7, cy - 6, col,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, outline)
        end

        local y = cy + xi.offset

        -- title: a light sweep runs across it
        do
            local name = xi.name
            surface.SetFont("NyxXIndPx")
            local tw = surface.GetTextSize(name)
            local x = cx - tw / 2
            local sweep = (RealTime() * 0.8) % 1.6 - 0.3

            for i = 1, #name do
                local ch = string.sub(name, i, i)
                local cw = surface.GetTextSize(ch)
                local f = math.Clamp(1 - math.abs((i - 0.5) / #name - sweep) * 4, 0, 1)
                local col = Color(Lerp(f, xi.r, 255), Lerp(f, xi.g, 255), Lerp(f, xi.b, 255))

                draw.SimpleTextOutlined(ch, "NyxXIndPx", x, y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, outline)
                x = x + cw
            end

            y = y + 13
        end

        local function Line(text, col)
            draw.SimpleTextOutlined(text, "NyxXIndPx", cx, y, col or Color(235, 235, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, outline)
            y = y + 12
        end

        if xi.state then
            local state
            if not me:IsOnGround() and me:GetMoveType() ~= MOVETYPE_NOCLIP and me:GetMoveType() ~= MOVETYPE_LADDER then
                state = "AIR"
            elseif me:Crouching() then
                state = "CROUCH"
            elseif me:GetVelocity():Length2D() > 5 then
                state = "MOVE"
            else
                state = "STAND"
            end
            Line(state)
        end

        if xi.features then
            local on = Color(xi.r, xi.g, xi.b)
            if cfg.rage.enabled and cfg.rage.forceBaim then Line("BAIM", Color(255, 120, 120)) end
            if cfg.rage.enabled and cfg.rage.minDmgOverride then Line("DMG " .. cfg.rage.minDmgOverrideValue, on) end
            if cfg.aa.enabled then Line("AA", on) end
            if cfg.aa.fakelag then Line("FAKELAG", on) end
            if cfg.move.edgebug then Line("EDGEBUG", MV.plan and Color(90, 255, 120) or on) end
            if cfg.move.airstuck then Line("AIRSTUCK", on) end
        end
    end)
end
Build()
end

-- feature binds are evaluated here, once per frame
AddHook("Think", "binds", function()
    local ply = LocalPlayer()
    local locked = IsValid(menu) or binding ~= nil or gui.IsGameUIVisible()
        or (IsValid(ply) and ply:IsTyping())

    for _, e in ipairs(bindList) do
        if e.mode ~= "always" and e.code then
            local down = IsBindDown(e.code)

            if not locked then
                if e.mode == "hold" then
                    e.tbl[e.key] = down
                elseif e.mode == "release" then
                    e.tbl[e.key] = not down
                elseif down and not e.wasDown then
                    e.tbl[e.key] = not e.tbl[e.key]
                end
            end

            e.wasDown = down
        end
    end
end)

-- ---------------------------------------------------------------------------
-- toggle / unload keys
-- ---------------------------------------------------------------------------

local insertWasDown, findWasDown = false, false

local function Unload()
    for _, h in ipairs(addedHooks) do
        hook.Remove(h[1], h[2])
    end
    addedHooks = {}

    -- ragdolls painted by kill effects go back to normal
    KFX.alive = false
    KFX.Cleanup()            -- ghost models are real client entities

    -- put the original capture functions back
    render.Capture = origCapture
    render.CapturePixels = origCapturePixels
    ssHidden = false

    -- the map's materials back to how they shipped, lighting back to normal
    WorldMaterialsNeutral()
    render.SetLightingMode(0)

    -- network convars, removals (convars, hidden ragdolls), pending killsay line, the killsay
    -- console command
    NET.Restore()
    REM.Restore()
    BAG.SetRate(nil)
    MV.HideShotsRestore()
    MV.mdl.Restore()
    concommand.Remove("nyx_model")

    -- module: no choke / hold left behind, the net channel's own vtable back
    if istable(nyxmod) then
        pcall(nyxmod.SetChoke, 0)
        pcall(nyxmod.SetHold, false, 1)
        pcall(nyxmod.NetUnhook)
    end
    BAG.Log.Restore()
    BAG.Log.CloseWindow()
    concommand.Remove("nyx_net_menu")
    concommand.Remove("nyx_net_replay")
    concommand.Remove("nyx_net_lua")
    concommand.Remove("nyx_net_dump")
    concommand.Remove("nyx_net_clear")
    concommand.Remove("nyx_net_save")
    concommand.Remove("nyx_net_mark")
    concommand.Remove("nyx_net_ignore")
    concommand.Remove("nyx_nwvars")
    concommand.Remove("nyx_dump_lua")
    concommand.Remove("nyx_dump_lua_dir")
    concommand.Remove("nyx_interact_burst")
    timer.Remove(ID .. "killsay")
    concommand.Remove("nyx_killsay")
    concommand.Remove("nyx_bag_class")
    concommand.Remove("nyx_config_save")
    concommand.Remove("nyx_config_load")
    concommand.Remove("nyx_config_list")
    concommand.Remove("nyx_sky_url")
    concommand.Remove("nyx_bg_url")
    concommand.Remove("nyx_bg")
    concommand.Remove("nyx_bg_list")

    ClosePopup()
    if IsValid(menu) then menu:Remove() end

    -- don't leave an injected angle sitting in the engine view
    if silentDirty then
        local ply = LocalPlayer()
        if IsValid(ply) then ply:SetEyeAngles(realAng) end
        silentDirty = false
    end

    NyxUnload = nil
end

NyxUnload = Unload

AddHook("Think", "keys", function()
    local insertDown = input.IsKeyDown(KEY_INSERT)
    if insertDown and not insertWasDown then ToggleMenu() end
    insertWasDown = insertDown

    -- Ctrl+F: the function search (opens the menu first when it is closed)
    local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
    local findDown = ctrl and input.IsKeyDown(KEY_F)

    if findDown and not findWasDown then
        local me = LocalPlayer()
        local typing = IsValid(me) and me:IsTyping()

        if not typing then
            if not IsValid(menu) then
                ToggleMenu()
                if IsValid(menu) then menu.wantSearch = true end
            elseif SEARCH.toggle then
                menu.closing = false
                SEARCH.toggle()
            end
        end
    end

    findWasDown = findDown
end)
