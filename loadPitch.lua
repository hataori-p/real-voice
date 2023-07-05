SCRIPT_TITLE = "RV Load Pitch"
-- Ver.1 - loads pitch from Pratt pitch object into pitch deviation automation track
-- Ver.2 - minor changes
-- Ver.3 - refactored pitch dev timing to consume less resources

function getClientInfo()
  return {
    name = SV:T(SCRIPT_TITLE),
    author = "Hataori@protonmail.com",
    category = "Real Voice",
    versionNumber = 3,
    minEditorVersion = 0x010600
  }
end

function main()
  loadPraatPitch()
  SV:finish()
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

end -- end praat class

local function getProjectPathName()
  local projectFileName = SV:getProject():getFileName()
  if not projectFileName then return end

  local projectName, projectDir
  projectFileName = projectFileName:gsub("\\", "/")
  projectDir, projectName = projectFileName:match("^(.*/)([^/]+)%.svp$")
  return projectName, projectDir
end

function loadPraatPitch()
                                  -- pitch file in project folder
  local projectName, projectDir = getProjectPathName()
  if not projectDir or not projectName then
    SV:showMessageBox(SV:T("Error"), SV:T("Project dir or name not found, save your project first"))
    return
  end
  local fileName = projectDir..projectName.."_Pitch.txt"

  local pitch = praatPitch:loadPitch(fileName)
  if not pitch then
    SV:showMessageBox(SV:T("Error"), SV:T("Wrong pitch file format, save it as SHORT text"))
    return
  end

  local timeAxis = SV:getProject():getTimeAxis()
  local scope = SV:getMainEditor():getCurrentGroup()
  local group = scope:getTarget()
  local am = group:getParameter("pitchDelta") -- pitch automation

  scope:setVoice({
        tF0Left = 0,
        tF0Right = 0,
        dF0Left = 0,
        dF0Right = 0,
        dF0Vbr = 0
  })

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
