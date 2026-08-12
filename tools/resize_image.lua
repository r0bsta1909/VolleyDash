-- ============================================================================
-- tools/resize_image.lua -- Bilder verkleinern, ohne neue Abhaengigkeit
--
--     love . --resize=assets/bg.png:1600x1200     explizite Zielgroesse
--     love . --resize=assets/bg.png:1600          Breite, Hoehe proportional
--     love . --resize=quelle.png:1600x1200:ziel.png   in eine andere Datei
--
-- Ohne drittes Feld wird die Quelldatei **ueberschrieben**. Das ist Absicht:
-- der uebliche Fall ist "ich habe ein zu grosses Bild nach assets/ gelegt".
-- Rueckgaengig macht das `git checkout -- <datei>`, solange nichts committet
-- ist.
--
-- Warum LOEVE und nicht Pillow oder ImageMagick: das Projekt nimmt keine
-- Bildbibliothek als Abhaengigkeit auf (`CLAUDE.md` §7), und LOEVE liegt
-- ohnehin auf jeder Maschine, die das Spiel baut.
--
-- **Warum das Schreiben an love.filesystem vorbeigeht:** LOEVE darf nur in
-- seinen Speicherordner schreiben. Gebraucht wird aber der Repo-Ordner.
-- Deshalb kodiert das Werkzeug in den Arbeitsspeicher (`ImageData:encode`
-- ohne Dateinamen liefert FileData) und schreibt mit dem gewoehnlichen
-- `io.open` aus der Lua-Standardbibliothek.
--
-- Zur Groesse: der Hintergrund wird auf 800 x 600 gezeichnet
-- (`src/render/game_view.lua`), das Seitenverhaeltnis der Quelle ist also
-- ohne Belang. 1600 x 1200 ist die doppelte Aufloesung des Gezeigten und die
-- empfohlene Zielgroesse -- gross genug fuer 4K-Vollbild, klein genug fuer
-- acht Jahre alte Laptops (M1-09).
-- ============================================================================

local M = {}

-- "pfad:BxH[:ziel]" oder "pfad:B[:ziel]"
function M.parseSpec(spec)
    local source, size, target = spec:match("^(.-):(%d+x?%d*):(.+)$")
    if not source then
        source, size = spec:match("^(.-):(%d+x?%d*)$")
    end
    if not source or not size then return nil, "Form: --resize=datei.png:BREITExHOEHE[:ziel.png]" end

    local w, h = size:match("^(%d+)x(%d+)$")
    if not w then
        w = size:match("^(%d+)$")
        if not w then return nil, "Groesse nicht lesbar: " .. size end
    end

    return {
        source = source,
        target = target or source,
        width  = tonumber(w),
        height = h and tonumber(h) or nil,   -- nil = proportional
    }
end

local function writeFile(path, data)
    local file, err = io.open(path, "wb")
    if not file then return false, err end
    file:write(data)
    file:close()
    return true
end

-- Gibt true zurueck, wenn es geklappt hat. Meldungen gehen nach stdout;
-- gestartet wird das Werkzeug ueber lovec.exe, damit man sie sieht.
function M.run(spec)
    local job, err = M.parseSpec(spec)
    if not job then
        print("FEHLER: " .. err)
        return false
    end

    if not love.filesystem.getInfo(job.source) then
        print("FEHLER: " .. job.source .. " nicht gefunden (Pfad relativ zum Repo-Wurzelverzeichnis)")
        return false
    end

    -- mipmaps: beim Verkleinern um mehr als das Doppelte franst eine reine
    -- Linearfilterung sichtbar aus.
    -- Vor dem Schreiben lesen: bei Ueberschreiben in dieselbe Datei waere die
    -- Groesse danach die neue, und der Vergleich waere wertlos.
    local sourceInfo = love.filesystem.getInfo(job.source)

    local image = love.graphics.newImage(job.source, { mipmaps = true })
    image:setFilter("linear", "linear")
    image:setMipmapFilter("linear")

    -- getPixelDimensions, nicht getDimensions: bei aktiviertem highdpi teilt
    -- LOEVE die logischen Masse durch den DPI-Faktor. Gemeint sind hier immer
    -- echte Bildpunkte -- sonst skaliert das Werkzeug am Ziel vorbei.
    local sw, sh = image:getPixelDimensions()
    local tw = job.width
    local th = job.height or math.floor(sh * (tw / sw) + 0.5)

    -- dpiscale = 1 erzwingen: ohne das haette die Zeichenflaeche die Groesse
    -- tw * getDPIScale() und das Ergebnis waere nicht das bestellte Mass.
    -- Genau daran ist die improvisierte Fassung in M1-09 vorbeigelaufen.
    local canvas = love.graphics.newCanvas(tw, th, { dpiscale = 1 })
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    -- premultiplied: sonst bekommen halbtransparente Raender einen dunklen
    -- Saum, weil die Farbe zweimal mit dem Alpha multipliziert wird.
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, 0, 0, 0, tw / sw, th / sh)
    love.graphics.setBlendMode("alpha")
    love.graphics.setCanvas()

    local encoded = canvas:newImageData():encode("png")
    local ok, writeErr = writeFile(job.target, encoded:getString())
    if not ok then
        print("FEHLER beim Schreiben von " .. job.target .. ": " .. tostring(writeErr))
        return false
    end

    -- Selbstkontrolle: die geschriebene Datei nochmals aufmachen und den
    -- IHDR-Kopf lesen. Die Meldung des Werkzeugs sagt, was es tun *wollte* --
    -- entscheidend ist, was auf der Platte steht. Waehrend der Entwicklung
    -- dieses Werkzeugs stand dort zeitweise etwas anderes, und das faellt
    -- ohne diese Pruefung erst beim naechsten Blick ins Spiel auf.
    local check = io.open(job.target, "rb")
    if check then
        local header = check:read(24)
        check:close()
        if header and #header >= 24 then
            local b = { header:byte(17, 24) }
            local gotW = b[1] * 16777216 + b[2] * 65536 + b[3] * 256 + b[4]
            local gotH = b[5] * 16777216 + b[6] * 65536 + b[7] * 256 + b[8]
            if gotW ~= tw or gotH ~= th then
                print(("FEHLER: geschrieben wurden %d x %d statt %d x %d")
                    :format(gotW, gotH, tw, th))
                return false
            end
        end
    end

    print(("%s  %d x %d  ->  %s  %d x %d"):format(job.source, sw, sh, job.target, tw, th))
    if sourceInfo then
        print(("vorher %.2f MB, nachher %.2f MB")
            :format(sourceInfo.size / 1048576, #encoded:getString() / 1048576))
    end
    print("Texturspeicher: " .. ("%.1f MB -> %.1f MB")
        :format(sw * sh * 4 / 1048576, tw * th * 4 / 1048576))
    if job.target == job.source then
        print("Quelle ueberschrieben. Rueckgaengig: git checkout -- " .. job.source)
    end
    return true
end

return M
