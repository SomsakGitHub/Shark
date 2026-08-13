import { readFile } from 'node:fs/promises';
import { neon } from '@neondatabase/serverless';

const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL not set');
  process.exit(1);
}

const schema = await readFile(new URL('../schema.sql', import.meta.url), 'utf8');

const statements = schema
  .split(/;\s*(?:\r?\n|$)/)
  .map((s) => s.trim())
  .filter((s) => s.length > 0 && !s.startsWith('--'));

const db = neon(url);
for (const statement of statements) {
  try {
    await db(statement);
    console.log(`ok: ${statement.split('\n')[0].trim().slice(0, 80)}`);
  } catch (err) {
    console.error(`failed: ${statement.slice(0, 80)}\n${err.message}`);
    process.exitCode = 1;
  }
}

if (!process.exitCode) console.log('Schema applied.');
