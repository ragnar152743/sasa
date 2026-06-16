#!/usr/bin/env bash
# Ragnar MC menu + reset auto toutes les 10 min
# Fix : conserve les donnees joueurs pendant le reset.
# Dossier serveur : ~/ragnar mc
# Container : ragnar-mc-local

SERVER_DIR="$HOME/ragnar mc"
CONTAINER_NAME="ragnar-mc-local"
WORLD_NAME="world"
BASE_BACKUP="$SERVER_DIR/ragnar_base_world"
PID_FILE="$SERVER_DIR/ragnar_reset.pid"
RESET_LOG="$SERVER_DIR/ragnar_reset.log"
RESET_SECONDS=600

clear

print_title() {
  echo "===================================="
  echo "        Ragnar MC - Menu serveur"
  echo "===================================="
  echo ""
}

check_folder() {
  if [ ! -d "$SERVER_DIR" ]; then
    echo "Erreur : dossier introuvable : $SERVER_DIR"
    exit 1
  fi
  if [ ! -f "$SERVER_DIR/docker-compose.yml" ]; then
    echo "Erreur : docker-compose.yml introuvable dans : $SERVER_DIR"
    exit 1
  fi
}

show_ip() {
  IP=$(hostname -I | awk '{print $1}')
  echo ""
  echo "Adresse locale Minecraft :"
  echo "$IP:25565"
  echo ""
}

stop_reset_auto() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "Reset auto arrete."
  else
    rm -f "$PID_FILE"
    echo "Reset auto deja arrete."
  fi
}

wait_world_exists() {
  for i in $(seq 1 60); do
    [ -d "$SERVER_DIR/data/$WORLD_NAME" ] && return 0
    sleep 2
  done
  return 1
}

save_user_data() {
  TEMP="$SERVER_DIR/.ragnar_user_temp"
  WORLD="$SERVER_DIR/data/$WORLD_NAME"

  rm -rf "$TEMP"
  mkdir -p "$TEMP"

  # playerdata = inventaire, position, ender chest, xp...
  # advancements = succes
  # stats = statistiques
  for folder in playerdata advancements stats; do
    if [ -d "$WORLD/$folder" ]; then
      cp -a "$WORLD/$folder" "$TEMP/$folder"
    fi
  done

  # scoreboard optionnel
  if [ -f "$WORLD/data/scoreboard.dat" ]; then
    mkdir -p "$TEMP/data"
    cp -a "$WORLD/data/scoreboard.dat" "$TEMP/data/scoreboard.dat"
  fi
}

restore_user_data() {
  TEMP="$SERVER_DIR/.ragnar_user_temp"
  WORLD="$SERVER_DIR/data/$WORLD_NAME"

  rm -rf "$WORLD/playerdata" "$WORLD/advancements" "$WORLD/stats"

  for folder in playerdata advancements stats; do
    if [ -d "$TEMP/$folder" ]; then
      cp -a "$TEMP/$folder" "$WORLD/$folder"
    fi
  done

  if [ -f "$TEMP/data/scoreboard.dat" ]; then
    mkdir -p "$WORLD/data"
    cp -a "$TEMP/data/scoreboard.dat" "$WORLD/data/scoreboard.dat"
  fi

  rm -rf "$TEMP"
}

create_base_if_missing() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  if [ -d "$BASE_BACKUP" ]; then
    echo "Base reset : OK"
    return
  fi

  echo "Aucune base reset. Creation automatique..."
  wait_world_exists || { echo "Monde introuvable. Lance le serveur une fois."; return 1; }

  docker exec "$CONTAINER_NAME" mc-send-to-console "save-all flush" >/dev/null 2>&1 || true
  sleep 3

  docker compose down

  rm -rf "$BASE_BACKUP"
  cp -a "$SERVER_DIR/data/$WORLD_NAME" "$BASE_BACKUP"

  # La base garde le terrain, pas les donnees joueurs.
  rm -rf "$BASE_BACKUP/playerdata" "$BASE_BACKUP/advancements" "$BASE_BACKUP/stats"

  docker compose up -d
  echo "Base reset creee."
}

