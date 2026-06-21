local voice_count = 8

create_voice = function(i, mp)
  -- save you having to always type i .. _ yadda yadda. use getters
  local get = function (param)
    return params:get(i .. "_" .. param)
  end
  local set = function (param, value)
    params:set(i .. "_" .. param, value)
  end

  local bool = {"no", "yes"}
  local rules = {"none", "increment", "decrement", "max", "min", "random", "pole", "stop"}

  params:add_group("voice " .. i, 12 + mp.voice_count)

  local midi_options = {"auto", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
  local note_options = {"auto"}

  for i=1,88 do
    table.insert(note_options, i)
  end

  params:add{
    type = "option",
    id = i .. "_note",
    name = "note",
    options = note_options,
    default = 1
  }

  params:add{
    type = "option",
    id = i .. "_midi_channel",
    name = "midi channel",
    options = midi_options,
    default = 1
  }

  params:add {
    type = "option",
    id = i .. "_running",
    name = "running",
    options = bool,
    default = 1
  }

  params:add{
    type = "number",
    id = i .. "_range_low",
    name = "range low",
    min=1,
    max=16, 
    default = 8,
  }

  params:add{
    type = "number",
    id = i .. "_range_high",
    name = "range high",
    min=1,
    max=16, 
    default = 8,
  }

  params:add{
    type = "number",
    id = i .. "_clock_division_low",
    name = "clock div low",
    min=1,
    max=16, 
    default = 1,
  }
  
  params:add {
    type = "number",
    id = i .. "_clock_division_high",
    name = "clock div high",
    min=1,
    max=16, 
    default = 1,
  }

  params:add {
    type = "option",
    id = i .. "_type",
    name = "type",
    options = {"trigger", "gate"}
  }

  params:add {
    type = "option",
    id = i .. "_crow_voice",
    name = "crow voice",
    options = {"crow I (out 1+2)", "crow II (out 3+4)"},
    default = 1
  }

  params:add {
    type = "option",
    id = i .. "_rule",
    name = "rule",
    options = rules
  }

  params:add {
    type = "option",
    id = i .. "_rule_application",
    name = "rule application",
    options = {"position", "speed", "position+speed"}
  }

  params:add {
    type = "number",
    id = i .. "_rule_target",
    name = "rule target",
    min = 1,
    max = 8,
    default = i
  }

  for reset_i=1, mp.voice_count do
    params:add {
      type = "option",
      id = i .. "_reset_" .. reset_i,
      name = "resets " .. reset_i,
      options = bool
    }
    params:hide(i .. "_reset_" .. reset_i)
  end

  set("reset_" .. i, 2)

  local v = {}
  v.index = i
  v.current_tick = 0
  v.current_step = get("range_low")
  v.current_cycle_length = get("range_low")
  params:set_action(i .. "_range_low", function ()
    v.current_cycle_length = get("range_low")
  end)
  v.current_clock_division = get("clock_division_low")
  v.bang_type = get("type")
  v.gate = 0
  v.get = get
  v.set = set
  v.active_midi_notes = {}

  v.on_bang = function() end

  v.isRunning = function ()
    if get("running") == 2 then
      return true
    else
      return false
    end
  end

  v.apply_resets = function()
    if not v.isRunning() then return end
    -- Reset tick clock and advance step (toward zero) when hitting the clock division
    if (v.current_tick >= v.current_clock_division) then
      v.current_tick = 0
      v.current_step = v.current_step - 1
    end
    if v.current_tick == 0 and v.current_step == 0 then
      set("running", 1)
      for i=1, mp.voice_count do
        local voice = mp.voices[i]
        if get("reset_" .. i) == 2 then
          voice.current_step = voice.current_cycle_length
          voice.set("running", 2)
          voice.current_tick = 0
          voice.apply_rule(rules[voice.get("rule")])
        end
      end
    end
  end

  v.toggle_target = function(voice_index)
    if get("reset_" .. voice_index) == 2 then
      set("reset_" .. voice_index, 1)
    else
      set("reset_" .. voice_index, 2)
    end
  end

  v.toggle_playback = function()
    if (v.isRunning()) then set("running", 1) else set("running", 2) end
  end

  v.set_bang_type = function(bang_type)
    set("type", bang_type)
  end

  v.bang = function()
    set("running", 2)
    if get("type") == 2 then
      if v.gate == 0 then
        v.gate = 1
      else v.gate = 0 
      end
    end
    local bang = {}
    bang.type = v.bang_type
    bang.voice = v.index
    bang.gate = v.gate
    v.on_bang(bang)
  end

  v.reset = function ()
    v.current_step = v.current_cycle_length
    v.current_tick = 1
  end

  local rule_methods = {

    none = function (value, min, max)
      return value
    end,

    increment = function (value, min, max)
      value = value + 1
      if value > max then
        value = min
      end
      return value
    end,

    decrement = function (value, min, max)
      value = value - 1
      if value < min then
        value = max
      end
      return value
    end,

    max = function (value, min, max)
      return max
    end,

    min = function (value, min, max)
      return min
    end,

    random = function (value, min, max)
      value = 1
      local delta = max - min
      if delta > 0 then
        value = min - 1 + math.random(delta+1)
      else
        value = min
      end
      return value
    end,

    pole = function (value, min, max)
      if value == max then
        value = min
      else
        value = max
      end
      return value
    end,

    stop = function (value, min, max)
      v.toggle_playback()
      return max
    end

  }

  v.apply_rule = function(rule)
    local rt = mp.voices[get("rule_target")]
    local ra = get("rule_application")
    local rl = rt.get("range_low")
    local rh = rt.get("range_high")
    local cl = rt.get("clock_division_low")
    local ch = rt.get("clock_division_high")
    local a = {
      {{'current_cycle_length', rl, rh}},
      {{'current_clock_division', cl, ch}},
      {{'current_cycle_length', rl, rh}, {'current_clock_division', cl, ch}}
    }
    for i=1,#a[ra] do
      if rule == "none" then return end
      local property = a[ra][i][1]
      local min = a[ra][i][2]
      local max = a[ra][i][3]
      local value = rule_methods[rule](rt[property], min, max)
      rt[property] = value
    end
  end

  return v
end

return create_voice