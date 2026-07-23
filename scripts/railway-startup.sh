#!/bin/bash
# OpenWA - Railway Startup Script
# Handles database initialization and migration before starting the application
#
# This script:
# 1. Waits for PostgreSQL to be available (if using DATABASE_TYPE=postgres)
# 2. Ensures the PostgreSQL schema exists (for non-public schemas)
# 3. Starts the application (migrations run automatically on boot)
#
# Supports multiple environment variable formats:
# - DATABASE_HOST/PORT/NAME/USERNAME/PASSWORD (standard)
# - DATABASE_URL (connection string)
# - Railway references: pguser, pgpassword, pgdatabase, pg port, database url, etc.
#
set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# =============================================================================
# PostgreSQL URL Parser
# =============================================================================
# Parse a PostgreSQL URL and extract components
parse_pg_url() {
    local url="$1"
    # Remove protocol if present
    url="${url#postgresql://}"
    url="${url#postgres://}"
    
    # Extract components using parameter expansion
    local auth="${url%%@*}"
    local host_port_db="${url#*@}"
    
    local user="${auth%%:*}"
    local password="${auth#*:}"
    if [ "$password" = "$auth" ]; then
        password=""
    fi
    
    local host="${host_port_db%%/*}"
    local db_path="${host_port_db#*/}"
    local database="${db_path%%\?*}"
    if [ -z "$database" ]; then
        database="postgres"
    fi
    
    local port="${host#*:}"
    if [ "$port" = "$host" ]; then
        port="5432"
    fi
    host="${host%%:*}"
    
    echo "${host}|${port}|${database}|${user}|${password}"
}

# =============================================================================
# PostgreSQL Initialization (only when using PostgreSQL)
# =============================================================================
if [ "${DATABASE_TYPE:-sqlite}" = "postgres" ]; then
    log "PostgreSQL mode detected - checking database connectivity..."

    # PostgreSQL connection parameters
    # Support multiple environment variable formats:
    # 1. Explicit DATABASE_* variables
    # 2. DATABASE_URL connection string
    # 3. Railway reference variables (pguser, pgpassword, pgdatabase, pg port)
    # 4. Railway database URL references (database url, database public url)
    
    # Default values
    PGHOST=""
    PGPORT="5432"
    PGUSER=""
    PGPASSWORD=""
    PGDATABASE=""
    
    # Priority 1: Explicit DATABASE_* variables
    if [ -n "${DATABASE_HOST:-}" ] && [ -n "${DATABASE_USERNAME:-}" ]; then
        log "Using explicit DATABASE_* variables"
        PGHOST="${DATABASE_HOST}"
        PGPORT="${DATABASE_PORT:-5432}"
        PGUSER="${DATABASE_USERNAME}"
        PGPASSWORD="${DATABASE_PASSWORD:-}"
        PGDATABASE="${DATABASE_NAME:-postgres}"
    # Priority 2: DATABASE_URL
    elif [ -n "${DATABASE_URL:-}" ]; then
        log "Using DATABASE_URL"
        IFS='|' read -r PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD <<< "$(parse_pg_url "$DATABASE_URL")"
    # Priority 3: Railway reference variables
    elif [ -n "${pguser:-}" ] || [ -n "${PGUSER:-}" ]; then
        log "Using Railway reference variables"
        PGHOST="${PGHOST:-${DATABASE_HOST:-}}"
        PGPORT="${PGPORT:-${DATABASE_PORT:-${PORT:-${pg port:-5432}}}"
        PGUSER="${pguser:-${PGUSER:-${DATABASE_USERNAME:-postgres}}"
        PGPASSWORD="${pgpassword:-${PGPASSWORD:-${DATABASE_PASSWORD:-}}"
        PGDATABASE="${pgdatabase:-${postgresdb:-${PGDATABASE:-${DATABASE_NAME:-postgres}}}"
    # Priority 4: Railway database URL references
    elif [ -n "${database public url:-}" ]; then
        log "Using Railway 'database public url' reference"
        IFS='|' read -r PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD <<< "$(parse_pg_url "${database public url}")"
    elif [ -n "${database url:-}" ]; then
        log "Using Railway 'database url' reference"
        IFS='|' read -r PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD <<< "$(parse_pg_url "${database url}")"
    else
        # Fallback to defaults
        log "Using default PostgreSQL settings"
        PGHOST="${DATABASE_HOST:-localhost}"
        PGPORT="${DATABASE_PORT:-5432}"
        PGUSER="${DATABASE_USERNAME:-postgres}"
        PGPASSWORD="${DATABASE_PASSWORD:-}"
        PGDATABASE="${DATABASE_NAME:-postgres}"
    fi
    
    PGSCHEMA="${POSTGRES_SCHEMA:-public}"

    # Function to check PostgreSQL connectivity
    wait_for_postgres() {
        local max_attempts=30
        local attempt=1

        log "Waiting for PostgreSQL at ${PGHOST}:${PGPORT}..."

        while [ $attempt -le $max_attempts ]; do
            if PGPASSWORD="${PGPASSWORD}" psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" -c "SELECT 1;" > /dev/null 2>&1; then
                log "PostgreSQL is ready!"
                return 0
            fi

            log "Attempt ${attempt}/${max_attempts}: PostgreSQL not ready yet, waiting 2 seconds..."
            sleep 2
            attempt=$((attempt + 1))
        done

        log "ERROR: PostgreSQL did not become ready within ${max_attempts} attempts"
        return 1
    }

    # Function to create schema if it doesn't exist
    ensure_schema_exists() {
        if [ "${PGSCHEMA}" = "public" ]; then
            log "Using default 'public' schema - no schema creation needed"
            return 0
        fi

        log "Ensuring schema '${PGSCHEMA}' exists..."
        
        # Check if schema exists
        schema_exists=$(PGPASSWORD="${PGPASSWORD}" psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" -t -c "SELECT 1 FROM pg_namespace WHERE nspname = '${PGSCHEMA}';" 2>/dev/null || echo "")

        if [ -z "${schema_exists}" ]; then
            log "Creating schema '${PGSCHEMA}'..."
            PGPASSWORD="${PGPASSWORD}" psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" -c "CREATE SCHEMA \"${PGSCHEMA}\" AUTHORIZATION \"${PGUSER}\";" || {
                log "WARNING: Could not create schema (may already exist or insufficient permissions)"
            }
        else
            log "Schema '${PGSCHEMA}' already exists"
        fi
    }

    # Wait for PostgreSQL and create schema
    if ! wait_for_postgres; then
        log "FATAL: Could not connect to PostgreSQL"
        log "FATAL: Please verify PostgreSQL is linked to the OpenWA service in Railway"
        log "FATAL: And that DATABASE_TYPE=postgres is set"
        exit 1
    fi

    ensure_schema_exists
    log "PostgreSQL initialization complete"
else
    log "SQLite mode - creating data directory if needed"
    mkdir -p /app/data/sessions /app/data/media /app/data/plugins
fi

# =============================================================================
# Clear stale Chromium Singleton locks
# =============================================================================
log "Clearing stale Chromium locks..."
rm -f /app/data/sessions/*/Singleton* 2>/dev/null || true

# =============================================================================
# Start the Application
# =============================================================================
log "Starting OpenWA application..."
log "Database type: ${DATABASE_TYPE:-sqlite}"
log "Auto-start sessions: ${AUTO_START_SESSIONS:-false}"

exec node dist/main
