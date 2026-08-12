-- ============================================================================
-- src/app/build_info.lua -- Version und Build-Hash (M1-04)
--
-- `tools/build.sh` erzeugt beim Bauen die Datei `src/build_info_gen.lua` und
-- legt sie in die `.love`. Aus dem Quellordner gestartet gibt es sie nicht --
-- dann steht hier "dev". Das ist kein Fehler, sondern die Aussage: dieses
-- Spiel kam nicht aus einem Build.
--
-- Warum zwei Dateien statt einer generierten: `src/build_info_gen.lua` ist ein
-- Artefakt und steht in `.gitignore`. Eine generierte Datei, die zugleich im
-- Repo liegt, wird bei jedem Build zu einer Aenderung im Arbeitsverzeichnis --
-- und irgendwann committet jemand einen Build-Hash von gestern.
--
-- Die Kennungen und ihre Wirkung im Netzwerk stehen in `06_BUILD` §6:
--   version     jedes Release, reine Anzeige
--   buildHash   jede Codeaenderung, ab M2 Warnung beim Join, kein Abbruch
-- ============================================================================

local BuildInfo = {
    version   = "dev",
    buildHash = "dev",
}

local ok, generated = pcall(require, "src.build_info_gen")
if ok and type(generated) == "table" then
    BuildInfo.version   = generated.version   or BuildInfo.version
    BuildInfo.buildHash = generated.buildHash or BuildInfo.buildHash
end

-- Was im Menue und in Fehlerberichten steht. Der Build-Hash ist die Angabe,
-- die im Zweifel zwei Rechner unterscheidet -- die Bug-Vorlage fragt genau
-- diese Zeichenkette ab.
function BuildInfo.label()
    return ("v%s (%s)"):format(BuildInfo.version, BuildInfo.buildHash)
end

return BuildInfo