reset_world_keep_users() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  if [ ! -d "$BASE_BACKUP" ]; then
    echo "Base reset introuvable." >> "$RESET_LOG"
    return 1
  fi

  echo "[$(date)] Reset avec conservation joueurs..." >> "$RESET_LOG"

  docker exec "$CONTAINER_NAME" mc-send-to-console "say Reset du monde dans 10 secondes..." >/dev/null 2>&1 || true
  docker exec "$CONTAINER_NAME" mc-send-to-console "save-all flush" >/dev/null 2>&1 || true
  sleep 10

  docker compose down >> "$RESET_LOG" 2>&1

  save_user_data

  rm -rf "$SERVER_DIR/data/$WORLD_NAME"
  cp -a "$BASE_BACKUP" "$SERVER_DIR/data/$WORLD_NAME"

  restore_user_data

  docker compose up -d >> "$RESET_LOG" 2>&1

  echo "[$(date)] Reset termine. Donnees joueurs conservees." >> "$RESET_LOG"
}

reset_loop() {
  echo "$$" > "$PID_FILE"
  echo "Reset auto demarre : $(date)" >> "$RESET_LOG"

  while true; do
    sleep "$RESET_SECONDS"
    reset_world_keep_users
  done
}

start_reset_auto() {
  create_base_if_missing

  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Reset auto deja lance."
    return
  fi

  nohup bash "$0" --reset-loop >/dev/null 2>&1 &
  sleep 1
  echo "Reset auto lance toutes les 10 minutes."
  echo "Les donnees joueurs sont conservees."
}

start_server() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  echo "Lancement du serveur..."
  docker compose up -d
  echo "Serveur lance."
  show_ip

  echo "Lancement du reset auto..."
  start_reset_auto
}

stop_server() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  echo "Arret du reset auto..."
  stop_reset_auto

  echo "Arret du serveur..."
  docker compose down
  echo "Serveur arrete."
}

restart_server() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  echo "Redemarrage complet..."
  stop_reset_auto
  docker compose down
  docker compose up -d
  show_ip
  start_reset_auto
}

server_status() {
  echo ""
  docker ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo ""
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Reset auto : ACTIF"
  else
    echo "Reset auto : INACTIF"
  fi
  [ -d "$BASE_BACKUP" ] && echo "Base reset : OK" || echo "Base reset : absente"
  echo "Mode reset : conserve playerdata / advancements / stats"
}

server_logs() {
  check_folder
  echo "Logs du serveur. Pour quitter : CTRL + C"
  docker logs -f "$CONTAINER_NAME"
}

recreate_base() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  echo "Cette option remplace la base par le monde actuel."
  echo "Les donnees joueurs ne seront pas stockees dans la base."
  read -rp "Confirmer ? Ecris oui : " ok
  [ "$ok" != "oui" ] && echo "Annule." && return

  docker exec "$CONTAINER_NAME" mc-send-to-console "save-all flush" >/dev/null 2>&1 || true
  sleep 3
  docker compose down

  rm -rf "$BASE_BACKUP"
  cp -a "$SERVER_DIR/data/$WORLD_NAME" "$BASE_BACKUP"
  rm -rf "$BASE_BACKUP/playerdata" "$BASE_BACKUP/advancements" "$BASE_BACKUP/stats"

  docker compose up -d
  echo "Nouvelle base creee."
}

restore_now() {
  echo "Reset maintenant avec donnees joueurs conservees."
  read -rp "Confirmer ? Ecris oui : " ok
  [ "$ok" != "oui" ] && echo "Annule." && return
  reset_world_keep_users
}

if [ "$1" = "--reset-loop" ]; then
  reset_loop
  exit 0
fi

while true; do
  print_title
  echo "1) Lancer le serveur + reset auto"
  echo "2) Arreter le serveur + reset auto"
  echo "3) Redemarrer le serveur + reset auto"
  echo "4) Voir le statut"
  echo "5) Voir les logs"
  echo "6) Afficher l'adresse locale"
  echo "7) Refaire la base avec le monde actuel"
  echo "8) Reset maintenant"
  echo "0) Quitter"
  echo ""
  read -rp "Choisis une option : " choice
  clear

  case "$choice" in
    1) start_server ;;
    2) stop_server ;;
    3) restart_server ;;
    4) server_status ;;
    5) server_logs ;;
    6) show_ip ;;
    7) recreate_base ;;
    8) restore_now ;;
    0) echo "Bye."; exit 0 ;;
    *) echo "Choix invalide." ;;
  esac

  echo ""
  read -rp "Appuie sur Entree pour revenir au menu..."
  clear
done
