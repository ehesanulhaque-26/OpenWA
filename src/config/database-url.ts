/**
 * Database URL and Railway PostgreSQL reference variable parser.
 *
 * Supports multiple environment variable formats:
 *
 * 1. Standard DATABASE_* variables:
 *    DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, DATABASE_USERNAME, DATABASE_PASSWORD
 *
 * 2. DATABASE_URL (connection string):
 *    DATABASE_URL=postgresql://user:pass@host:5432/dbname
 *
 * 3. Railway PostgreSQL reference variables:
 *    - pguser (maps to DATABASE_USERNAME)
 *    - pgpassword (maps to DATABASE_PASSWORD)
 *    - pgdatabase / postgresdb (maps to DATABASE_NAME)
 *    - pg port (maps to DATABASE_PORT)
 *    - database public url / database url (maps to DATABASE_URL)
 *
 * Priority:
 * 1. Explicit DATABASE_* variables (highest priority)
 * 2. DATABASE_URL (if provided and no explicit DATABASE_* vars)
 * 3. Railway reference variables (pguser, pgpassword, etc.)
 */

export interface DatabaseConfig {
  host: string;
  port: number;
  database: string;
  username: string;
  password: string;
  ssl?: boolean;
}

/**
 * Parse a PostgreSQL connection URL into components.
 */
export function parsePostgresUrl(url: string): {
  host: string;
  port: number;
  database: string;
  username: string;
  password: string;
} {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'postgresql:' && parsed.protocol !== 'postgres:') {
      throw new Error(`Invalid protocol: ${parsed.protocol}`);
    }

    return {
      host: parsed.hostname,
      port: parsed.port ? parseInt(parsed.port, 10) : 5432,
      database: parsed.pathname.replace(/^\//, '') || 'postgres',
      username: parsed.username || 'postgres',
      password: parsed.password || '',
    };
  } catch (error) {
    throw new Error(`Invalid DATABASE_URL format: ${url}`);
  }
}

/**
 * Resolve PostgreSQL connection parameters from environment variables.
 *
 * Priority order:
 * 1. Explicit DATABASE_* variables
 * 2. DATABASE_URL
 * 3. Railway reference variables
 */
export function resolvePostgresConfig(env: NodeJS.ProcessEnv = process.env): DatabaseConfig {
  // 1. Check for explicit DATABASE_* variables first (highest priority)
  if (env.DATABASE_HOST && env.DATABASE_USERNAME && env.DATABASE_PASSWORD) {
    return {
      host: env.DATABASE_HOST,
      port: parseInt(env.DATABASE_PORT || '5432', 10),
      database: env.DATABASE_NAME || 'openwa',
      username: env.DATABASE_USERNAME,
      password: env.DATABASE_PASSWORD,
      ssl: env.DATABASE_SSL === 'true',
    };
  }

  // 2. Check for DATABASE_URL
  if (env.DATABASE_URL) {
    const parsed = parsePostgresUrl(env.DATABASE_URL);
    return {
      ...parsed,
      ssl: env.DATABASE_SSL !== 'false', // SSL enabled by default for DATABASE_URL
    };
  }

  // 3. Check for Railway PostgreSQL reference variables
  // Railway provides: pguser, pgpassword, pgdatabase, pg port, postgresdb, database url, etc.
  const railwayHost = env.PGHOST || env.DATABASE_HOST;
  const railwayUser = env.PGUSER || env.pguser || env.DATABASE_USERNAME;
  const railwayPassword = env.PGPASSWORD || env.pgpassword || env.DATABASE_PASSWORD;
  const railwayDatabase =
    env.PGDATABASE || env.pgdatabase || env.postgresdb || env.DATABASE_NAME;
  const railwayPort = env.PGPORT || env.PORT || env['pg port'] || env.DATABASE_PORT;

  if (railwayHost && railwayUser && railwayPassword) {
    return {
      host: railwayHost,
      port: parseInt(railwayPort || '5432', 10),
      database: railwayDatabase || 'postgres',
      username: railwayUser,
      password: railwayPassword,
      ssl: env.DATABASE_SSL === 'true',
    };
  }

  // 4. Check for Railway database URL reference
  const railwayUrl =
    env['database public url'] || env['database url'] || env.DATABASE_URL;

  if (railwayUrl) {
    const parsed = parsePostgresUrl(railwayUrl);
    // Allow Railway URL vars to override individual Railway vars
    return {
      host: parsed.host,
      port: parsed.port,
      database: parsed.database,
      username: parsed.username,
      password: parsed.password,
      ssl: env.DATABASE_SSL !== 'false',
    };
  }

  // Fallback to defaults
  return {
    host: 'localhost',
    port: 5432,
    database: 'openwa',
    username: 'postgres',
    password: '',
    ssl: false,
  };
}
