-- Distors REAPER
-- Distorsul se aude doar când masterul trece de 0 dB. Atunci scrie un mesaj pe care addonul NVDA
-- „Distors REAPER” îl citește: bipăie scurt și spune, de exemplu, „Distors pe master, scade volumul
-- cu 2 dB. Pe pista 2 cu 3 dB” (pistele spuse sunt cele care sunt ele însele peste 0 dB).
-- Cât merge redarea, spune de cel mult 3 ori „Poți urca pista 1 cu 4 dB. Poți urca pista 2 cu 1 dB”
-- (alt bip): cât poate urca fiecare pistă fără să treacă ea sau masterul de 0 dB, după cel mai tare
-- loc de la pornirea redării. Setările sunt mai jos.
-- Pornește singur odată cu REAPER. Control Shift Alt D (prins de addonul NVDA) îl oprește și îl pornește.

local FISIER = (os.getenv("TEMP") or "C:\\Windows\\Temp") .. "\\reaper_distors.txt"
local PAUZA = 1.5          -- secunde minime între două anunțuri de distors
local PRAG = 0.0           -- dB; 0 dB e plafonul
local TOLERANTA = 0.5      -- dB; vârfurile de câteva sutimi peste 0 dB (piese masterizate, MP3) nu sunt distors.
                           -- Alarma vine doar când masterul trece de 0 dB cu mai mult de atât.

-- ===== SETĂRI pentru „poți urca” =====
local ANUNTA_INCET = true  -- true = îți spune și când mai ai loc să urci; false = doar distorsul
local FEREASTRA = 5        -- la câte secunde de redare îți spune cât mai poți urca
local DE_CATE_ORI = 3      -- de câte ori îți spune, cel mult, de fiecare dată când pornești redarea
-- ===== Jurnal pentru verificare =====
local JURNAL = false       -- scrie în jurnal.txt (lângă script) ce valori dă REAPER, în primele 30 de secunde de redare
-- ======================================

-- Control Shift Alt D în REAPER: addonul NVDA scrie în acest fișier, iar scriptul se oprește sau pornește
local FIS_COMANDA = (os.getenv("TEMP") or "C:\\Windows\\Temp") .. "\\reaper_distors_comanda.txt"
local function citeste_comanda()
  local f = io.open(FIS_COMANDA, "r")
  if not f then return nil end
  local t = f:read("a")
  f:close()
  return t
end
local ultima_comanda = citeste_comanda()   -- ce era dinainte nu contează
local ultima_verificare = 0
local activ = true

local CALE_SCRIPT = ({reaper.get_action_context()})[2]
local FOLDER = CALE_SCRIPT:match("^(.*)[\\/]") or (os.getenv("TEMP") or ".")
local FIS_JURNAL = FOLDER .. "\\jurnal.txt"

local ultimul_anunt = -100 -- momentul ultimului anunț de distors
local cel_mai_mare = nil   -- cel mai mare vârf al masterului peste prag, de la ultimul anunț
local piste_peste = {}     -- pistă -> cel mai mare vârf peste prag, de la ultimul anunț
local inceput_redare = nil -- când a pornit redarea
local varf_redare = {}     -- "master" / pistă -> cel mai tare vârf de la pornirea redării
local urmatorul_urca = nil -- când îți spune din nou cât poți urca
local anunturi_urca = 0
local ultima_linie = -100

local function scrie(mesaj)
  local id = string.format("%.3f", reaper.time_precise())
  local tmp = FISIER .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return end
  f:write(id .. "\n" .. mesaj)
  f:close()
  os.remove(FISIER)
  os.rename(tmp, FISIER)
end

local function jurnal(linie)
  if not JURNAL then return end
  local f = io.open(FIS_JURNAL, "a")
  if f then f:write(linie .. "\n") f:close() end
end

local function nume_pista(pista)
  local _, n = reaper.GetTrackName(pista)
  local nr = n:match("^Track (%d+)$")
  if nr then return "pista " .. nr end
  return "pista " .. n
