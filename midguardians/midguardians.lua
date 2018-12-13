_addon.name = 'Midguardians'
_addon.author = 'Miaw'
_addon.version = '0.1'
_addon.commands = {'mg'}

res = require('resources')
config = require('config')
packets = require('packets')
json =  require('json')
require("logger")

-- URL to download data from
local url = 'http://www.midguardians.com/gear-overview/loot.json'

-- Mess around to get a proper windows path that can be used in powershell
local outdir = string.gsub(
        string.gsub(windower.addon_path, "/", "\\"),
        "\\\\", "\\"
    ) .. "data"

if not windower.dir_exists(outdir) then
    windower.create_dir(outdir)
end

local data_file = outdir .. "\\mg_data.json"
local complete_file = data_file .. ".downloaded_ok.txt"

local lotters_data = {}
local alliance_names = {}

local download_command = string.format(
    "Invoke-WebRequest -Uri '%s' -OutFile '%s'; " ..
    "if($?) { New-Item -ItemType file '%s' }",
    url, data_file, complete_file
)

local function say(message, color)
    windower.add_to_chat(color or 128, "MG: " .. message);
end

local function load_data()
    local f = assert(io.open(data_file, "rb"))
    local content = f:read("*all")
    f:close()

    local tmpdata = json.decode(content)
    lotters_data = {}
    local count = 0
    for k, v in pairs(tmpdata) do
        lotters_data[k:lower()] = v
        count = count + 1
    end

    -- table.vprint(lotters_data)

    --lotters_data["wind crystal"] = {
    --    Razokoooko=true,
    --    Miaw=true
    --}

    say("Loaded " .. count .. " lottable items.")
end


local function download_data()
    say("Running powershell command to download data from website")

    -- Remove old sync file
    if windower.file_exists(complete_file) then
        os.remove(complete_file)
    end

    -- Run powershell
    windower.execute(
        "powershell.exe",
        {"-WindowStyle", "Hidden", "-Command", download_command}
    )

    -- Check for completion
    local tries = 0;
    local max_wait = 5
    local wait_interval = 0.2
    local max_tries = max_wait / wait_interval

    local function check_done()
        if tries >= max_tries then
            say(" - Download failed!")
            return
        end
        
        if windower.file_exists(complete_file) then
            say(" - Download succeeded!")
            os.remove(complete_file)
            load_data()
            return
        end

        -- Count up number of tries
        tries = tries + 1

        -- Reschedule
        coroutine.schedule(check_done, wait_interval)
    end

    check_done()
end

download_data()

local function update_alliance_names()
    local party_data = windower.ffxi.get_party()
    alliance_names = {}
    for idx1 = 0, 5 do
        if party_data["p" .. idx1] then
            alliance_names[party_data["p" .. idx1].name] = true
        end
        local idx2 = idx1 + 10
        if party_data["a" .. idx2] then
            alliance_names[party_data["a" .. idx2].name] = true
        end
        local idx3 = idx1 + 20
        if party_data["a" .. idx3] then
            alliance_names[party_data["a" .. idx3].name] = true
        end
    end
end

local output_queue = T{}
local output_index = 1
local outputting = false

local function reset_output()
    output_queue= T{}
    output_index = 1
    outputting = false
end

local function process_output()
    local output_str = output_queue[output_index]
    if not output_str then
        reset_output()
        return
    end

    outputting = true
    windower.send_command("input /party " .. output_str)
    output_index = output_index + 1
    if output_queue[output_index] then
        -- Reschedule
        coroutine.schedule(process_output, 1.2)
    else
        reset_output()
    end
end

function start_output()
    if not outputting then
        process_output()
    end
end

function output_result(item_name, lotters)
    local lines = T{}

    table.insert(lines, "~~ Players who can lot for " .. item_name .. " ~~")

    if table.getn(lotters) == 0 then
        table.insert(lines, "  Freelot!")
    else
        local out_str = ""
        for _, name in pairs(lotters) do
            if string.len(out_str) >= 75 then
                table.insert(lines, "  " .. out_str)
                out_str = ""
            end
            out_str = out_str .. name .. ", "
        end
        if out_str ~= "" then
            table.insert(lines, "  " .. out_str:sub(1, -3))
        end
    end

    table.insert(lines, "~~ Done ~~")

    for _, msg in pairs(lines) do
        output_queue:insert(msg)
    end
    start_output()
end

local last_seen = {}

local ingame_names = {
    ["anguelwyvern"]="Anguelwyvern",
    ["Becky"]="Beckydacatlady",
    ["butmunch"]="Butmunch",
    ["NEGAN"]="Negan",
}

windower.register_event('incoming chunk', function(id, data)
    if id == 0x0D2 then
        local treasure = packets.parse('incoming', data)

        if not treasure.Item then
            return
        end

        local item = res.items[treasure.Item]

        if not item then
            return
        end

        local item_name = item.en:lower()
        now = os.time()
        if last_seen[item_name] and (now - last_seen[item_name]) <= 5 then
            return
        end
        last_seen[item_name] = now

        local allowed_lotters = lotters_data[item_name]
        if not allowed_lotters then
            return
        end

        -- Make sure alliance data is up to date
        update_alliance_names()

        local lotters = {}
        for name in pairs(allowed_lotters) do
            if ingame_names[name] then
                name = ingame_names[name]
            end
            if alliance_names[name] then
                table.insert(lotters, name)
            end
        end

        output_result(item_name, lotters)
    end
end)
