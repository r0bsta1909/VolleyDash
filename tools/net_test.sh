#!/usr/bin/env bash
# =============================================================================
# tools/net_test.sh -- Netzwerktest mit zwei Prozessen (M2-10)
#
#     ./tools/net_test.sh selftest    Host und Client in EINEM Prozess
#     ./tools/net_test.sh loopback    zwei Prozesse, ohne Fenster, feste Eingaben
#     ./tools/net_test.sh auto        zwei Prozesse MIT Fenster, Screenshots
#
# LOEVE wird aus $LOVE_BIN genommen, sonst aus dem PATH (CLAUDE.md §8). Der
# Pfad zur Maschine gehoert nicht in dieses Skript.
#
# WAS DIESES SKRIPT NICHT KANN, und warum das so bleibt:
#
#   Paketverlust. Beide Prozesse reden ueber 127.0.0.1, und da verliert nichts.
#   Fuer T-N-02 (5 % auf Kanal 2) und T-N-03 (20 % auf Kanal 1) braucht es
#   `clumsy` (Windows, https://jagt.github.io/clumsy/) mit dem Filter
#
#       udp and (udp.DstPort == 21212 or udp.SrcPort == 21212)
#
#   und darin "Drop" mit der gewuenschten Rate. Das Werkzeug haengt sich in den
#   Windows-Netzwerkstapel und laesst sich nicht aus einem Skript heraus
#   verlaesslich fernsteuern -- ein Aufruf, der es versucht und dabei still
#   scheitert, waere schlechter als diese Zeilen.
#
#   Zwei RECHNER. Was hier laeuft, beweist Protokoll und Ablauf, nicht den
#   Betrieb ueber ein echtes Netz: keine Firewall, keine WLAN-Latenz, kein
#   Broadcast ueber einen Switch. Das ist D2 aus `07_TEST_PLAN` §6 und braucht
#   Hardware.
# =============================================================================
set -u

MODE="${1:-selftest}"
LOVE="${LOVE_BIN:-love}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v "$LOVE" >/dev/null 2>&1 && [ ! -x "$LOVE" ]; then
    echo "FEHLER: LOEVE nicht gefunden. LOVE_BIN setzen, z. B." >&2
    echo "  LOVE_BIN=/d/love2d/LOVE/lovec.exe $0 $MODE" >&2
    exit 2
fi

cd "$ROOT"

case "$MODE" in
selftest)
    echo "== Selbsttest (ein Prozess) =="
    "$LOVE" . --net-selftest
    exit $?
    ;;

loopback)
    echo "== Loopback (zwei Prozesse, ohne Fenster) =="
    rm -f build/net-host.log build/net-client.log
    mkdir -p build

    "$LOVE" . --net-host=R-05 --client-id=1001 > build/net-host.log 2>&1 &
    HOST_PID=$!
    sleep 3
    "$LOVE" . --net-client=127.0.0.1 --client-id=2002 > build/net-client.log 2>&1
    CLIENT_CODE=$?
    wait "$HOST_PID"
    HOST_CODE=$?

    echo "--- Host ---";   cat build/net-host.log
    echo "--- Client ---"; cat build/net-client.log

    # Der Endstand muss auf beiden Seiten gleich sein (T-N-01).
    HOST_SCORE=$(grep -o 'Host fertig: [0-9]*:[0-9]*' build/net-host.log | tail -1 | sed 's/.*: //')
    CLIENT_SCORE=$(grep -o 'Client fertig: [0-9]*:[0-9]*' build/net-client.log | tail -1 | sed 's/.*: //')

    echo
    if [ -n "$HOST_SCORE" ] && [ "$HOST_SCORE" = "$CLIENT_SCORE" ]; then
        echo "OK  gleicher Endstand auf beiden Seiten: $HOST_SCORE"
        exit $(( HOST_CODE | CLIENT_CODE ))
    fi
    echo "FEHLER  Endstand Host '$HOST_SCORE' gegen Client '$CLIENT_SCORE'"
    exit 1
    ;;

auto)
    echo "== Autopilot (zwei Fenster, Screenshots) =="
    "$LOVE" . --net-auto-host --client-id=1001 &
    sleep 3
    "$LOVE" . --net-auto-client=127.0.0.1 --client-id=2002
    wait
    echo "Screenshots liegen im Save-Ordner: net-host.png und net-client.png"
    ;;

*)
    echo "unbekannter Modus: $MODE (selftest | loopback | auto)" >&2
    exit 2
    ;;
esac
