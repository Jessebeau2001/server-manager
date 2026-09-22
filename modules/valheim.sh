#!/bin/sh

SERVER_DIR="$HOME/.steam/root/steamapps/common/Valheim dedicated server"
SERVER_ENTRYPOINT="./my_server_start.sh"
SERVER_NAME="valheim"
SAVE_DIR="$HOME/.config/unity3d/IronGate/Valheim/worlds_local/"
BACKUP_DIR="/mnt/nas-vault/Backup/Valheim/server/MalseServer"


module_update() {
    steamcmd +@sSteamCmdForcePlatformType linux +login anonymous +app_update 896660 -beta public validate +quit
}