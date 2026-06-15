import pg from 'pg';
import readline from 'readline';

const { Client } = pg;

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

const question = (query: string): Promise<string> => 
  new Promise((resolve) => rl.question(query, resolve));

async function runInteractive() {
  console.log('\n=============================================');
  console.log('🤖 Hybrid Delta-Sync Database Migration Tool');
  console.log('=============================================\n');

  console.log('--- SOURCE DATABASE (OLD) ---');
  
  let oldHost = '';
  while (!oldHost) {
    oldHost = await question('1. Database Host (e.g. adesanta52.my.id): ');
    oldHost = oldHost.trim();
  }

  const oldPortInput = await question('2. Port (press Enter for 5432): ');
  const oldPort = oldPortInput.trim() || '5432';

  const oldUserInput = await question('3. Username (press Enter for "postgres"): ');
  const oldUser = oldUserInput.trim() || 'postgres';

  let oldPassword = '';
  while (!oldPassword) {
    oldPassword = await question('4. Password: ');
    oldPassword = oldPassword.trim();
  }

  let oldDbInput = await question('5. Database Name: ');
  const oldDb = oldDbInput.trim() || 'postgres';
  
  const oldSchemaInput = await question('6. Schema Name (press Enter for "adoetzgpt"): ');
  const oldSchemaName = oldSchemaInput.trim() || 'adoetzgpt';

  console.log('\n--- TARGET DESTINATION (NEW) ---');
  
  const newHostInput = await question(`7. Database Host (press Enter to keep "${oldHost}"): `);
  const newHost = newHostInput.trim() || oldHost;

  const newPortInput = await question(`8. Port (press Enter to keep "${oldPort}"): `);
  const newPort = newPortInput.trim() || oldPort;

  const newUserInput = await question(`9. Username (press Enter to keep "${oldUser}"): `);
  const newUser = newUserInput.trim() || oldUser;

  const newPasswordInput = await question(`10. Password (press Enter to keep same as old password): `);
  const newPassword = newPasswordInput.trim() || oldPassword;

  let newDbInput = await question(`11. Database Name (press Enter to keep "${oldDb}"): `);
  const newDb = newDbInput.trim() || oldDb;

  const newSchemaInput = await question(`12. Schema Name (press Enter for "adoetzgpt"): `);
  const newSchemaName = newSchemaInput.trim() || 'adoetzgpt';

  rl.close();

  const encOldUser = encodeURIComponent(oldUser);
  const encOldPass = encodeURIComponent(oldPassword);
  const oldUrl = `postgres://${encOldUser}:${encOldPass}@${oldHost}:${oldPort}/${oldDb}`;

  const encNewUser = encodeURIComponent(newUser);
  const encNewPass = encodeURIComponent(newPassword);
  const newUrl = `postgres://${encNewUser}:${encNewPass}@${newHost}:${newPort}/${newDb}`;

  console.log(`\nStarting migration...`);
  console.log(` FROM: [Host: ${oldHost}] [DB: ${oldDb}] [User: ${oldUser}] [Schema: ${oldSchemaName}]`);
  console.log(`   TO: [Host: ${newHost}] [DB: ${newDb}] [User: ${newUser}] [Schema: ${newSchemaName}]\n`);
  
  await migrate(oldUrl, oldSchemaName, newUrl, newSchemaName);
}

