SCRIPT_TITLE = "RV Shift Notes & Params"

paramTypeNames = {
  "pitchDelta", "vibratoEnv", "loudness", "tension", "breathiness", "voicing", "gender", "toneShift"
}

local inputForm = {
    title = SV:T("Shift Notes & Params"),
    message = SV:T("Workaround for the \"many notes with params shifting crash\"\nshifts everything between 1st and last note selected"),
    buttons = "OkCancel",
    widgets = {
      {
        name = "cbDirection", type = "ComboBox",
        label = "Direction",
        choices = {"Forward", "Backward"},
        default = 0
      },
      {
        name = "cbUnit", type = "ComboBox",
        label = "Unit",
        choices = {"Measure (at 1st note)", "Quarter", "Time (sec)"},
        default = 0
      },
      {
        name = "tbAmount", type = "TextBox",
        label = "How much to shift",
        default = "1"
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

function process()
  local timeAxis = SV:getProject():getTimeAxis()
  local scope = SV:getMainEditor():getCurrentGroup()
  local group = scope:getTarget()
             -- determine start and end time
  local minTime_b, maxTime_b = math.huge, 0

  local noteCnt = group:getNumNotes()
  if noteCnt == 0 then -- no notes in track
    return
  else
    local selection = SV:getMainEditor():getSelection()
    local selectedNotes = selection:getSelectedNotes()
    if #selectedNotes == 0 then
      SV:showMessageBox(SV:T("Nothing selected"), SV:T("Select notes to shift (only a start and end note is enough)"))
      return
    else
      table.sort(selectedNotes, function(noteA, noteB)
        return noteA:getOnset() < noteB:getOnset()
      end)

      for _, note in ipairs(selectedNotes) do
        local onset_b, nend_b = note:getOnset(), note:getEnd()
        if onset_b < minTime_b then
          minTime_b = onset_b
        end
        if nend_b > maxTime_b then
          maxTime_b = nend_b
        end
      end
    end
  end
  assert(maxTime_b > minTime_b)
          -- list of notes to shift
  local notes = {}
  for i = 1, group:getNumNotes() do
    local note = group:getNote(i)
    local onset_b, nend_b = note:getOnset(), note:getEnd()
    if nend_b > minTime_b and onset_b < maxTime_b then
      table.insert(notes, note)
    end
  end

  inputForm.title = inputForm.title.." ("..#notes.." notes)"
                             -- show dialog
  local dlgResult = SV:showCustomDialog(inputForm)
  local amount = tonumber(dlgResult.answers.tbAmount)
  if not dlgResult.status or amount == 0 then return end -- cancel pressed or no shift

  local direction = 1 - 2 * dlgResult.answers.cbDirection -- 1 forward, -1 backward
  amount = amount * direction

  local timeConvert, shift = false, 0
  local unit = dlgResult.answers.cbUnit
  local shift = 0
  if unit == 0 then
    local measure = timeAxis:getMeasureMarkAtBlick(minTime_b)
    shift = measure.numerator / measure.denominator * 4 * SV.QUARTER * amount -- in blicks
  elseif unit == 1 then
    shift = SV.QUARTER * amount
  else
    timeConvert = true
  end
                      -- do the shift
  for _, note in ipairs(notes) do
    local onset_b = note:getOnset()
    local newOnset_b = onset_b

    if timeConvert then
      local onset = timeAxis:getSecondsFromBlick(onset_b)
      newOnset_b = timeAxis:getBlickFromSeconds(onset + amount)
    else
      newOnset_b = onset_b + shift
    end
    note:setOnset(newOnset_b)
  end
                  -- correction of short pauses and overlap due to rounding
  if timeConvert then
    for _, note in ipairs(notes) do
      local onset_b = note:getOnset()
      local ni = note:getIndexInParent()
      local nextNote = group:getNote(ni + 1)
      if nextNote then
        if math.abs(nextNote:getOnset() - note:getEnd()) <= 1 then
          note:setDuration(nextNote:getOnset() - note:getOnset())
        end
      end
    end
  end

  for _, par in ipairs(paramTypeNames) do
    local am = group:getParameter(par) -- automation track

    local points = am:getPoints(minTime_b, maxTime_b)

    if amount > 0 then
      local endval = am:get(maxTime_b)
      table.insert(points, {maxTime_b, endval})

      if timeConvert then
        local maxTime = timeAxis:getSecondsFromBlick(maxTime_b)
        am:remove(maxTime_b, timeAxis:getBlickFromSeconds(maxTime + amount))
      else
        am:remove(maxTime_b, maxTime_b + shift)
      end
    else
      local startval = am:get(minTime_b)
      table.insert(points, 1, {minTime_b, startval})

      if timeConvert then
        local minTime = timeAxis:getSecondsFromBlick(minTime_b)
        am:remove(minTime_b + timeAxis:getBlickFromSeconds(minTime + amount), minTime_b)
      else
        am:remove(minTime_b + shift, minTime_b)
      end
    end
    am:remove(minTime_b, maxTime_b)

    for _, pt in ipairs(points) do
      if timeConvert then
        local onset = timeAxis:getSecondsFromBlick(pt[1])
        am:add(timeAxis:getBlickFromSeconds(onset + amount), pt[2])
      else
        am:add(pt[1] + shift, pt[2])
      end
    end
  end
end

function main()
  process()
  SV:finish()
end
