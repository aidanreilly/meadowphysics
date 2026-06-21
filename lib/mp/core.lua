--

local function Meadowphysics ()

  local mp = {}

  local create_voice = include("lib/mp/voice")
  local setup_params = include("lib/mp/parameters")
  local ui = include("lib/mp/ui")
  local mp_grid = include("lib/mp/grid")
  local scale = include("lib/mp/scale")
  local MusicUtil = require "musicutil"

  mp.focus = "HOME"
  mp.state = {
    dirty = true,
    grid_keys = {},
    selected_voice = 1
  }
  for i = 1, 8 do
    mp.state.grid_keys[i] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
  end

  mp.midi_out_device = midi.connect(1)
  
  local mp_ui = ui.new(mp)

  local voices = {}
  mp.voices = voices

  -- -------------------------------------------------------------------------
  --  Crow CV + Gate helpers
  -- -------------------------------------------------------------------------

  -- Send a V/oct note and a short gate to a crow voice (I or II).
  -- crow_voice_index:  1 = crow I  (out 1 = CV, out 2 = gate)
  --                    2 = crow II (out 3 = CV, out 4 = gate)
  local function crow_cv_gate(note_num, crow_voice_index, gate_length)
    gate_length = gate_length or 0.1
    local cv_out  = crow_voice_index == 1 and 1 or 3
    local gate_out = crow_voice_index == 1 and 2 or 4
    -- V/oct: middle-C (MIDI 60) = 0 V
    crow.output[cv_out].volts = (note_num - 60) / 12
    crow.output[gate_out].volts = 5
    clock.run(function()
      clock.sleep(gate_length)
      crow.output[gate_out].volts = 0
    end)
  end

  -- Gate-high variant: just raise CV and gate, caller is responsible for low.
  local function crow_cv_gate_high(note_num, crow_voice_index)
    local cv_out   = crow_voice_index == 1 and 1 or 3
    local gate_out = crow_voice_index == 1 and 2 or 4
    crow.output[cv_out].volts  = (note_num - 60) / 12
    crow.output[gate_out].volts = 5
  end

  local function crow_cv_gate_low(crow_voice_index)
    local gate_out = crow_voice_index == 1 and 2 or 4
    crow.output[gate_out].volts = 0
  end

  -- Return which crow voice (1 or 2) a given track should use.
  -- Falls back to 1 if the param isn't set yet.
  local function get_crow_voice(track)
    local ok, v = pcall(function() return params:get(track .. "_crow_voice") end)
    return (ok and v) and v or 1
  end

  -- -------------------------------------------------------------------------

  mp.init = function ()
    mp.voice_count = 8
    setup_params(mp)
    scale:make_params()

    -- -----------------------------------------------------------------------
    -- Extra params: crow voice assignment per track
    -- -----------------------------------------------------------------------
    for i = 1, 8 do
      params:add_option(i .. "_crow_voice", "track " .. i .. " crow voice",
        {"crow I (out 1+2)", "crow II (out 3+4)"}, 1)
    end

    -- set up each voice
    for i=1,mp.voice_count do
      voices[i] = create_voice(i, mp)
      local voice = voices[i]
      voice.on_bang = function ()
        local note_num = scale.notes[mp.voice_count + 1 - i]
        if params:get(i .. "_note") ~= 1 then
          note_num = params:get(i .. "_note") - 1
        end
        local hz = MusicUtil.note_num_to_freq(note_num)
        local out = params:get('output')

        -- trigger type
        if params:get(i .. "_type") == 1 then

          if (out == 1 or out == 3) then
            trigger(note_num, hz, i)
          end
          if (out == 2 or out == 3) then
            trigger_midi_note(i)
          end
          if out == 4 then
            crow.output[util.wrap(i, 1, 4)].volts = 10
            crow.output[util.wrap(i, 1, 4)].volts = 0
          end
          if out == 5 then
            crow.ii.jf.play_note((note_num-60) / 12, 5)
          end
          if out == 6 then
            crow.ii.jf.vtrigger(voice.index, 8)
          end

          -- NEW: crow cv+gate (trigger mode = short gate pulse)
          if out == 7 then
            -- single crow voice (I only)
            crow_cv_gate(note_num, get_crow_voice(i))
          end
          if out == 8 then
            -- both crow voices receive the same note (useful for layering)
            crow_cv_gate(note_num, get_crow_voice(i))
          end
        end

        -- gate type
        if params:get(i .. "_type") == 2 then
          local cv_idx = get_crow_voice(i)

          if voice.gate == 1 then
            if (out == 1 or out == 3) then gate_high(note_num, hz, i) end
            if (out == 2 or out == 3) then toggle_midi_note(i) end
            if out == 7 or out == 8 then
              crow_cv_gate_high(note_num, cv_idx)
            end
          else
            if (out == 1 or out == 3) then gate_low(note_num, hz, i) end
            if (out == 2 or out == 3) then toggle_midi_note(i) end
            if out == 7 or out == 8 then
              crow_cv_gate_low(cv_idx)
            end
          end
        end
      end
    end

    function clock.transport.start()
      print("start transport")
      mp.paused = false
    end

    function clock.transport.stop()
      mp.paused = true
      print('stop transport')
    end

    mp.clock_id = clock.run(mp.clock_loop)
  end

  function get_midi_target(track)
    local channel = 1
    if params:get(track .. "_midi_channel") == 1 then
      channel = params:get("midi_out_channel")
    else
      channel = params:get(track .. "_midi_channel") - 1
    end
    local note = 1
    if params:get(track .. "_note") == 1 then
      note = scale.notes[track]
    else
      note = params:get(track .. "_note") - 1
    end
    return channel, note
  end

  active_midi_notes = {}

  function trigger_midi_note(track)
    local channel, note = get_midi_target(track)
    length = 0.1
    mp.midi_out_device:note_on(note, velocity, channel)
    local note_id = channel .. "_" .. note

    local off = function ()
      mp.midi_out_device:note_off(note, velocity, channel)
      active_midi_notes[note_id] = nil
    end

    active_midi_notes[note_id] = off

    local timeout = function()
      clock.sleep(length)
      off()
    end
    if length ~= nil then
        clock.run(timeout)
    end
  end

  function toggle_midi_note(track)
    local channel, note = get_midi_target(track)
    local note_id = channel .. "_" .. note
    if active_midi_notes[note_id] ~= nil then
      active_midi_notes[note_id]()
    else
      active_midi_notes[note_id] = function ()
        mp.midi_out_device:note_off(note, velocity, channel)
        active_midi_notes[note_id] = nil
      end
      mp.midi_out_device:note_on(note, velocity, channel)
    end
  end

  notes = {}

  function mp.all_notes_off()
    for k,v in pairs(active_midi_notes) do
      active_midi_notes[k]()
    end
    -- also pull all crow gates low on all-notes-off
    local out = params:get('output')
    if out == 7 or out == 8 then
      crow.output[2].volts = 0
      crow.output[4].volts = 0
    end
  end

  mp.clock_loop = function()
    local tick_count = 0
    while true do
      clock.sync(1/(params:get("clock_division")*4))
      mp.handle_tick()
      tick_count = tick_count + 1
      redraw()
      mp_grid:draw(mp)
    end
  end

  function mp:handle_tick()
    if mp.paused then return end
    for i=1,mp.voice_count do
      if voices[i].current_tick == voices[i].current_clock_division and voices[i].current_step == 1 then
        voices[i].bang()
      end
    end
    for i=1,mp.voice_count do
      voices[i].apply_resets()
    end
    for i=1,mp.voice_count do
      voices[i].current_tick = voices[i].current_tick + 1
    end
  end

  function mp:playpause ()
    mp.all_notes_off()
    if mp.paused then 
      mp.paused = false 
    else
      mp.paused = true
    end
  end
  
  function mp:reset () 
    mp.all_notes_off()
    for i=1,mp.voice_count do
      voices[i].reset()
    end
    print "reset"
  end

  function mp:handle_key (n, z)
    if mp.focus == "HOME" then
      if n == 1 and z == 1 then mp.focus = "ALT" end
      if n == 2 and z == 1 then mp.focus = "TIME" end
      if n == 3 and z == 1 then mp.focus = "CONFIG" end
    end
    if mp.focus == "CONFIG" then
      if n == 3 and z == 0 then mp.focus = "HOME" end
    end
    if mp.focus == "TIME" then
      if n == 2 and z == 0 then mp.focus = "HOME" end
    end
    if mp.focus == "ALT" then
      if n == 1 and z == 0 then mp.focus = "HOME" end
      if n == 2 and z == 1 then mp:playpause() end
      if n == 3 and z == 1 then mp:reset() end
    end
    redraw()
    mp_grid:draw(mp)
  end

  function mp:handle_grid_input(x, y, z)
    mp.state.grid_keys[y][x] = z

    if mp.focus == "HOME" then
      if x == 1 and z == 1 then
        mp.state.selected_voice = y
        mp.focus = "RESETS"
      end
      if x > 1 and z == 1 then
        local row_pressed_keys = {}
        for i=2, 16 do
          if mp.state.grid_keys[y][i] == 1 then
            table.insert(row_pressed_keys, i)
          end
        end
        params:set(y .. "_range_low",  row_pressed_keys[1])
        params:set(y .. "_range_high", row_pressed_keys[#row_pressed_keys])
        if #row_pressed_keys == 1 then
          voices[y].current_step = x
          voices[y].current_tick = 0
          voices[y].current_cycle_length = x
          params:set(y .. "_range_high", x)
          params:set(y .. "_range_low",  x)
          params:set(y .. "_running", 2)
          if params:get("trigger_on_press") == 2 then
            voices[y].bang()
          end
        end
      end
    end

    if mp.focus == "RESETS" then
      if x == 2 and z == 1 then mp.focus = "RULES" end
      if x == 1 and z == 0 then mp.focus = "HOME" end
      if z == 1 then
        if x == 3 then mp.voices[y].toggle_playback() end
        if x == 4 then mp.voices[mp.state.selected_voice].toggle_target(y) end
        if x == 6 then mp.voices[y].set_bang_type(1) end
        if x == 7 then mp.voices[y].set_bang_type(2) end
        if x > 8 then
          local pushed_division_keys = {}
          for di=1,8 do
            if (mp.state.grid_keys[y][di+8]) == 1 then
              table.insert(pushed_division_keys, di)
            end
          end
          params:set(y .. "_clock_division_low",  pushed_division_keys[1])
          params:set(y .. "_clock_division_high", pushed_division_keys[#pushed_division_keys])
          mp.voices[y].current_clock_division = pushed_division_keys[1]
        end
      end
    end

    if mp.focus == "RULES" then
      if x == 1 and z == 0 then mp.focus = "HOME" end
      if x == 2 and z == 0 then mp.focus = "RESETS" end
      if z == 1 then
        if x > 8 then
          params:set(mp.state.selected_voice .. "_rule", y)
        end
        if x > 4 and x < 8 then
          params:set(mp.state.selected_voice .. "_rule_target",      y)
          params:set(mp.state.selected_voice .. "_rule_application", x-4)
        end
      end
    end

    redraw()
    mp_grid:draw(mp)
  end

  function mp:draw()
    mp_ui:draw(mp)
  end

  function mp:gridredraw()
    mp_grid:draw(mp)
  end

  return mp

end

return Meadowphysics