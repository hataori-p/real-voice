SCRIPT_TITLE = "RV Quantize Pitch"

function getClientInfo()
  return {
    name = SV:T(SCRIPT_TITLE),
    author = "Hataori@protonmail.com",
    versionNumber = 2,
    minEditorVersion = 65537
  }
end

local NOTES = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B'}

local SCALES = {
  ['chroma'] = 'C-C#-D-D#-E-F-F#-G-G#-A-Bb-B-',
  ['C/a'] = 'C-D-E-F-G-A-B-',
  ['C#/Db/bb'] = 'C#-D#-F-F#-G#-Bb-C-',
  ['D/b'] = 'D-E-F#-G-A-B-C#-',
  ['Eb/c'] = 'D#-F-G-G#-Bb-C-D-',
  ['E/c#'] = 'E-F#-G#-A-B-C#-D#-',
  ['F/d'] = 'F-G-A-Bb-C-D-E-',
  ['F#/Gb/d#/eb'] = 'F#-G#-Bb-B-C#-D#-F-',
  ['G/e'] = 'G-A-B-C-D-E-F#-',
  ['Ab/f'] = 'G#-Bb-C-C#-D#-F-G-',
  ['A/f#'] = 'A-B-C#-D-E-F#-G#-',
  ['Bb/g'] = 'Bb-C-D-D#-F-G-A-',
  ['B/Cb/g#'] = 'B-C#-D#-E-F#-G#-Bb-'
}

local inputForm = {
    title = SV:T("Quantization parameters"),
    message = SV:T("Set tempo before running this script."),
    buttons = "OkCancel",
    widgets = {
      {
        name = "qDiv", type = "ComboBox",
        label = SV:T("Time resolution"),
        choices = {"Quarter", "1/2 Quarter", "1/4 Quarter", "1/8 Quarter", "1/16 Quarter"},
        default = 1
      },
      {
        name = "scale", type = "ComboBox",
        label = SV:T("Scale (Maj/Min)"),
        choices = {"chroma", "C/a", "C#/Db/bb", "D/b", "Eb/c", "E/c#", "F/d", "F#/Gb/d#/eb", "G/e", "Ab/f", "A/f#", "Bb/g", "B/Cb/g#"},
        default = 0
      },
      {
        name = "defLyr", type = "TextBox",
        label = SV:T("Lyrics for all notes"),
        default = "u"
      },
      {
        name = "loadPitchCheck", type = "CheckBox",
        text = SV:T("Load pitch automation"),
        default = false
      }
    }
  }

------------ Praat pitch
local praatPitch = {} -- class

do

local PitchHeader = {
{n="File_type", v="File type = \"ooTextFile\"", t="del"},
{n="Object_class", v="Object class = \"Pitch 1\"", t="del"},
{t="del"},
{n="xmin", t="num"},
{n="xmax", t="num"},
{n="nx", t="num"},
{n="dx", t="num"},
{n="x1", t="num"},
{n="ceiling", t="num"},
{n="maxnCandidates", t="num"}
}

function praatPitch:loadPitch(fnam) -- constructor, short text format
  local o = {}
  setmetatable(o, self)
  self.__index = self

  local data, header = {}, {}

  local fi = io.open(fnam)
  for i = 1, #PitchHeader do
    local lin = fi:read("*l")
    local h = PitchHeader[i]

    if h.v then
      assert(lin == h.v)
    elseif h.t == "num" then
      lin = tonumber(lin)
    end

    if h.n and h.t ~= "del" then
      header[h.n] = lin
    end
  end

  header["fileType"] = "ooTextFile"
  header["objectClass"] = "Pitch 1"
  assert(header.nx)

  for i = 1, header.nx do
    local pitch = { i = i }
    pitch.t = (i - 1) * header.dx + header.x1

    local int = fi:read("*n", "*l") -- intensity
    local cand = fi:read("*n", "*l") -- candidates

    for k = 1, cand do
      local f = fi:read("*n", "*l")
      if k == 1 then
        pitch.f = f
      end
      fi:read("*n", "*l")
    end

    table.insert(data, pitch)
  end;
  fi:close()

  o.header = header
  o.data = data
  return o
end

