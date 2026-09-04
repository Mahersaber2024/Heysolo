# MT5 on Linux VPS + RealVNC

## Step 1 — Install  [root]

apt update && apt -y install xvfb x11vnc screen wget openbox
dpkg --add-architecture i386 && apt update
apt -y install wine

## Step 2 — User  [root]

adduser mt5user         # pass: sdS4fgfdbgD@

## Step 3 — VNC password  [mt5user]

su - mt5user
mkdir -p ~/.vnc
x11vnc -storepasswd MySecretPass123 ~/.vnc/passwd

## Step 4 — Screen  [mt5user]

screen -S vnc

## Step 5 — Start VNC  [inside screen]

export DISPLAY=:1
Xvfb :1 -screen 0 1280x1024x24 >/dev/null 2>&1 &
openbox >/dev/null 2>&1 &
x11vnc -display :1 -forever -shared -rfbauth ~/.vnc/passwd -rfbport 5900 -bg

Ctrl+A then D

## Step 6 — Windows  [your PC]

ssh -L 5900:localhost:5900 mt5user@192.166.82.150

RealVNC Viewer -> localhost:5900 -> MySecretPass123

## Step 7 — Install MT5  [mt5user]

cd ~
wget https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe
export DISPLAY=:1
wine mt5setup.exe

## Step 8 — Screen  [mt5user]

screen -S mt5

## Step 9 — Run MT5  [inside screen]

export DISPLAY=:1
wine "$HOME/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"

Ctrl+A then D

## Step 10 — Cheatsheet  [mt5user]

su - mt5user            # screens belong to mt5user, not root

# Status
screen -ls
ps -u mt5user -f | grep -E 'Xvfb|x11vnc|terminal64'

# Back into a screen
screen -r vnc
screen -r mt5
screen -d -r mt5        # force detach + attach
Ctrl+A then D           # leave without closing

# Stop
pkill -f terminal64 && wineserver -k   # stop MT5
pkill x11vnc; pkill Xvfb               # stop VNC
screen -wipe                           # clear dead screens

# Start (detached, no Ctrl+A D needed)
screen -dmS vnc bash -c 'export DISPLAY=:1; Xvfb :1 -screen 0 1280x1024x24 & sleep 2; openbox & x11vnc -display :1 -forever -shared -rfbauth ~/.vnc/passwd -rfbport 5900 -bg; sleep infinity'

screen -dmS mt5 bash -c 'export DISPLAY=:1; wine "$HOME/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe"'

# Full restart (VNC first, then MT5)
pkill -f terminal64; wineserver -k; pkill x11vnc; pkill Xvfb
screen -wipe
# then run the two screen -dmS commands above
# then reconnect the SSH tunnel from Windows

## Step 11 — Add 2 more terminals  [mt5user]

# Idea: same DISPLAY=:1, each terminal gets its own WINEPREFIX + its own screen.
# Xvfb :1 must stay up. x11vnc can be off, terminals keep running.

# 11.1 copy installers  [root]
cp /opt/heysolo-bot/*.exe /home/mt5user/
cd /home/mt5user
mv "combatcapitalmarkets5setup (1).exe" combat.exe
mv fusionmarkets5setup.exe fusion.exe
chown mt5user: *.exe

# 11.2 install each one  [mt5user]
su - mt5user
export DISPLAY=:1

WINEPREFIX=$HOME/mt5-fusion wine ~/fusion.exe      # finish wizard in VNC
WINEPREFIX=$HOME/mt5-fusion wineserver -k

WINEPREFIX=$HOME/mt5-combat wine ~/combat.exe      # finish wizard in VNC
WINEPREFIX=$HOME/mt5-combat wineserver -k

# 11.3 run each in its own screen
screen -dmS fusion bash -c 'export DISPLAY=:1 WINEPREFIX=$HOME/mt5-fusion; wine "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"'
screen -dmS combat bash -c 'export DISPLAY=:1 WINEPREFIX=$HOME/mt5-combat; wine "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"'

screen -ls              # mt5 / fusion / combat all running

## Step 12 — Manage them  [mt5user]

# stop ONE (never run bare "wineserver -k", it kills all of them)
WINEPREFIX=$HOME/mt5-fusion wineserver -k; screen -S fusion -X quit

# restart ONE
WINEPREFIX=$HOME/mt5-fusion wineserver -k; screen -S fusion -X quit; sleep 3
screen -dmS fusion bash -c 'export DISPLAY=:1 WINEPREFIX=$HOME/mt5-fusion; wine "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"'

# look at charts / add indicators: just turn VNC on, all windows are on one desktop
x11vnc -display :1 -forever -shared -rfbauth ~/.vnc/passwd -rfbport 5900 -bg
pkill x11vnc            # turn viewing off, terminals stay up

# add a 4th terminal later: repeat 11.2 + 11.3 with a new name (mt5-<name>)
