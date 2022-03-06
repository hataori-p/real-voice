SCRIPT_TITLE = "RV Notes to TextGrid"
-- Ver.1 - exports notes and lyrics to Praat's textGrid object, pitch encoded in lyrics,
--   after editing in Praat it can be loaded back by "RV Notes from TextGrid" ver.2

function getClientInfo()
  return {
    name = SV:T(SCRIPT_TITLE),
    author = "Hataori@protonmail.com",
    category = "Real Voice",
    versionNumber = 1,
    minEditorVersion = 65537
  }
end

local inputForm = {
    title = SV:T("Notes to Praat Textgrid"),
    message = SV:T("Exports notes to a textgrid file"),
    buttons = "OkCancel",
    widgets = {
      {
        name = "file", type = "TextBox",
        label = SV:T("filePath/fileName.txt"),
        default = "[projectDir]/[projectName]_textGrid.txt"
      }
    }
  }

local function getProjectPathName()
  local projectFileName = SV:getProject():getFileName()
  if not projectFileName then return end

  local projectName, projectDir
  projectFileName = projectFileName:gsub("\\", "/")
  projectDir, projectName = projectFileName:match("^(.*/)([^/]+)%.svp$")
  if not projectDir or not projectName then error(SV:T("project dir or name not found")) end

  return projectName, projectDir
end

local function process()
  package.path = ".\\?.lua;C:\\Delphi\\YT\\?.lua;C:\\Delphi\\lua\\lua\\?.lua;C:\\Delphi\\lua\\lua\\?\\?.lua;"
  local JSON = require("JSON")


  local dlgResult = SV:showCustomDialog(inputForm)
  if not dlgResult.status then return end -- cancel pressed
                          -- output file
  local filePathName = dlgResult.answers.file or ""
  if filePathName == "" then filePathName = "[projectDir]/[projectName]_textGrid.txt" end

  if filePathName:match("%[projectDir%]") or filePathName:match("%[projectName%]") then
    local projectName, projectDir = getProjectPathName()
    filePathName = filePathName:gsub("%[projectDir%]", projectDir)
    filePathName = filePathName:gsub("%[projectName%]", projectName)
  end
  filePathName = filePathName:gsub("\\", "/")
  filePathName = filePathName:gsub("/+", "/")
                            -- synthv structures
  local project = SV:getProject()
  local timeAxis = project:getTimeAxis()
  local scope = SV:getMainEditor():getCurrentGroup()
  local group = scope:getTarget()

  local notes, maxtime = {}, 0
  for i = 1, group:getNumNotes() do
    local note = group:getNote(i)

    local lyr = note:getLyrics()
    local pitch = note:getPitch() - 69 -- midi offset
    local blOnset, blEnd = note:getOnset(), note:getEnd()

    local tons = timeAxis:getSecondsFromBlick(blOnset) -- start time
    local tend = timeAxis:getSecondsFromBlick(blEnd) -- end time

    table.insert(notes, {
      lyr = lyr,
      pitch = pitch,
      tstart = tons,
      tend = tend
    })

    if tend > maxtime then maxtime = tend end
  end
  maxtime = maxtime + 1.0
          -- number of intervals
  local cnt = 0
  local pretim = 0
  for _, nt in ipairs(notes) do
    if math.abs(nt.tstart - pretim) > 0.0001 then
      cnt = cnt + 1
    end
    cnt = cnt + 1

    pretim = nt.tend
  end
  cnt = cnt + 1
            -- write to file
  local fo = io.open(filePathName, "w")
  fo:write("File type = \"ooTextFile\"\n")
  fo:write("Object class = \"TextGrid\"\n")
  fo:write("\n")
  fo:write("0\n")
  fo:write(maxtime.."\n")
  fo:write("<exists>\n")
  fo:write("1\n")
  fo:write("\"IntervalTier\"\n")
  fo:write("\"Notes\"\n")
  fo:write("0\n")
  fo:write(maxtime.."\n")
  fo:write(cnt.."\n")

  local pretim = 0
  for _, nt in ipairs(notes) do
    if math.abs(nt.tstart - pretim) > 0.0001 then
      fo:write(pretim.."\n")
      fo:write(nt.tstart.."\n")
      fo:write("\"\"\n")

      fo:write(nt.tstart.."\n")
      fo:write(nt.tend.."\n")
      fo:write("\""..nt.lyr.." ("..nt.pitch..")\"\n")
    else
      fo:write((nt.tstart).."\n")
      fo:write(nt.tend.."\n")
      fo:write("\""..nt.lyr.." ("..nt.pitch..")\"\n")
    end

    pretim = nt.tend
  end

  fo:write(pretim.."\n")
  fo:write((pretim + 1.0).."\n")
  fo:write("\"\"\n")

  fo:close()
end

function main()
  process()
  SV:finish()
end

