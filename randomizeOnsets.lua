SCRIPT_TITLE = "RV Randomize Onsets"

local MIN_NOTE_LENGTH_B = SV:quarter2Blick(1/32)

local inputForm = {
    title = SV:T("Randomize Onsets"),
    message = SV:T("Randomly shifts onsets of selected or all notes in current group"),
    buttons = "OkCancel",
    widgets = {
      {
        name = "sl", type = "Slider",
        label = "Amount of randomness (standard deviation in ms)",
        format = "%3.0f",
        minValue = 0,
        maxValue = 50,
        interval = 1,
        default = 25
      },
      {
        name = "tb", type = "TextBox",
        label = "Random Seed (to have repeatable results)",
        default = "0"
      }
    }
  }

function getClientInfo()
  return {
    name = SV:T(SCRIPT_TITLE),
    author = "Hataori@protonmail.com",
    versionNumber = 1,
    minEditorVersion = 65537
  }
end

local function gaussian(mean, variance)
  return  math.sqrt(-2 * variance * math.log(math.random())) *
          math.cos(2 * math.pi * math.random()) + mean
end

local function randInRange(mean, stdev, range)
  local var = stdev^2
  local x
  repeat
    x = gaussian(mean, var)
  until x >= - range and x <= range
  return x
end

function process()
  local dlgResult = SV:showCustomDialog(inputForm)
  if not dlgResult.status then return end -- cancel pressed

  local stdev = dlgResult.answers.sl
  local seed = tonumber(dlgResult.answers.tb) or 0

  local timeAxis = SV:getProject():getTimeAxis()
  local scope = SV:getMainEditor():getCurrentGroup()
  local group = scope:getTarget()

  math.randomseed(seed)

  local notes = {} -- notes indexes

  local noteCnt = group:getNumNotes()
  if noteCnt == 0 then -- no notes
    return
  else
    local selection = SV:getMainEditor():getSelection()
    local selectedNotes = selection:getSelectedNotes()
    if #selectedNotes == 0 then
      for i = 1, noteCnt do
        table.insert(notes, i)
      end
    else
      table.sort(selectedNotes, function(noteA, noteB)
        return noteA:getOnset() < noteB:getOnset()
      end)

      for _, n in ipairs(selectedNotes) do
        table.insert(notes, n:getIndexInParent())
      end
    end
  end

  for _, i in ipairs(notes) do
    local note = group:getNote(i)

    local onset_b, nend_b = note:getOnset(), note:getEnd()

    local shift = randInRange(0, stdev, stdev) / 1000 -- ms -> sec
    local onset = timeAxis:getSecondsFromBlick(onset_b)
    local new_onset_b = timeAxis:getBlickFromSeconds(onset + shift)
                                               -- positive shift correction
    if new_onset_b > onset_b and (nend_b - new_onset_b) < MIN_NOTE_LENGTH_B then
      new_onset_b = nend_b - MIN_NOTE_LENGTH_B
    end

    local ni = note:getIndexInParent()
    if ni > 1 then -- not first note
      local p_note = group:getNote(ni - 1) -- previous note
      local p_onset_b, p_nend_b = p_note:getOnset(), p_note:getEnd()
                                -- negative shift correction
      if new_onset_b < onset_b and (new_onset_b - p_onset_b) < MIN_NOTE_LENGTH_B then
        new_onset_b = p_onset_b + MIN_NOTE_LENGTH_B
      end

      if math.abs(onset_b - p_nend_b) < MIN_NOTE_LENGTH_B / 4 then -- 2 notes connected, change duration of previous
        p_note:setDuration(new_onset_b - p_onset_b)
      end
    end

    note:setTimeRange(new_onset_b, nend_b - new_onset_b)
  end
end

function main()
  process()
  SV:finish()
end
