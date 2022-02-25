SCRIPT_TITLE = "RV Load Envelope"

function getClientInfo()
  return {
    name = SV:T(SCRIPT_TITLE),
    author = "Hataori@protonmail.com",
    versionNumber = 1,
    minEditorVersion = 65537
  }
end

function main()
  loadEnvelope()
  SV:finish()
end

------------ Pitch
local praatPitch = {} -- class

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

----------------- Intensity
local praatIntensity = {} -- class

local IntensityHeader = {
{n="File_type", v="File type = \"ooTextFile\"", t="del"},
{n="Object_class", v="Object class = \"Intensity 2\"", t="del"},
{t="del"},
{n="xmin", t="num"},
{n="xmax", t="num"},
{n="nx", t="num"},
{n="dx", t="num"},
{n="x1", t="num"},
{n="ymin", t="num"},
{n="ymax", t="num"},
{n="ny", t="num"},
{n="dy", t="num"},
{n="y1", t="num"}
}

function praatIntensity:loadIntensity(fnam) -- constructor, short text format
  local o = {}
  setmetatable(o, self)
  self.__index = self

  local data, header = {}, {}

  local fi = io.open(fnam)
  for i = 1, #IntensityHeader do
    local lin = fi:read("*l")
    local h = IntensityHeader[i]

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
  header["objectClass"] = "Intensity 2"
  assert(header.nx)

  for i = 1, header.nx do
    local int = { i = i }
    int.t = (i - 1) * header.dx + header.x1

    local ii = fi:read("*n", "*l") -- intensity
    int.db = ii
    table.insert(data, int)
  end;
  fi:close()

  o.header = header
  o.data = data
  return o
end

function praatIntensity:getIntensity(t) -- ret: I [dB]
  if t < self.data[1].t then return -100 end
  if t > self.data[#self.data].t then return -100 end

  local ll, rr = 1, #self.data
  while (rr-ll) > 1 do
    local cc = math.floor((rr + ll) / 2)
    if t <= self.data[cc].t then
      rr = cc
    else
      ll = cc
    end
  end

  local intf, intt = self.data[ll].db, self.data[rr].db
  if not intf or not intt then return -100 end

  local fro, til = self.data[ll].t, self.data[rr].t

  return intf + (intt - intf) / (til - fro) * (t - fro)
end
--------------- end praat

local function getProjectPathName()
  local projectFileName = SV:getProject():getFileName()
  if not projectFileName then return end

  local projectName, projectDir
  projectFileName = projectFileName:gsub("\\", "/")
  projectDir, projectName = projectFileName:match("^(.*/)([^/]+)%.svp$")
  if not projectDir or not projectName then error(T("project dir or name not found")) end

  return projectName, projectDir
end

function loadEnvelope()
                                  -- pitch file in project folder
  local projectName, projectDir = getProjectPathName()

  local pitch = praatPitch:loadPitch(projectDir..projectName.."_pitch.txt")
  local intens = praatIntensity:loadIntensity(projectDir..projectName.."_intensity.txt")

  local timeAxis = SV:getProject():getTimeAxis()
  local scope = SV:getMainEditor():getCurrentGroup()
  local group = scope:getTarget()
  local am = group:getParameter("vibratoEnv")

  local t = intens.header.xmin
  local tend = intens.header.xmax

  while t <= tend do
    local int = intens:getIntensity(t) or -300
    local env = math.sqrt(10^(int/10)*4e-10)*3

    local f0 = pitch:getPitch(t)
    if f0 < 50 then env = - env*5 end
    am:add(timeAxis:getBlickFromSeconds(t), env+1)
    t = t + 0.001 -- time step
  end

  am:simplify(timeAxis:getBlickFromSeconds(intens.header.xmin), timeAxis:getBlickFromSeconds(intens.header.xmax), 0.00005)
end
