SCRIPT_TITLE = "RV Growl"

local inputForm = {
  title = SV:T("Growl"),
  message = SV:T(""),
  buttons = "OkCancel",
  widgets = {
    {
      name = "slFreq", type = "Slider",
      label = "Base frequency of the modualtor (Hz)",
      format = "%3.0f",
      minValue = 10,
      maxValue = 200,
      interval = 1,
      default = 50
    },
    {
      name = "chkVibr", type = "CheckBox",
      text = SV:T("Vibrato mode - divide base frequency by 10"),
      default = false
    },
    {
      name = "slPitch", type = "Slider",
      label = "Modulation depth for Pitch (smt)",
      format = "%5.2f",
      minValue = 0,
      maxValue = 2.0,
      interval = 0.01,
      default = 0
    },
    {
      name = "slLoud", type = "Slider",
      label = "Modulation depth for Loudness (dB)",
      format = "%3.0f",
      minValue = 0,
      maxValue = 12,
      interval = 1,
      default = 0
    },
    {
      name = "slTens", type = "Slider",
      label = "Modulation depth for Tension",
      format = "%5.2f",
      minValue = 0,
      maxValue = 1.0,
      interval = 0.01,
      default = 0.0
    },
    {
      name = "slGend", type = "Slider",
      label = "Modulation depth for Gender",
      format = "%5.2f",
      minValue = 0,
      maxValue = 1.0,
      interval = 0.01,
      default = 0.0
    },
    {
      name = "slRand", type = "Slider",
      label = "Random phase modulation",
      format = "%5.2f",
      minValue = 0,
      maxValue = 1.0,
      interval = 0.01,
      default = 0.0
    },
    {
      name = "chkEnv", type = "CheckBox",
      text = SV:T("Use \"Vibrato Envelope\" for additional depth modulation"),
      default = false
    },
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

function main()
  process()
  SV:finish()
end

local function getProjectPathName()
  local projectFileName = SV:getProject():getFileName()
  if not projectFileName then return end

  local projectName, projectDir
  projectFileName = projectFileName:gsub("\\", "/")
  projectDir, projectName = projectFileName:match("^(.*/)([^/]+)%.svp$")
  if not projectDir or not projectName then error(SV:T("project dir or name not found")) end

  return projectName, projectDir
end

function process()
  local projectName, projectDir = getProjectPathName()
  local configFileName = projectDir.."RTgrowl.txt"
            -- read config
  do
    local fi = io.open(configFileName)
    if fi then
      local txt = fi:read("*a")
      fi:close()

      local conf = assert(load("return"..txt))()
      assert(conf, SV:T("config format error"))
      if type(conf) ~= "table" then
        error(SV:T("config format error"))
      end
              -- dialog defaults from config
      local wg = inputForm.widgets
      wg[1].default = conf.baseFrequency or 50
      if conf.vibratoMode and conf.vibratoMode > 0 then
        wg[2].default = true
      else
        wg[2].default = false
      end
      wg[3].default = conf.pitchDepth or 0
      wg[4].default = conf.loudnessDepth or 0
      wg[5].default = conf.tensionDepth or 0.0
      wg[6].default = conf.genderDepth or 0.0
      wg[7].default = conf.randomPhase or 0.0
      if conf.useEnvelope and conf.useEnvelope > 0 then
        wg[8].default = true
      else
        wg[8].default = false
      end
    end
  end
           -- input dialog
  local dlgResult = SV:showCustomDialog(inputForm)
  if not dlgResult.status then return end -- cancel pressed

  local slFreq = dlgResult.answers.slFreq
  local chkVibr = dlgResult.answers.chkVibr
  local slPitch = dlgResult.answers.slPitch
  local slLoud = dlgResult.answers.slLoud
  local slTens = dlgResult.answers.slTens
  local slGend = dlgResult.answers.slGend
  local slRand = dlgResult.answers.slRand
  local chkEnv = dlgResult.answers.chkEnv
              -- save configuration
  do
    local fo = io.open(configFileName, "w")
    fo:write("{\n")
    fo:write("baseFrequency="..slFreq..",\n")
    if chkVibr then
      fo:write("vibratoMode=1,\n")
    else
      fo:write("vibratoMode=0,\n")
    end
    fo:write("pitchDepth="..slPitch..",\n")
    fo:write("loudnessDepth="..slLoud..",\n")
    fo:write("tensionDepth="..slTens..",\n")
    fo:write("genderDepth="..slGend..",\n")
    fo:write("randomPhase="..slRand..",\n")
    if chkEnv then
      fo:write("useEnvelope=1,\n")
    else
      fo:write("useEnvelope=0,\n")
    end
    fo:write("}\n")
    fo:close()
  end
           -- vibrato mode
  if chkVibr then slFreq = slFreq / 10 end
                 -- SV automations
  local project = SV:getProject()
  local timeAxis = project:getTimeAxis()
  local scope = SV:getMainEditor():getCurrentGroup()
  local group = scope:getTarget()
  local amenv = group:getParameter("vibratoEnv") -- modulation envelope
  local ampt = group:getParameter("pitchDelta")
  local amld = group:getParameter("loudness")
  local amts = group:getParameter("tension")
  local amgen = group:getParameter("gender")
                   -- find associated track by name
  local ctName = SV:getMainEditor():getCurrentTrack():getName()
  local amenv2
  for i = 1, project:getNumTracks() do
    local tr = project:getTrack(i)
    if tr:getName() == ctName.."-growl" then
      amenv2 = tr:getGroupReference(1):getTarget():getParameter("vibratoEnv")
      break
    end
  end
          -- selected notes list
  local notes = {} -- notes indexes

  local noteCnt = group:getNumNotes()
  if noteCnt == 0 then -- no notes
    return
  else
    local selection = SV:getMainEditor():getSelection()
    local selectedNotes = selection:getSelectedNotes()
    if #selectedNotes == 0 then
      SV:showMessageBox("Error", SV:T("Nothing selected"))
      return
    else
      table.sort(selectedNotes, function(noteA, noteB)
        return noteA:getOnset() < noteB:getOnset()
      end)

      for _, n in ipairs(selectedNotes) do
        table.insert(notes, n:getIndexInParent())
      end
    end
  end

  local firststart
  for _, i in ipairs(notes) do
    local note = group:getNote(i)

    local blOnset, blEnd = note:getOnset(), note:getEnd()
    local tons = timeAxis:getSecondsFromBlick(blOnset) -- start time
    local tend = timeAxis:getSecondsFromBlick(blEnd) -- end time
    if not firststart then firststart = tons end

    local lastpointPitch = ampt:get(blEnd + 1)
    local lastpointLoud = amld:get(blEnd + 1)
    local lastpointTens = amts:get(blEnd + 1)
    local lastpointGend = amgen:get(blEnd + 1)

    local result = {}

    local t = tons
    while t < tend do
      local tbl = timeAxis:getBlickFromSeconds(t)
      local t0 = t - firststart
                    -- frequency envelope
      local fenv = 1.0
      if amenv2 then
        fenv = amenv2:get(tbl)
      end

      local sn = math.sin(2 * math.pi * (fenv * slFreq + 1) * t0 + 2 * math.pi * slRand * math.random()) -- sin wave generator
                               -- modulation envelope (0 - 1) from "Vibrato Envelope" automation
      local env = 1.0
      if chkEnv then
        env = amenv:get(tbl) - 1.0
        if env < 0 then env = 0 end
      end

      local res = { tbl = tbl }
                          -- pitch modulation
      res.df = env * sn * 100 * slPitch + ampt:get(tbl)
                          -- loudness modulation
      res.ld = env * sn * slLoud + amld:get(tbl)
                          -- tension modulation
      res.ten = env * sn * slTens + amts:get(tbl)
                          -- gender modulation
      res.gen = env * sn * slGend + amgen:get(tbl)

      table.insert(result, res)

      t = t + 0.001 -- time step
    end
              -- remove all previous points
    if slPitch > 0 then
      ampt:remove(blOnset, blEnd)
    end
    if slLoud > 0 then
      amld:remove(blOnset, blEnd)
    end
    if slTens > 0 then
      amts:remove(blOnset, blEnd)
    end
    if slGend > 0 then
      amgen:remove(blOnset, blEnd)
    end
             -- add new points
    for _, res in ipairs(result) do
      if slPitch > 0 then
        ampt:add(res.tbl, res.df)
      end
      if slLoud > 0 then
        amld:add(res.tbl, res.ld)
      end
      if slTens > 0 then
        amts:add(res.tbl, res.ten)
      end
      if slGend > 0 then
        amgen:add(res.tbl, res.gen)
      end
    end
             -- simplify
    if slPitch > 0 then
      ampt:simplify(blOnset, blEnd, 0.00001)
    end
    if slLoud > 0 then
      amld:simplify(blOnset, blEnd, 0.00001)
    end
    if slTens > 0 then
      amts:simplify(blOnset, blEnd, 0.00001)
    end
    if slGend > 0 then
      amgen:simplify(blOnset, blEnd, 0.00001)
    end
            -- restore curve after note
    ampt:add(blEnd + 1, lastpointPitch)
    amld:add(blEnd + 1, lastpointLoud)
    amts:add(blEnd + 1, lastpointTens)
    amgen:add(blEnd + 1, lastpointGend)
  end
end
