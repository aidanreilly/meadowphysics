setup_params = function(mp)
  params:add_separator()
  -- Voices
  params:add {
    type = "option",
    id = "output",
    name = "output",
    default = 1,
    options = {
      "audio", "midi", "audio + midi",
      "crow 1-4 trigs", "just friends notes", "just friends shapes",
      "crow cv+gate", "crow cv+gate i+ii"
    },
    action = function(value)
      mp.all_notes_off()
      if value == 4 then
        crow.ii.pullup(true)
        crow.output[2].action = "{to(5,0),to(0,0.25)}"
      elseif value == 5 then
        crow.ii.pullup(true)
        crow.ii.jf.mode(1)
      elseif value == 6 then
        crow.ii.pullup(true)
        crow.ii.jf.mode(0)
      elseif value == 7 then
        -- crow I: out 1 = CV, out 2 = gate
        crow.output[1].action = "none"
        crow.output[2].action = "none"
        crow.output[1].volts = 0
        crow.output[2].volts = 0
      elseif value == 8 then
        -- crow I + II: out 1+2 and out 3+4
        crow.output[1].action = "none"
        crow.output[2].action = "none"
        crow.output[3].action = "none"
        crow.output[4].action = "none"
        crow.output[1].volts = 0
        crow.output[2].volts = 0
        crow.output[3].volts = 0
        crow.output[4].volts = 0
      end
    end
  }
  params:add{
    type = "number",
    id = "midi_out_device",
    name = "midi out device",
    min = 1,
    max = 4,
    default = 1,
    action = function(value)
      mp.midi_out_device = midi.connect(value)
    end
  }
  params:add{
    type = "number",
    id = "midi_out_channel",
    name = "midi out channel",
    min = 1, max = 16, default = 1,
    action = function(value)
      mp.midi_out_channel = value
    end
  }
  params:add {
    type = "option",
    id = "clock_division",
    name = "clock division",
    options = {"1/4", "1/8", "1/12", "1/16"}
  }
  params:add {
    type = "option",
    id = "trigger_on_press",
    name = "trigger on press",
    options = {"no", "yes"}
  }
end
return setup_params