end

-- vârful unei piste (sau al masterului) acum, în dB; întoarce și valorile brute, pentru jurnal
local function varf(pista, e_master)
  local canale = 2
  if not e_master then
    canale = math.max(2, math.floor(reaper.GetMediaTrackInfo_Value(pista, "I_NCHAN")))
  end
  local maxim = -1000
  local brut = {}
  for c = 0, canale - 1 do
    -- doar vârful de acum: vârful ținut minte (Track_GetPeakHoldDB) dădea mereu -150 dB, iar ștergerea lui
    -- la fiecare citire strica cifrele de vârf din mixerul REAPER
    local a = reaper.Track_GetPeakInfo(pista, c)
    if c < 2 then brut[#brut + 1] = string.format("c%d info=%.5f", c, a or 0) end
    -- vârful de acum, ca amplitudine (1,0 = 0 dB)
    if a and a > 0 then
      local db = 20 * math.log(a, 10)
      if db > maxim then maxim = db end
    end
  end
  return maxim, table.concat(brut, " ")
end

local bucla_interna

local function bucla()
  local ok, eroare = pcall(bucla_interna)
  if not ok then
    scrie("Eroare în detectorul de distors: " .. tostring(eroare))
    return
  end
  reaper.defer(bucla)
end

bucla_interna = function()
  local acum = reaper.time_precise()
  if acum - ultima_verificare >= 0.1 then
    ultima_verificare = acum
    local c = citeste_comanda()
    if c and c ~= ultima_comanda then
      ultima_comanda = c
      activ = not activ
      cel_mai_mare = nil
      piste_peste = {}
      inceput_redare = nil
      if reaper.set_action_options then reaper.set_action_options(activ and 4 or 8) end
      scrie(activ and "Detectorul de distors a pornit" or "Detectorul de distors s-a oprit")
    end
  end
  if not activ then return end
  local reda = (reaper.GetPlayState() & 5) ~= 0
  if reda and not inceput_redare then
    inceput_redare = acum
    varf_redare = {}
    anunturi_urca = 0
    urmatorul_urca = acum + FEREASTRA
    jurnal(string.format("--- redare pornită (stare %d)", reaper.GetPlayState()))
  elseif not reda then
    inceput_redare = nil
  end
  local scrie_jurnal = JURNAL and reda and acum - inceput_redare <= 30 and acum - ultima_linie >= 0.5
  if scrie_jurnal then ultima_linie = acum end

  -- masterul
  local master = reaper.GetMasterTrack(0)
  local vm, brut = varf(master, true)
  if vm > PRAG + TOLERANTA and (not cel_mai_mare or vm > cel_mai_mare) then cel_mai_mare = vm end
  if reda and (not varf_redare.master or vm > varf_redare.master) then varf_redare.master = vm end
  if scrie_jurnal then
    jurnal(string.format("t=%.1f master %s acum=%.2f dB", acum - inceput_redare, brut, vm))
  end

  -- pistele
  local piste = {}
  local inregistreaza = (reaper.GetPlayState() & 4) ~= 0
  for i = 0, reaper.CountTracks(0) - 1 do
    local p = reaper.GetTrack(0, i)
    -- o pistă armată arată pe contor intrarea (microfonul), nu ce se cântă de pe ea;
    -- o măsurăm doar când înregistrezi
    local armata = reaper.GetMediaTrackInfo_Value(p, "I_RECARM") == 1
    if not (armata and not inregistreaza) then
      local v, b = varf(p, false)
      local k = tostring(p)  -- cheie sigură pentru pistă
      piste[#piste + 1] = p
      if v > PRAG + TOLERANTA and (not piste_peste[k] or v > piste_peste[k]) then piste_peste[k] = v end
      if reda and (not varf_redare[k] or v > varf_redare[k]) then varf_redare[k] = v end
      if scrie_jurnal then
        jurnal(string.format("      %s %s acum=%.2f dB", nume_pista(p), b, v))
      end
    end
  end

  -- distors: se aude doar când trece masterul de 0 dB; atunci spunem și pistele care sunt ele însele peste 0 dB
  if cel_mai_mare and acum - ultimul_anunt >= PAUZA then
    local mesaj = "Distors pe master, scade volumul cu " .. math.max(1, math.ceil(cel_mai_mare - PRAG)) .. " dB"
    for _, p in ipairs(piste) do
      local v = piste_peste[tostring(p)]
      if v then mesaj = mesaj .. ". Pe " .. nume_pista(p) .. " cu " .. math.max(1, math.ceil(v - PRAG)) .. " dB" end
    end
    scrie(mesaj)
    jurnal("anunț: " .. mesaj)
    ultimul_anunt = acum
    cel_mai_mare = nil
    piste_peste = {}
  elseif not cel_mai_mare then
    piste_peste = {}       -- o pistă peste 0 dB nu se aude distorsionată cât timp masterul e sub 0 dB
  end

  -- poți urca: cât merge redarea, după cel mai tare loc de la pornirea ei
  if not reda or not ANUNTA_INCET or anunturi_urca >= DE_CATE_ORI or acum < urmatorul_urca then return end
  urmatorul_urca = acum + FEREASTRA
  local loc_master = varf_redare.master and math.floor(PRAG - varf_redare.master) or 0
  if not varf_redare.master or varf_redare.master <= -60 or loc_master < 1 then return end
  local urca = {}
  for _, p in ipairs(piste) do
    local v = varf_redare[tostring(p)]
    -- sub -60 dB considerăm că pe pistă nu se cântă nimic
    if v and v > -60 then
      -- o pistă poate urca până ajunge ea la 0 dB, dar nici mai mult decât are loc masterul
      local cu_cat = math.min(math.floor(PRAG - v), loc_master)
      if cu_cat >= 1 then urca[#urca + 1] = nume_pista(p) .. " cu " .. cu_cat .. " dB" end
    end
  end
  if #urca == 0 then urca[1] = "masterul cu " .. loc_master .. " dB" end
  anunturi_urca = anunturi_urca + 1
  local mesaj = "Poți urca " .. table.concat(urca, ". Poți urca ")
  scrie(mesaj)
  jurnal("anunț: " .. mesaj)
end

-- Pornire automată: la prima rulare se adaugă în __startup.lua din REAPER,
-- ca scriptul să pornească singur de fiecare dată când deschizi REAPER.
local function porneste_singur()
  local cale_script = CALE_SCRIPT
  local startup = reaper.GetResourcePath() .. "\\Scripts\\__startup.lua"
  local continut = ""
  local f = io.open(startup, "r")
  if f then continut = f:read("a") or "" f:close() end
  if continut:find("Distors REAPER", 1, true) then return end
  local linii = "\n-- Distors REAPER: pornește detectorul de distors\n" ..
    "do local id = reaper.AddRemoveReaScript(true, 0, [[" .. cale_script .. "]], true)\n" ..
    "if id and id ~= 0 then reaper.Main_OnCommand(id, 0) end end\n"
  f = io.open(startup, "a")
  if f then f:write(linii) f:close() end
end

-- Aceeași scurtătură pornește și oprește: dacă scriptul rulează deja, a doua pornire îl oprește
-- fără întrebări (REAPER 7). Starea pornit/oprit apare și în lista de acțiuni.
if reaper.set_action_options then reaper.set_action_options(1 | 4) end

reaper.atexit(function()
  if reaper.set_action_options then reaper.set_action_options(8) end
  scrie("Detectorul de distors s-a oprit")
end)
porneste_singur()
jurnal("=== scriptul a pornit " .. os.date("%Y-%m-%d %H:%M:%S"))
scrie("Detectorul de distors a pornit")
bucla()
