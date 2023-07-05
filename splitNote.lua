SCRIPT_TITLE = "RV Split Note"
-- Ver.1 - splits a note at cursor, requantizes the new notes and reloads surrounding pitch devs
-- Ver.2 - refactored pitch dev timing to consume less resources

function getClientInfo()
  return {
    name = SV:T(SCRIPT_TITLE),
    author = "Hataori@protonmail.com",
    category = "Real Voice",
    versionNumber = 2,
    minEditorVersion = 0x010800
  }
end

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
  assert(fi, "cannot open pitch file")
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
  assert(header.nx, "no nx in pitch file")

  for i = 1, header.nx do
    local pitch = { i = i }
    pitch.t = (i - 1) * header.dx + header.x1

    local int = fi:read("*n", "*l") -- intensity
    local cand = fi:read("*n", "*l") -- candidates
    assert(cand, "no candidates in pitch file")

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

local function HzToHalftone(hz)
  if hz<=0 then return end
  return 12 * math.log(hz / 440) / math.log(2)
end

local function medianNotePitch(noteStart, noteEnd, pitch) -- times in secs
  local med, cnt, unvoc = {}, 0, 0
  local t = noteStart
  while t <= noteEnd do
    local f0 = pitch:getPitch(t)
    if f0 > 0 then
      local qn = math.floor(HzToHalftone(f0) + 0.5)
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
    return med + 69
  end
end

--------- project

local function getProjectPathName()
  local projectFileName = SV:getProject():getFileName()
  if not projectFileName then return end

  local projectName, projectDir
  projectFileName = projectFileName:gsub("\\", "/")
  projectDir, projectName = projectFileName:match("^(.*/)([^/]+)%.svp$")
  return projectName, projectDir
end

---------- main

function process()
  local sver = SV:getHostInfo().hostVersionNumber -- SynthV version
                                  -- pitch file in project folder
  local projectName, projectDir = getProjectPathName()
  if not projectDir or not projectName then
    SV:showMessageBox(SV:T("Error"), SV:T("Project dir or name not found, save your project first"))
    return
  end
  local fileName = projectDir..projectName.."_Pitch.txt"

  local fi = io.open(fileName)
  if not fi then
    SV:showMessageBox(SV:T("Error"), SV:T("Cannot open pitch file").." '"..fileName.."'")
    return
  else
    fi:close()
  end

  local pitch = praatPitch:loadPitch(fileName) -- pitch instance
  if not pitch then
    SV:showMessageBox(SV:T("Error"), SV:T("Wrong pitch file format, save it as SHORT text"))
    return
  end

  local timeAxis = SV:getProject():getTimeAxis()
  local scope = SV:getMainEditor():getCurrentGroup()
  local group = scope:getTarget()
  local playback = SV:getPlayback()
  local am = group:getParameter("pitchDelta") -- pitch automation

  local ph = playback:getPlayhead() -- in secs
  local phb = timeAxis:getBlickFromSeconds(ph)
                       -- find note index
  local ni
  for i = 1, group:getNumNotes() do
    local note = group:getNote(i)
    if phb >= note:getOnset() and phb < note:getEnd() then
      ni = i
      break
    end
  end
                  -- note not under playhead cursor
  if not ni then return end

  local noteL = group:getNote(ni)
  local nLpitch = medianNotePitch(timeAxis:getSecondsFromBlick(noteL:getOnset()), ph, pitch)
  local nRpitch = medianNotePitch(ph, timeAxis:getSecondsFromBlick(noteL:getEnd()), pitch)

  local notes = {} -- notes indexes for pitch reload
  local noteCnt = group:getNumNotes()

  if nLpitch and not nRpitch then
    noteL:setPitch(nLpitch)
    noteL:setDuration(phb - noteL:getOnset())

    local ifr, ito = ni - 1, ni + 1
    if ifr < 1 then ifr = 1 end
    if ito > noteCnt then ito = noteCnt end

    for i = ifr, ito do
      table.insert(notes, i)
    end
    return
  elseif not nLpitch and nRpitch then
    noteL:setPitch(nRpitch)
    noteL:setTimeRange(phb, noteL:getEnd() - phb)

    local ifr, ito = ni - 1, ni + 1
    if ifr < 1 then ifr = 1 end
    if ito > noteCnt then ito = noteCnt end

    for i = ifr, ito do
      table.insert(notes, i)
    end
    return
  elseif nLpitch and nRpitch then
    local noteR = SV:create("Note")
    noteR:setTimeRange(phb, noteL:getEnd() - phb)
    if sver >= 0x010900 then
      noteR:setPitchAutoMode(0) -- manual pitch mode
    end
    noteR:setPitch(nRpitch)
    noteR:setLyrics("-")
    group:addNote(noteR)

    noteL:setPitch(nLpitch)
    noteL:setDuration(phb - noteL:getOnset())

    local ifr, ito = ni - 1, ni + 2
    if ifr < 1 then ifr = 1 end
    if ito > noteCnt then ito = noteCnt end

    for i = ifr, ito do
      table.insert(notes, i)
    end
  end
                  -- reload pitch
  for _, i in ipairs(notes) do
    local note = group:getNote(i)
    local npitch = note:getPitch()
    local ncents = 100 * (npitch - 69) -- A4

    local blOnset, blEnd = note:getOnset(), note:getEnd()
    am:remove(blOnset, blEnd)

    local tons = timeAxis:getSecondsFromBlick(blOnset) -- start time
    local tend = timeAxis:getSecondsFromBlick(blEnd) -- end time

    local tempo = timeAxis:getTempoMarkAt(blOnset)
    local compensation = tempo.bpm * 6.3417442
    local t_step = math.max(SV:blick2Seconds(SV:quarter2Blick(1/64), tempo.bpm), 0.01)

    local df, f0
    local o10, e10 = tons + 0.010, tend - 0.010
    local t = tons + 0.0005
    while t < tend - 0.0001 do
      f0 = pitch:getPitch(t)
      if f0 > 50 then -- voiced
        df = 1200 * math.log(f0/440)/math.log(2) - ncents -- delta f0 in cents
        am:add(timeAxis:getBlickFromSeconds(t), df)
      end

      if t <= o10 or t >= e10 then
        t = t + 0.001
      else
        t = t + t_step -- time step
        if t >= e10 then
          t = e10
        end
      end
    end

    if i > 1 then
      local pnote = group:getNote(i - 1)
      local pnpitch = pnote:getPitch()
      local pncents = 100 * (pnpitch - 69) -- A4
      local pblOnset, pblEnd = pnote:getOnset(), pnote:getEnd()

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

    if i < noteCnt then
      local pnote = group:getNote(i + 1)
      local pnpitch = pnote:getPitch()
      local pncents = 100 * (pnpitch - 69) -- A4
      local pblOnset, pblEnd = pnote:getOnset(), pnote:getEnd()

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

function main()
  process()
  SV:finish()
end
