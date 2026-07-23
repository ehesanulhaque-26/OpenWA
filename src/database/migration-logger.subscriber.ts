import { EventSubscriber, DataSource, Subscriber } from 'typeorm';

/**
 * TypeORM subscriber that logs migration execution for diagnostics.
 * Logs:
 * - Migrations discovered
 * - Migrations executed
 * - Connection events
 */
@EventSubscriber()
export class MigrationLoggerSubscriber {
  // Track migration state
  private migrationsDiscovered = 0;
  private migrationsExecuted: string[] = [];

  /**
   * Called after the DataSource is initialized.
   */
  afterDataSourceInit?(dataSource: DataSource): void {
    const isPostgres = dataSource.options.type === 'postgres';
    
    console.log('');
    console.log('╔═══════════════════════════════════════════════════════════════════════╗');
    console.log('║                     TYPEORM INITIALIZED                            ║');
    console.log('╚═══════════════════════════════════════════════════════════════════════╝');
    console.log(`  Connection name: ${dataSource.name}`);
    console.log(`  Database type:   ${dataSource.options.type}`);
    console.log(`  Database:       ${dataSource.options.database || '(default)'}`);
    if (isPostgres && dataSource.options.host) {
      console.log(`  Host:           ${dataSource.options.host}:${dataSource.options.port || 5432}`);
    }
    
    // Log migrations
    if (dataSource.migrations?.length) {
      this.migrationsDiscovered = dataSource.migrations.length;
      console.log(`  Migrations discovered: ${this.migrationsDiscovered}`);
      console.log('  Migration list:');
      for (const m of dataSource.migrations.slice(0, 10)) {
        console.log(`    - ${m.name}`);
      }
      if (dataSource.migrations.length > 10) {
        console.log(`    ... and ${dataSource.migrations.length - 10} more`);
      }
    } else {
      console.log('  Migrations discovered: 0');
    }
    
    console.log('═══════════════════════════════════════════════════════════════════════');
    console.log('');
  }
}
