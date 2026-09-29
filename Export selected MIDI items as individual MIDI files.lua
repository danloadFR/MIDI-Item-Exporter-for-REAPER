--[[
  REAPER - Export selected MIDI items as individual MIDI files

  Features:
  - One .mid file per selected MIDI item
  - The beginning of each item becomes MIDI time 0
  - 960 PPQ
  - Notes only
  - All notes are forced to MIDI channel 1
  - Note velocities are preserved
  - Filename: NN_ItemName.mid
  - NN = number of beats, always 2 digits
  - A native folder browser is used to select the destination folder
  - Requires js_ReaScriptAPI
--]]

local r = reaper

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local PPQ = 960

------------------------------------------------------------
-- Check for js_ReaScriptAPI
------------------------------------------------------------

if not r.JS_Dialog_BrowseForFolder then

    r.ShowMessageBox(
        "This script requires js_ReaScriptAPI.\n\n" ..
        "Please install js_ReaScriptAPI through ReaPack.",
        "MIDI Export",
        0
    )

    return
end

------------------------------------------------------------
-- Write Big Endian integers
------------------------------------------------------------

local function write_u8(f, n)
    f:write(string.char(n & 0xFF))
end

local function write_u16(f, n)
    write_u8(f, (n >> 8) & 0xFF)
    write_u8(f, n & 0xFF)
end

local function write_u32(f, n)
    write_u8(f, (n >> 24) & 0xFF)
    write_u8(f, (n >> 16) & 0xFF)
    write_u8(f, (n >> 8) & 0xFF)
    write_u8(f, n & 0xFF)
end

------------------------------------------------------------
-- MIDI Variable Length Quantity
------------------------------------------------------------

local function vlq_bytes(value)

    value = math.max(0, math.floor(value))

    local buffer = value & 0x7F

    while value > 0x7F do

        value = value >> 7

        buffer =
            (buffer << 8) |
            ((value & 0x7F) | 0x80)
    end

    local bytes = {}

    while true do

        table.insert(
            bytes,
            buffer & 0xFF
        )

        if (buffer & 0x80) == 0 then
            break
        end

        buffer = buffer >> 8
    end

    return bytes
end

------------------------------------------------------------
-- Make a Windows-safe filename
------------------------------------------------------------

local function sanitize_filename(name)

    name = name:gsub(
        '[<>:"/\\|%?%*]',
        '_'
    )

    name = name:gsub(
        '[%c]',
        '_'
    )

    -- Remove trailing spaces and dots
    name = name:gsub(
        '[%. ]+$',
        ''
    )

    if name == "" then
        name = "MIDI_Item"
    end

    return name
end

------------------------------------------------------------
-- Select destination folder
------------------------------------------------------------

local retval, folder =
    r.JS_Dialog_BrowseForFolder(
        "Select MIDI export folder",
        ""
    )

if not retval or folder == "" then
    return
end

folder = folder:gsub("\\", "/")
folder = folder:gsub("/+$", "")

------------------------------------------------------------
-- Check selected items
------------------------------------------------------------

local item_count =
    r.CountSelectedMediaItems(0)

if item_count == 0 then

    r.ShowMessageBox(
        "No MIDI items selected.",
        "MIDI Export",
        0
    )

    return
end

------------------------------------------------------------
-- Create MIDI file
------------------------------------------------------------

local function create_midi_file(
    filepath,
    notes
)

    local f =
        io.open(
            filepath,
            "wb"
        )

    if not f then
        return false
    end

    --------------------------------------------------------
    -- Build MIDI events
    --------------------------------------------------------

    local events = {}

    for _, note in ipairs(notes) do

        -- Note ON - MIDI channel 1
        table.insert(events, {

            pos = note.start,

            order = 1,

            data = {
                0x90,
                note.pitch & 0x7F,
                note.velocity & 0x7F
            }
        })

        -- Note OFF - MIDI channel 1
        table.insert(events, {

            pos = note.stop,

            order = 0,

            data = {
                0x80,
                note.pitch & 0x7F,
                0
            }
        })
    end

    --------------------------------------------------------
    -- Sort events chronologically
    --
    -- When two events have the same position:
    -- Note OFF comes before Note ON
    --------------------------------------------------------

    table.sort(
        events,
        function(a, b)

            if a.pos == b.pos then
                return a.order < b.order
            end

            return a.pos < b.pos
        end
    )

    --------------------------------------------------------
    -- Build MIDI track data
    --------------------------------------------------------

    local track = {}

    local function track_byte(n)

        table.insert(
            track,
            string.char(n & 0xFF)
        )
    end

    local function track_vlq(n)

        local bytes =
            vlq_bytes(n)

        for _, b in ipairs(bytes) do
            track_byte(b)
        end
    end

    local previous_pos = 0

    for _, event in ipairs(events) do

        local delta =
            event.pos - previous_pos

        if delta < 0 then
            delta = 0
        end

        track_vlq(delta)

        for _, b in ipairs(event.data) do
            track_byte(b)
        end

        previous_pos =
            event.pos
    end

    --------------------------------------------------------
    -- End Of Track event
    --------------------------------------------------------

    track_byte(0)
    track_byte(0xFF)
    track_byte(0x2F)
    track_byte(0)

    local track_data =
        table.concat(track)

    --------------------------------------------------------
    -- MIDI Header
    --
    -- Format 0
    -- 1 track
    -- 960 PPQ
    --------------------------------------------------------

    f:write("MThd")

    write_u32(f, 6)

    write_u16(f, 0)
    write_u16(f, 1)
    write_u16(f, PPQ)

    --------------------------------------------------------
    -- MIDI Track
    --------------------------------------------------------

    f:write("MTrk")

    write_u32(
        f,
        #track_data
    )

    f:write(track_data)

    f:close()

    return true
