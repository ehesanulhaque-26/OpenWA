#!/bin/bash
# OpenWA - Railway Startup Script
# Handles database initialization and migration before starting the application
#
# This script:
# 1. Waits for PostgreSQL to be available (if using DATABASE_TYPE=postgres)
# 2. Ensures the PostgreSQL schema exists (for non-public schemas)
# 3. Starts the application (migrations run automatically on boot)
#
set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# =============================================================================
# PostgreSQL Initialization (only when using PostgreSQL)
# =============================================================================
if [ "${DATABASE_TYPE:-sqlite}" = "postgres" ]; then
    log "PostgreSQL mode detected - checking database connectivity..."

    # PostgreSQL connection parameters
    PGHOST="${DATABASE_HOST:-localhost}"
    PGPORT="${DATABASE_PORT:-5432}"
    PGUSER="${DATABASE_USERNAME:-postgres}"
    PGPASSWORD="${DATABASE_PASSWORD:-}"
    PGDATABASE="${DATABASE_NAME:-railway}"
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
        log "FATAL: Please verify DATABASE_HOST, DATABASE_PORT, DATABASE_USERNAME, DATABASE_PASSWORD are correct"
        log "FATAL: And that Railway PostgreSQL is properly linked to this service"
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
