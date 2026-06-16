#!/usr/bin/env bash
# Ragnar MC - menu simple : lancer / arreter / redemarrer
# Quand tu lances le serveur, le reset monde toutes les 10 minutes demarre aussi.
# Dossier serveur attendu : ~/ragnar mc

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
    echo "Erreur : le dossier serveur n'existe pas :"
    echo "$SERVER_DIR"
    echo ""
    echo "Cree d'abord le serveur dans le dossier : ragnar mc"
    exit 1
  fi

  if [ ! -f "$SERVER_DIR/docker-compose.yml" ]; then
    echo "Erreur : docker-compose.yml introuvable dans :"
    echo "$SERVER_DIR"
    echo ""
    echo "Le serveur n'est pas encore configure."
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

wait_world_exists() {
  echo "Verification du monde..."
  for i in $(seq 1 60); do
    if [ -d "$SERVER_DIR/data/$WORLD_NAME" ]; then
      return 0
    fi
    sleep 2
  done

  echo "Attention : le dossier du monde n'a pas ete trouve apres attente."
  return 1
}

create_base_if_missing() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  if [ -d "$BASE_BACKUP" ]; then
    echo "Base du monde deja presente."
    return 0
  fi

  echo ""
  echo "Aucune base de reset trouvee."
  echo "Creation automatique de la base du monde..."
  echo ""

  wait_world_exists || return 1

  echo "Sauvegarde du serveur avant copie..."
  docker exec "$CONTAINER_NAME" mc-send-to-console "save-all flush" >/dev/null 2>&1 || true
  sleep 3

  echo "Pause rapide du serveur pour copier une base propre..."
  docker compose down

  if [ ! -d "$SERVER_DIR/data/$WORLD_NAME" ]; then
    echo "Erreur : impossible de trouver le monde."
    docker compose up -d
    return 1
  fi

  rm -rf "$BASE_BACKUP"
  cp -a "$SERVER_DIR/data/$WORLD_NAME" "$BASE_BACKUP"

  echo "Base de reset creee :"
  echo "$BASE_BACKUP"

  echo "Relance du serveur..."
  docker compose up -d
}

start_reset_loop() {
  mkdir -p "$SERVER_DIR"
  echo "$$" > "$PID_FILE"

  echo "Reset auto demarre a $(date)" >> "$RESET_LOG"
  echo "Intervalle : $RESET_SECONDS secondes" >> "$RESET_LOG"

  while true; do
    sleep "$RESET_SECONDS"

    if [ ! -d "$BASE_BACKUP" ]; then
      echo "[$(date)] Base introuvable, reset annule." >> "$RESET_LOG"
      continue
    fi

    echo "[$(date)] Reset dans 10 secondes..." >> "$RESET_LOG"
    docker exec "$CONTAINER_NAME" mc-send-to-console "say Reset du monde dans 10 secondes..." >/dev/null 2>&1 || true
    sleep 10

    cd "$SERVER_DIR" || continue

    echo "[$(date)] Arret serveur..." >> "$RESET_LOG"
    docker compose down >> "$RESET_LOG" 2>&1

    echo "[$(date)] Restauration du monde..." >> "$RESET_LOG"
    rm -rf "$SERVER_DIR/data/$WORLD_NAME"
    cp -a "$BASE_BACKUP" "$SERVER_DIR/data/$WORLD_NAME"

    echo "[$(date)] Relance serveur..." >> "$RESET_LOG"
    docker compose up -d >> "$RESET_LOG" 2>&1

    echo "[$(date)] Reset termine." >> "$RESET_LOG"
  done
}

start_reset_auto() {
  check_folder

  if [ ! -d "$BASE_BACKUP" ]; then
    create_base_if_missing
  fi

  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Reset auto deja lance. PID : $(cat "$PID_FILE")"
    return 0
  fi

  echo "Lancement du reset auto toutes les 10 minutes..."
  nohup bash "$0" --reset-loop >/dev/null 2>&1 &
  sleep 1

  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Reset auto lance."
  else
    echo "Attention : reset auto pas confirme. Regarde :"
    echo "$RESET_LOG"
  fi
}