end

------------------------------------------------------------
-- Export selected items
------------------------------------------------------------

local exported = 0
local skipped = 0

r.Undo_BeginBlock()

r.PreventUIRefresh(1)

------------------------------------------------------------
-- Process each selected item
------------------------------------------------------------

for i = 0, item_count - 1 do

    local item =
        r.GetSelectedMediaItem(
            0,
            i
        )

    local take =
        r.GetActiveTake(item)

    --------------------------------------------------------
    -- Process MIDI takes only
    --------------------------------------------------------

    if take and r.TakeIsMIDI(take) then

        ----------------------------------------------------
        -- Item position and length
        ----------------------------------------------------

        local item_pos =
            r.GetMediaItemInfo_Value(
                item,
                "D_POSITION"
            )

        local item_len =
            r.GetMediaItemInfo_Value(
                item,
                "D_LENGTH"
            )

        local item_end =
            item_pos + item_len

        ----------------------------------------------------
        -- Calculate item length in beats
        ----------------------------------------------------

        local start_qn =
            r.TimeMap2_timeToQN(
                0,
                item_pos
            )

        local end_qn =
            r.TimeMap2_timeToQN(
                0,
                item_end
            )

        local beats =
            math.floor(
                (end_qn - start_qn) + 0.5
            )

        ----------------------------------------------------
        -- Get the take name
        --
        -- In REAPER, this is generally the name displayed
        -- for a MIDI item.
        ----------------------------------------------------

        local _, item_name =
            r.GetSetMediaItemTakeInfo_String(
                take,
                "P_NAME",
                "",
                false
            )

        if item_name == "" then
            item_name = "MIDI_Item"
        end

        item_name =
            sanitize_filename(
                item_name
            )

        ----------------------------------------------------
        -- Build filename
        --
        -- Example:
        -- 04_Bass Pattern.mid
        -- 08_Bass Pattern.mid
        -- 16_Bass Pattern.mid
        ----------------------------------------------------

        local filename =
            string.format(
                "%02d_%s.mid",
                beats,
                item_name
            )

        local filepath =
            folder ..
            "/" ..
            filename

        ----------------------------------------------------
        -- Get PPQ positions corresponding to item bounds
        ----------------------------------------------------

        local item_start_ppq =
            r.MIDI_GetPPQPosFromProjTime(
                take,
                item_pos
            )

        local item_end_ppq =
            r.MIDI_GetPPQPosFromProjTime(
                take,
                item_end
            )

        ----------------------------------------------------
        -- Retrieve MIDI notes
        ----------------------------------------------------

        local _, note_count, _, _ =
            r.MIDI_CountEvts(take)

        local notes = {}

        for n = 0, note_count - 1 do

            local ok,
                  selected,
                  muted,
                  startppq,
                  endppq,
                  chan,
                  pitch,
                  velocity =
                r.MIDI_GetNote(
                    take,
                    n
                )

            if ok then

                ------------------------------------------------
                -- Keep notes that overlap the item
                ------------------------------------------------

                if endppq > item_start_ppq
                   and startppq < item_end_ppq then

                    ------------------------------------------------
                    -- Convert positions to item-relative PPQ
                    ------------------------------------------------

                    local rel_start =
                        startppq -
                        item_start_ppq

                    local rel_end =
                        endppq -
                        item_start_ppq

                    ------------------------------------------------
                    -- Clamp notes to item boundaries
                    ------------------------------------------------

                    if rel_start < 0 then
                        rel_start = 0
                    end

                    if rel_end >
                       (item_end_ppq -
                        item_start_ppq) then

                        rel_end =
                            item_end_ppq -
                            item_start_ppq
                    end

                    if rel_end > rel_start then

                        table.insert(
                            notes,
                            {
                                start =
                                    math.floor(
                                        rel_start + 0.5
                                    ),

                                stop =
                                    math.floor(
                                        rel_end + 0.5
                                    ),

                                pitch = pitch,

                                velocity = velocity
                            }
                        )
                    end
                end
            end
        end

        ----------------------------------------------------
        -- Handle duplicate filenames
        ----------------------------------------------------

        local final_path =
            filepath

        local counter = 2

        while io.open(
            final_path,
            "rb"
        ) do

            final_path =
                folder ..
                "/" ..
                string.format(
                    "%02d_%s_%d.mid",
                    beats,
                    item_name,
                    counter
                )

            counter = counter + 1
        end

        ----------------------------------------------------
        -- Create MIDI file
        ----------------------------------------------------

        if create_midi_file(
            final_path,
            notes
        ) then

            exported =
                exported + 1

        else

            skipped =
                skipped + 1
        end

    else

        skipped =
            skipped + 1
    end
end

------------------------------------------------------------
-- Finish
------------------------------------------------------------

r.PreventUIRefresh(-1)

r.Undo_EndBlock(
    "Export selected MIDI items individually",
    -1
)

------------------------------------------------------------
-- Display result
------------------------------------------------------------

local message =
    exported ..
    " MIDI file(s) exported."

if skipped > 0 then

    message =
        message ..
        "\n" ..
        skipped ..
        " item(s) skipped."
end

r.ShowMessageBox(
    message,
    "MIDI Export",
    0
)
