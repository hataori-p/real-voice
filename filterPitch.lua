SCRIPT_TITLE = "RV Filter Pitch"

function getClientInfo()
  return {
    name = SV:T(SCRIPT_TITLE),
    author = "hataori@protonmail.com",
    category = "Real Voice",
    versionNumber = 2,
    minEditorVersion = 65537
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

function praatPitch:pitchFromArray(arr, dx, x1, ceiling) -- constructor, short text format, 1 candidate
  assert(type(arr) == "table" and #arr > 0)
  assert(dx and dx > 0)
  x1 = x1 or 0
  ceiling = ceiling or 1000

  local o = {}
  setmetatable(o, self)
  self.__index = self

  local data, header = {}, {}

  header["fileType"] = "ooTextFile"
  header["objectClass"] = "Pitch 1"
  header["maxnCandidates"] = 1
  header["dx"] = dx
  header["x1"] = x1
  header["ceiling"] = ceiling
  header["nx"] = #arr
  header["xmin"] = 0
  header["xmax"] = (header.nx - 1) * header.dx + header.x1

  for i = 1, header.nx do
    local pitch = { i = i }
    pitch.t = (i - 1) * header.dx + header.x1
    pitch.f = arr[i]

    table.insert(data, pitch)
  end;

  o.header = header
  o.data = data
  return o
end

function praatPitch:savePitch(fnam) -- short text format
  local data, header = self.data, self.header
  assert(#data == header.nx)
  local fi = io.open(fnam, "w")

  fi:write('File type = "ooTextFile"\n')
  fi:write('Object class = "Pitch 1"\n')
  fi:write("\n")
  fi:write(header.xmin.."\n")
  fi:write(header.xmax.."\n")
  fi:write(header.nx.."\n")
  fi:write(header.dx.."\n")
  fi:write(header.x1.."\n")
  fi:write(header.ceiling.."\n")
  fi:write(header.maxnCandidates.."\n")

  for _, pitch in ipairs(data) do
    fi:write("1.0\n") -- intensity
    fi:write("1\n") -- candidates

    local f = pitch.f
    if f < 20 then f = 0 end

    fi:write(f.."\n")
    if pitch.f == 0 then
      fi:write("0\n")
    else
      fi:write("1.0\n")
    end
  end;
  fi:close()
end

end -- end of pitch class
                              -- filter response
local response = {
-0.000000635231500975,0.000000000000000000,0.000000807065703388,0.000001770470789187,0.000002862668796963,0.000004043973129273,0.000005263135141289,0.000006458630332991,
0.000007560660763757,0.000008493844917658,0.000009180527453478,0.000009544602392788,0.000009515706298425,0.000009033604903976,0.000008052569468787,0.000006545519715146,
0.000004507700180840,0.000001959657484146,-0.000001050701779940,-0.000004447168638887,-0.000008125565053328,-0.000011955466249406,-0.000015783368833145,-0.000019437297175434,
-0.000022732771004509,-0.000025479985195950,-0.000027491981631430,-0.000028593526140439,-0.000028630344442158,-0.000027478323070216,-0.000025052247632035,-0.000021313634706140,
-0.000016277212946222,-0.000010015639561057,-0.000002662072919579,0.000005589704583729,0.000014487840869020,0.000023727768724614,0.000032960369199691,0.000041802827672183,
0.000049851936900116,0.000056699472558167,0.000061949144497833,0.000065234517196924,0.000066237201397718,0.000064704551186687,0.000060466061486024,0.000053447653924649,
0.000043683066991812,0.000031321630553238,0.000016631805028841,0.000000000000000000,-0.000018075647679758,-0.000036996665044174,-0.000056080721670673,-0.000074582891849405,
-0.000091721171156943,-0.000106705499752311,-0.000118769342494394,-0.000127202699866900,-0.000131385282959422,-0.000130818488750848,-0.000125154765709458,-0.000114222969587942,
-0.000098048378534171,-0.000076866166233212,-0.000051127320223890,-0.000021496235694864,0.000011160493702040,0.000045794236278740,0.000081203224357188,0.000116069615914566,
0.000149003761450155,0.000178594364830361,0.000203462901228582,0.000222320376246073,0.000234024292246158,0.000237633543550586,0.000232458901829789,0.000218106784302957,
0.000194514124447651,0.000161972388301211,0.000121139095688357,0.000073035607395202,0.000019030415069590,-0.000039192294572717,-0.000099678454109958,-0.000160263365906606,
-0.000218642854177836,-0.000272454219241792,-0.000319364381367093,-0.000357162163602133,-0.000383851321951806,-0.000397740706324425,-0.000397527842231268,-0.000382372272237852,
-0.000351955193447266,-0.000306522273000218,-0.000246907011915500,-0.000174532646759526,-0.000091391310963566,0.000000000000000001,0.000096666230806742,0.000195262492127315,
0.000292181455766413,0.000383676794573937,0.000465998749419760,0.000535537224540372,0.000588967276351427,0.000623391497831982,0.000636473633847676,0.000626557808704293,
0.000592768014645742,0.000535082999477404,0.000454382394847245,0.000352460826998179,0.000232007823519517,0.000096552539339326,-0.000049626367513300,-0.000201624021141629,
-0.000354062724990313,-0.000501271113883708,-0.000637483500467720,-0.000757052808771862,-0.000854669645050693,-0.000925579459950539,-0.000965789440893040,-0.000972256764571389,
-0.000943050151111631,-0.000877477296511540,-0.000776171708820553,-0.000641133714020658,-0.000475721895343966,-0.000284592939029649,-0.000073589724346871,0.000150420548268818,
0.000379754420565795,0.000606160738351136,0.000821102226032318,0.001016060998716548,0.001182857620521191,0.001313972336440665,0.001402856510521515,0.001444222134474215,
0.001434297552915503,0.001371038292830095,0.001254283077148637,0.001085846719713366,0.000869543598347635,0.000611137725055624,0.000318218003737925,-0.000000000000000001,
-0.000332941651196247,-0.000669003308377554,-0.000995935339632639,-0.001301266193323235,-0.001572753586790662,-0.001798847271705102,-0.001969146740776351,-0.002074836718825078,
-0.002109083374209074,-0.002067374915592883,-0.001947791602506744,-0.001751192170912955,-0.001481306208374410,-0.001144725036065497,-0.000750787074629070,-0.000311357377446786,
0.000159495116815019,0.000645915166232399,0.001130762417576187,0.001596181463671069,0.002024222899064806,0.002397494910887145,0.002699822987097212,0.002916894106585375,
0.003036861367070640,0.003050885452886233,0.002953590661669655,0.002743415381800996,0.002422839894815699,0.001998478091739393,0.001481024033024778,0.000885049115939833,
0.000228650785950638,-0.000467040932550771,-0.001178487490196913,-0.001880479742801444,-0.002546968333883720,-0.003151960968744115,-0.003670457627499832,-0.004079392263907290,
-0.004358548046723229,-0.004491412808395003,-0.004465942123839048,-0.004275199363086006,-0.003917845118442551,-0.003398452531787279,-0.002727630133555675,-0.001921939707990868,
-0.001003603242675857,0.000000000000000002,0.001057038061377879,0.002132117125215862,0.003187336338928249,0.004183477969228678,0.005081298623057721,0.005842882606635942,
0.006433014986850680,0.006820529712474388,0.006979587360403019,0.006890837761805883,0.006542424954139873,0.005930795566676460,0.005061276798596616,0.003948396460298771,
0.002615924945496772,0.001096627268712525,-0.000568277809374028,-0.002329945313176427,-0.004133002699458318,-0.005916895044360736,-0.007617443707363696,-0.009168577759578325,
-0.010504190916985644,-0.011560071510704187,-0.012275849352066937,-0.012596901359766472,-0.012476157606952667,-0.011875751059073609,-0.010768457691091561,-0.009138878819350476,
-0.006984324225550714,-0.004315362801171072,-0.001156016765292844,0.002456414268920778,0.006471902292442096,0.010828604807581575,0.015454124505438985,0.020267085022786714,
0.025178983301330535,0.030096270365784036,0.034922604992916328,0.039561219003367835,0.043917328964289022,0.047900527080882035,0.051427084055496591,0.054422098717605220,
0.056821433226337009,0.058573378506176700,0.059640002123555226,0.059998139821041983}

------------ filter class
local FIRfilter = {} -- class

do

function FIRfilter:new(response)
  local o = {}
  setmetatable(o, self)
  self.__index = self

  assert(#response > 1)

  local coefs = {}
  for i = 1, #response do
    table.insert(coefs, response[i])
  end
               -- mirrored second half
  for i = #response - 1, 1, -1 do
    table.insert(coefs, response[i])
  end

  o.coefs = coefs
  o.taps = 2 * (#response - 1) + 1
  assert(o.taps == #coefs)
  return o
end

function FIRfilter:filter(data) -- do the filtering
  local out, buff = {}, {}
  local smptr = 1
                   -- init buffer
  local d = data[1]
  for i = 1, self.taps do
    table.insert(buff, d)
  end
                 -- do one sample
  local function sample()
    local d
    if smptr <= #data then
      d = data[smptr]
      smptr = smptr + 1
    else
      d = data[#data]
    end

    table.insert(buff, 1, d) -- new sample
    table.remove(buff) -- last sample
              -- convolution
    local sum = 0
    for i = 1, self.taps do
      sum = sum + self.coefs[i] * buff[i]
    end

    return sum
  end
              -- prefilter to be zero phase
  for i = 1, math.floor(self.taps / 2) do
    sample()
  end

  for i = 1, #data do
    local d = sample()
    table.insert(out, d)
  end

  return out
end

end -- end of filter class

local function getProjectPathName()
  local projectFileName = SV:getProject():getFileName()
  if not projectFileName then return end

  local projectName, projectDir
  projectFileName = projectFileName:gsub("\\", "/")
  projectDir, projectName = projectFileName:match("^(.*/)([^/]+)%.svp$")
  if not projectDir or not projectName then error(SV:T("project dir or name not found, save your project first")) end

  return projectName, projectDir
end

local function fileExists(fname)
  local fi = io.open(fname)
  if not fi then return end
  fi:close()
  return true
end

local function process()
                                  -- pitch file in project folder
  local projectName, projectDir = getProjectPathName()
  local pitchFileName = projectDir..projectName.."_Pitch.txt"
                                   -- show info box
  if not SV:showOkCancelBox(SV:T("Filter Pitch"), SV:T("Low pass filter <project_name>_Pitch.txt, old file become <project_name>_unfiltered_Pitch.txt")) then return end -- cancel pressed

  if not fileExists(pitchFileName) then
    SV:showMessageBox(SV:T("Error"), SV:T("Cannot open pitch file").." '"..pitchFileName.."'")
    return
  end

  local pitch = praatPitch:loadPitch(pitchFileName) -- pitch instance
  if not pitch then
    SV:showMessageBox(SV:T("Error"), SV:T("wrong pitch file format"))
    return
  end

  local fp, ifp = {}, {}
  local t = pitch.header.xmin
                  -- sampling
  while t <= pitch.header.xmax do
    local p = pitch:getPitch(t)
    table.insert(fp, p)
    table.insert(ifp, p)
    t = t + 0.002
  end
                     -- interpolate unvoiced
  local i = 1
  repeat
    while i <= #ifp and ifp[i] ~= 0 do i = i + 1 end
    if i >= #ifp then break end

    local j = i
    while j <= #ifp and ifp[j] == 0 do j = j + 1 end

    local left, right = ifp[i - 1] or ifp[j + 1], ifp[j + 1] or ifp[i - 1]
    assert(left and right)

    if left > 0 and right > 0 then
      for k = i, j do
        local pf, pt = math.log(left), math.log(right)
        ifp[k] = math.exp(pf + (pt - pf) / (j - i + 2) * (k - i + 1))
        if j + 1 - i <= 2 then -- short unvoiced -> voiced
          fp[k] = ifp[k]
        end
      end
    end

    i = j + 1
  until false

  local filt = FIRfilter:new(response)
  ffilt = filt:filter(ifp)
                           -- set unvoiced back
  for i, f in ipairs(fp) do
    if f == 0 then
      ffilt[i] = 0
    end
  end

  local fpitch = praatPitch:pitchFromArray(ffilt, 0.002, pitch.header.x1*0.002/pitch.header.dx, pitch.header.ceiling)
  pitch:savePitch(projectDir..projectName.."_unfiltered_Pitch.txt") -- backup of original
  fpitch:savePitch(pitchFileName) -- filtered

  SV:showMessageBox(SV:T("Info"), SV:T("Done filtering"))
end

function main()
  process()
  SV:finish()
end
