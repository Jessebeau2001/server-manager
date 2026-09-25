#!/bin/bash

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================
log() {
    # echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$1"
}

echerr() {
    echo "Error: $1" >&2
}

die() {
    echerr "$1"
    exit 1
}

prompt_yn() {
    local message="$1"
    local response

    read -r -p "${message} [y/n]: " response

    [[ "$response" == [Yy] ]] # Returns true if Y or y
}

is_file() {
    path=$1                     # The path to check for
    [ -f "$1" ] && [ -r "$1" ]  # Returns whether the path is regular file & and readable
}

is_fn() {
    command -v "$1" >/dev/null 2>&1
}

require_dir() {
    path="$1"
    message="$2"
    if [ ! -d "$path" ]; then
        die "$message: '$path'"
    fi
}

require_file() {
    path="$1"
    message="$2"
    if ! is_file "$path"; then
        die "$message: '$path'"
    fi
}

generate_backup_name() {
    local timestamp="$(date +%Y-%m-%d)"
    local out_file="${BACKUP_DIR}/${timestamp}.zip"
    local suffix=1

    while [ -e "$out_file" ]; do
        if [ "$suffix" -gt 99 ]; then
            die "Error: Incremental name generator limit reached. Backup was not created."
        fi

        out_file="${BACKUP_DIR}/${timestamp}_worlds-${suffix}.zip"
        suffix=$((suffix + 1))
    done

    echo "$out_file"
}

# ==============================================================================
# MODULE FUNCTIONS
# ==============================================================================
load_module() {
    module_path="${MODULE_DIR}/${module}.sh"

    echo "Loading ${module_path}..."

    # POSIX source dot notation instead of bash source
    if ! . "$module_path"; then
        die "Failed to load module '$module'."
    fi

    # Check server name explicityly
    # This is the only variable that isnt a file or directory
    if [ -z "${SERVER_NAME:-}" ]; then
        die "constant 'SERVER_NAME' is not set."
    fi

    for fn in "module_update"; do
        if ! is_fn "$fn"; then
            die "Module '$module' is missing required function: $fn()"
        fi
    done

    # Set global session name
    SESSION_NAME="${SERVER_NAME}-managed-server"
}

# ==============================================================================
# SESSION FUNCTIONS
# ==============================================================================
session_is_found() {
    if screen -list | grep -q "$SESSION_NAME"; then
        return 0 # True
    else
        return 1 # False
    fi
}

# Send raw characters
session_stuff() {
    screen -S "$SESSION_NAME" -X stuff "$1"
}

# Execute a command in the session shell
session_exec() {
    session_stuff "$1"$'\r'
}

# Send SIGINT (Ctrl+C) to session
session_stop() {
    session_stuff "^C"
}

session_await_exit() {
    timeout=20 # Timeout duration in seconds

    while session_is_found; do
        if [ ! "$timeout" -gt 0 ]; then # Timeout after n cycles
            return 1                    # False - Session was not quit
        fi

        sleep 1                         # Stall loop to make this less spammy
        timeout=$((timeout - 1))
    done

    return 0 # success
}

session_ensure_closed() {
    if session_is_found; then
        if ! prompt_yn "Server is running, stop the server and continue?"; then
            return 1 # False - action aborted
        fi

        log "Stopping server..."
        session_stop

        if ! session_await_exit; then
            log "Could not stop server."
            return 1 # False - action failed
        fi
    fi

    return 0 # Session was or is stopped
}

session_prompt_restart() {
    local message="$1 Do you want to restart the session?"
    if prompt_yn "$message"; then
        server_start
        return 0 # Restarted
    else
        return 1 # Ignored
    fi
}

# ==============================================================================
# COMMANDS
# ==============================================================================
server_start() {
    require_dir "$SERVER_DIR" "Could find server directory"
    require_file "${SERVER_DIR}/${SERVER_ENTRYPOINT}" "Could not find server entrypoint"

    if session_is_found; then
        die "Cannot start server \"$SESSION_NAME\", session already exists"
    fi

    log "Starting server session '$SESSION_NAME'..."

    (   # Use subshell so cd doesn't mess with main process
        cd "$SERVER_DIR" || exit 1
        # screen -L -Logfile tmp.txt -dmS "$SESSION_NAME" "${SERVER_ENTRYPOINT}"
        screen -dmS "$SESSION_NAME" "${SERVER_ENTRYPOINT}"
    )

    if session_is_found; then
        log "Server started successfully!"
        log "Attach to console with: screen -r $session_name"
    else
        die "Failed to launch screen session."
    fi
}

server_stop() {
    if ! session_is_found; then
        die "No active session found for \"$SESSION_NAME\""
    fi
    
    log "Attempting to stop session \"$SESSION_NAME\"..."
    
    session_stop

    if session_await_exit; then
        log "Server was stopped..."
    else
        die "Server stop command timed out. Could not stop session."
    fi
}

server_update() {
    if ! session_ensure_closed; then
        die "Update cancelled."
    fi

    log "Updating server..."
    module_update

    session_prompt_restart "Update complete."
}

server_backup_save() {
    # Make sure the directories exist
    require_dir "$SAVE_DIR" "Cannot find world save directory."
    require_dir "$BACKUP_DIR" "Cannot find backup directory."

    if ! session_ensure_closed; then
        die "Backup cancelled."
    fi

    # Generate filename for the backup
    local out_file=$(generate_backup_name)
    log "Writing backup to '$out_file'"

    # Run and measure zipping process
    local start_ns=$(date +%s%N)
    zip -r "$out_file" "$SAVE_DIR"
    local status=$? # Capture last commands exit status
    local end_ns=$(date +%s%N)

    # Notify user of result
    if [ $status -eq 0 ]; then
        local elapsed_ms=$(((end_ns - start_ns) / 1000000 ))
        session_prompt_restart "Backup complete in ${elapsed_ms}ms."
    else
        die "Error: Backup failed for an unexpected reason."
        return 1
    fi
}

show_help() {
    echo "Usage: $0 {module} {start|stop|backup|update}"
}

# ==============================================================================
# ENTRYPOINT
# ==============================================================================

# Constants
MODULE_DIR="modules"
SESSION_NAME="" # Filled by module

# Program args
module=$1   # What module to load
command=$2  # What command to execute

# Command unspecified, exit
if [ -z "$command" ]; then
    show_help
    exit 1
fi

# Attempt to load the module or fail
load_module

case "$command" in
    start)
        server_start
        ;;
    stop)
        server_stop
        ;;
    backup)
        server_backup_save
        ;;
    update)
        server_update
        ;;
    test)
        log "Hello world!"
        ;;
    *)
        echerr "Invalid or missing command."
        show_help
        ;;
esac