async function migrate(oldUrl: string, oldSchemaName: string, newUrl: string, newSchemaName: string) {
  
  const isSameDatabase = oldUrl === newUrl;
  
  console.log(`Connecting to OLD database...`);
  const oldClient = new Client({
    connectionString: oldUrl,
    ssl: oldUrl.includes('supabase') || oldUrl.includes('neon.tech') || oldUrl.includes('my.id')
        ? { rejectUnauthorized: false } 
        : undefined,
  });

  const newClient = isSameDatabase ? oldClient : new Client({
    connectionString: newUrl,
    ssl: newUrl.includes('supabase') || newUrl.includes('neon.tech') || newUrl.includes('my.id')
        ? { rejectUnauthorized: false } 
        : undefined,
  });

  try {
    await oldClient.connect();
    if (!isSameDatabase) {
      console.log('Connecting to NEW database...');
      await newClient.connect();
    }
    console.log('✅ Successfully connected to database(s)!');

    const oldSchema = `"${oldSchemaName}"`;
    const newSchema = `"${newSchemaName}"`;

    await newClient.query(`CREATE SCHEMA IF NOT EXISTS ${newSchema}`);

    console.log(`\nReading old data from ${oldSchema}.app_states...`);
    const result = await oldClient.query(`SELECT user_id, state FROM ${oldSchema}.app_states`);
    
    console.log(`Found ${result.rowCount} users to migrate.`);

    for (const row of result.rows) {
      const userId = row.user_id;
      const state = row.state || {};

      console.log(`\nMigrating data for user ${userId}...`);

      const settings = { ...state };
      delete settings.sessions;

      await newClient.query('BEGIN');

      await newClient.query(`
        CREATE TABLE IF NOT EXISTS ${newSchema}.users (
          id TEXT PRIMARY KEY,
          username TEXT NOT NULL UNIQUE,
          email TEXT UNIQUE,
          display_name TEXT NOT NULL,
          password_hash TEXT NOT NULL,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      `);

      await newClient.query(`
        CREATE TABLE IF NOT EXISTS ${newSchema}.user_settings (
          user_id TEXT PRIMARY KEY REFERENCES ${newSchema}.users(id) ON DELETE CASCADE,
          state JSONB NOT NULL DEFAULT '{}'::jsonb,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      `);
      
      await newClient.query(`
        CREATE TABLE IF NOT EXISTS ${newSchema}.chat_sessions (
          id TEXT PRIMARY KEY,
          user_id TEXT REFERENCES ${newSchema}.users(id) ON DELETE CASCADE,
          session JSONB NOT NULL DEFAULT '{}'::jsonb,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      `);

      // We must fetch the user's profile from the OLD DB to copy it to the NEW DB/Schema
      const userRow = await oldClient.query(`SELECT * FROM ${oldSchema}.users WHERE id = $1`, [userId]);
      if (userRow.rows.length > 0) {
        const u = userRow.rows[0];
        await newClient.query(
          `INSERT INTO ${newSchema}.users (id, username, email, display_name, password_hash)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (id) DO NOTHING`,
          [u.id, u.username, u.email, u.display_name, u.password_hash]
        );
      }

      // 1. Insert User Settings into NEW DB
      await newClient.query(
        `INSERT INTO ${newSchema}.user_settings (user_id, state, updated_at) 
         VALUES ($1, $2::jsonb, NOW()) 
         ON CONFLICT (user_id) DO UPDATE SET state = EXCLUDED.state, updated_at = NOW()`,
        [userId, JSON.stringify(settings)]
      );

      // 2. Insert Chat Sessions Individually into NEW DB
      if (Array.isArray(state.sessions)) {
        for (const session of state.sessions) {
          if (!session.id) continue;
          await newClient.query(
            `INSERT INTO ${newSchema}.chat_sessions (id, user_id, session, updated_at) 
             VALUES ($1, $2, $3::jsonb, NOW()) 
             ON CONFLICT (id) DO UPDATE SET session = EXCLUDED.session, updated_at = NOW()`,
            [session.id, userId, JSON.stringify(session)]
          );
        }
        console.log(` -> Migrated ${state.sessions.length} chats for user ${userId}.`);
      }

      await newClient.query('COMMIT');
    }

    console.log(`\n✅ MIGRATION COMPLETE! Data successfully migrated!`);

  } catch (error) {
    console.error('\n❌ Migration failed:', error);
    await newClient.query('ROLLBACK').catch(() => {});
  } finally {
    await oldClient.end();
    if (!isSameDatabase) await newClient.end();
  }
}

runInteractive().catch(console.error);