function praatPitch:getPitch(t) -- ret: f0 [Hz]
  if t < self.data[1].t then return 0 end
  if t > self.data[#self.data].t then return 0 end

  local ll, rr = 1, #self.data
  while (rr-ll) > 1 do
    local cc = math.floor((rr + ll) / 2)
    if t <= self.data[cc].t then
      rr = cc
    else
      ll = cc
    end
  end

  local pf, pt = self.data[ll].f, self.data[rr].f
  if pf == 0 or pt == 0 then return 0 end

  local pf, pt = math.log(pf), math.log(pt)
  local fro, til = self.data[ll].t, self.data[rr].t

  return math.exp(pf + (pt - pf) / (til - fro) * (t - fro))
end

end -- end class

--------- qunatization

function HzToHalftone(hz)
  if hz<=0 then return end
  return 12 * math.log(hz / 440) / math.log(2)
end

-- halftone number from HzToHalftone, 0 = 440 Hz, scale string from SCALES
function isInScale(ht, scale)
  local cbase = math.fmod(ht + 57, 12) -- every C = 0
  local nam = NOTES[cbase + 1]
  return string.find(scale, nam.."-", 1, true)
end

-- quantize to scale
function quantizeNote(hz, scale)
  local ht = HzToHalftone(hz)
  if not ht then return end

  local qht = math.floor(ht + 0.5)
  if isInScale(qht, scale) then return qht end

  local lht, hht = qht - 1, qht + 1
  while not isInScale(lht, scale) do
    lht = lht - 1
  end

  while not isInScale(hht, scale) do
    hht = hht + 1
  end

  if math.abs(ht - lht) < math.abs(ht - hht) then
    return lht
  else
    return hht
  end
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
                                  -- pitch file in project folder
  local projectName, projectDir = getProjectPathName()
  local fileName = projectDir..projectName.."_pitch.txt"

  local fi = io.open(fileName)
  if not fi then
    SV:showMessageBox(SV:T("Error"), SV:T("Cannot open pitch file").." '"..fileName.."'")
    return
  else
    fi:close()
  end

  local dlgResult = SV:showCustomDialog(inputForm)
  if not dlgResult.status then return end -- cancel pressed

  local quarterDivider = 2^dlgResult.answers.qDiv
  local qInterval = SV.QUARTER / quarterDivider

  local scaleName = inputForm.widgets[2].choices[dlgResult.answers.scale + 1]
  local qScale = SCALES[scaleName]
  assert(qScale)

  local pitch = praatPitch:loadPitch(fileName) -- pitch instance
  if not pitch then
    SV:showMessageBox(SV:T("Error"), SV:T("wrong file format"))
    return
  end

  local timeAxis = SV:getProject():getTimeAxis()
  local scope = SV:getMainEditor():getCurrentGroup()
  local group = scope:getTarget()

  local tstart = pitch.header.xmin
  local tend = pitch.header.xmax

  local ints = {}
  local tms = timeAxis:getAllTempoMarks()
  table.insert(tms, {position = timeAxis:getBlickFromSeconds(tend), positionSeconds = tend})
  for tmi = 1, #tms - 1 do
    local tm = tms[tmi]

    local intNum = SV:blickRoundDiv(tms[tmi + 1].position - tm.position, qInterval)

    local b = tm.position
    for i = 1, intNum do
      local tst, ten = timeAxis:getSecondsFromBlick(b), timeAxis:getSecondsFromBlick(b + qInterval)

      local med, cnt, unvoc = {}, 0, 0
      local t = tst
      while t <= ten do
        local f0 = pitch:getPitch(t)
        if f0 > 50 then
          local qn = quantizeNote(f0, qScale)
          table.insert(med, qn)
        else
          unvoc = unvoc + 1
        end

        t = t + 0.001
        cnt = cnt + 1
      end

      if #med > 2 and (#med / cnt) > 0.5 then -- more than 50% voiced length
        table.sort(med)
        med = med[math.floor(#med / 2) + 1]

        table.insert(ints, {st = b, en = b + qInterval, pitch = med + 69})
      else
        table.insert(ints, {st = b, en = b + qInterval})
      end

      b = b + qInterval
    end
  end

  local notes = {}

  local i, j = 1, 1
  while i <= #ints do
    local p0 = ints[i].pitch
    j = i + 1
    while j <= #ints and ints[j].pitch and ints[j].pitch == p0 do
      j = j + 1
    end

    table.insert(notes, {st = ints[i].st, en = ints[j - 1].en, pitch = p0})

    while j <= #ints and not ints[j].pitch do
      j = j + 1
    end

    i = j
  end
                           -- remove old notes
  local ncnt = group:getNumNotes()
  if ncnt > 0 then
    for i = ncnt, 1, -1 do
      group:removeNote(i)
    end
  end
                           -- create notes
  for i, nt in ipairs(notes) do
    local note = SV:create("Note")
    note:setTimeRange(nt.st, nt.en - nt.st)
    note:setPitch(nt.pitch)
    note:setLyrics(dlgResult.answers.defLyr)
    group:addNote(note)
  end
                        -- load pitch automation
  if dlgResult.answers.loadPitchCheck then
    local am = group:getParameter("pitchDelta") -- pitch automation
    am:removeAll()

    scope:setVoice({
      tF0Left = 0,
      tF0Right = 0,
      dF0Left = 0,
      dF0Right = 0,
      dF0Vbr = 0
    })

    local minblicks, maxblicks = math.huge, 0
    for i = 1, group:getNumNotes() do
      local note = group:getNote(i)
      local npitch = note:getPitch()
      local ncents = 100 * (npitch - 69) -- A4

      local blOnset, blEnd = note:getOnset(), note:getEnd()
      am:remove(blOnset, blEnd)

      local tons = timeAxis:getSecondsFromBlick(blOnset) -- start time
      local tend = timeAxis:getSecondsFromBlick(blEnd) -- end time

      local df, f0
      local t = tons + 0.0005
      while t < tend - 0.0001 do
        f0 = pitch:getPitch(t)
        if f0 > 50 then -- voiced
          df = 1200 * math.log(f0/440)/math.log(2) - ncents -- delta f0 in cents
          am:add(timeAxis:getBlickFromSeconds(t), df)
        end
        t = t + 0.001 -- time step
      end

      local tempo = timeAxis:getTempoMarkAt(blOnset)
      local compensation = tempo.bpm * 6.3417442

      if i > 1 then
        local pnote = group:getNote(i - 1)
        local pnpitch = pnote:getPitch()
        local pncents = 100 * (pnpitch - 69) -- A4
        local pblOnset, pblEnd = pnote:getOnset(), pnote:getEnd()
        local ptons = timeAxis:getSecondsFromBlick(pblOnset) -- start time
        local ptend = timeAxis:getSecondsFromBlick(pblEnd) -- end time

        if pblEnd == blOnset then
          local pts = am:getPoints(blOnset, timeAxis:getBlickFromSeconds(tons + 0.010))
          local pdif = ncents - pncents

          for _, pt in ipairs(pts) do
            local b, v = pt[1], pt[2]
            local t = timeAxis:getSecondsFromBlick(b) - tons
            local cor = 1 - (1 / (1 + math.exp(-compensation * t)))
            am:add(b, v + pdif * cor)
          end
        end
      end

      if i < group:getNumNotes() then
        local pnote = group:getNote(i + 1)
        local pnpitch = pnote:getPitch()
        local pncents = 100 * (pnpitch - 69) -- A4
        local pblOnset, pblEnd = pnote:getOnset(), pnote:getEnd()
        local ptons = timeAxis:getSecondsFromBlick(pblOnset) -- start time
        local ptend = timeAxis:getSecondsFromBlick(pblEnd) -- end time

        if blEnd == pblOnset then
          local pts = am:getPoints(timeAxis:getBlickFromSeconds(tend - 0.010), blEnd - 1)
          local pdif = pncents - ncents

          for _, pt in ipairs(pts) do
            local b, v = pt[1], pt[2]
            local t = timeAxis:getSecondsFromBlick(b) - tend
            local cor = 1 / (1 + math.exp(-compensation * t))
            am:add(b, v - pdif * cor)
          end
        end
      end

      am:simplify(blOnset, blEnd, 0.0001)
    end

  end
end

function main()
  process()
  SV:finish()
end
