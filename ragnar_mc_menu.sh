#!/usr/bin/env bash
# Ragnar MC - menu simple pour lancer / arreter le serveur Minecraft Docker
# Dossier serveur attendu : ~/ragnar mc

SERVER_DIR="$HOME/ragnar mc"
CONTAINER_NAME="ragnar-mc-local"

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

start_server() {
  check_folder
  cd "$SERVER_DIR" || exit 1
  echo "Lancement du serveur..."
  docker compose up -d
  echo ""
  echo "Serveur lance."
  show_ip
}

stop_server() {
  check_folder
  cd "$SERVER_DIR" || exit 1
  echo "Arret du serveur..."
  docker compose down
  echo ""
  echo "Serveur arrete."
}

restart_server() {
  check_folder
  cd "$SERVER_DIR" || exit 1
  echo "Redemarrage du serveur..."
  docker compose down
  docker compose up -d
  echo ""
  echo "Serveur redemarre."
  show_ip
}

server_status() {
  echo ""
  docker ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo ""
}

server_logs() {
  check_folder
  echo "Logs du serveur. Pour quitter : CTRL + C"
  echo ""
  docker logs -f "$CONTAINER_NAME"
}

backup_world() {
  check_folder
  cd "$SERVER_DIR" || exit 1

  if [ ! -d "$SERVER_DIR/data/world" ]; then
    echo "Aucun monde trouve dans data/world."
    return
  fi

  mkdir -p "$SERVER_DIR/backups"
  DATE=$(date +"%Y-%m-%d_%H-%M-%S")
  BACKUP_FILE="$SERVER_DIR/backups/world_backup_$DATE.tar.gz"

  echo "Sauvegarde du monde..."
  tar -czf "$BACKUP_FILE" -C "$SERVER_DIR/data" world

  echo ""
  echo "Sauvegarde creee :"
  echo "$BACKUP_FILE"
}

while true; do
  print_title
  echo "1) Lancer le serveur"
  echo "2) Arreter le serveur"
  echo "3) Redemarrer le serveur"
  echo "4) Voir le statut"
  echo "5) Voir les logs"
  echo "6) Afficher l'adresse locale"
  echo "7) Sauvegarder le monde"
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
    7) backup_world ;;
    0) echo "Bye."; exit 0 ;;
    *) echo "Choix invalide." ;;
  esac

  echo ""
  read -rp "Appuie sur Entree pour revenir au menu..."
  clear
done