stop_reset_auto() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    PID="$(cat "$PID_FILE")"
    kill "$PID" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "Reset auto arrete."
  else
    rm -f "$PID_FILE"
    echo "Reset auto deja arrete."
  fi
}

reset_status() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Reset auto : ACTIF"
    echo "PID : $(cat "$PID_FILE")"
  else
    echo "Reset auto : INACTIF"
  fi

  echo ""
  if [ -d "$BASE_BACKUP" ]; then
    echo "Base monde : OK"
  else
    echo "Base monde : absente"
  fi

  echo ""
  echo "Dernieres lignes reset :"
  if [ -f "$RESET_LOG" ]; then
    tail -n 10 "$RESET_LOG"
  else
    echo "Aucun log reset."
  fi
}

start_server() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  echo "Lancement du serveur..."
  docker compose up -d

  echo ""
  echo "Serveur lance."
  show_ip

  echo "Le reset monde va aussi se lancer."
  start_reset_auto

  echo ""
  echo "Info : le monde revient a la base toutes les 10 minutes."
}

stop_server() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  echo "Arret du reset auto..."
  stop_reset_auto

  echo ""
  echo "Arret du serveur..."
  docker compose down

  echo ""
  echo "Serveur arrete."
}

restart_server() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  echo "Arret du reset auto..."
  stop_reset_auto

  echo ""
  echo "Redemarrage du serveur..."
  docker compose down
  docker compose up -d

  echo ""
  echo "Serveur redemarre."
  show_ip

  echo "Relance du reset auto..."
  start_reset_auto
}

server_status() {
  echo ""
  docker ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo ""
  reset_status
  echo ""
}

server_logs() {
  check_folder
  echo "Logs du serveur. Pour quitter : CTRL + C"
  echo ""
  docker logs -f "$CONTAINER_NAME"
}

recreate_base() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  echo "Cette option remplace la base du reset par le monde actuel."
  echo "Le monde actuel deviendra l'etat normal."
  echo ""
  read -rp "Tu confirmes ? Ecris oui : " confirm

  if [ "$confirm" != "oui" ]; then
    echo "Annule."
    return
  fi

  echo "Sauvegarde du serveur..."
  docker exec "$CONTAINER_NAME" mc-send-to-console "save-all flush" >/dev/null 2>&1 || true
  sleep 3

  echo "Arret du serveur pour copier proprement..."
  docker compose down

  if [ ! -d "$SERVER_DIR/data/$WORLD_NAME" ]; then
    echo "Erreur : monde introuvable."
    docker compose up -d
    return
  fi

  rm -rf "$BASE_BACKUP"
  cp -a "$SERVER_DIR/data/$WORLD_NAME" "$BASE_BACKUP"

  echo "Nouvelle base creee."
  echo "Relance serveur..."
  docker compose up -d
}

restore_base_now() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  if [ ! -d "$BASE_BACKUP" ]; then
    echo "Aucune base trouvee. Lance d'abord le serveur une fois."
    return
  fi

  echo "Le monde actuel va revenir a la base maintenant."
  read -rp "Tu confirmes ? Ecris oui : " confirm

  if [ "$confirm" != "oui" ]; then
    echo "Annule."
    return
  fi

  docker compose down
  rm -rf "$SERVER_DIR/data/$WORLD_NAME"
  cp -a "$BASE_BACKUP" "$SERVER_DIR/data/$WORLD_NAME"
  docker compose up -d

  echo "Monde restaure."
}

if [ "$1" = "--reset-loop" ]; then
  start_reset_loop
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
  echo "7) Refaire la base du reset avec le monde actuel"
  echo "8) Restaurer la base maintenant"
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
    8) restore_base_now ;;
    0) echo "Bye."; exit 0 ;;
    *) echo "Choix invalide." ;;
  esac

  echo ""
  read -rp "Appuie sur Entree pour revenir au menu..."
  clear
done
