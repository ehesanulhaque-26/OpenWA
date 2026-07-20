import * as fs from 'fs';
import { writeFileSync, chmodSync, mkdirSync } from 'fs';
import { dirname } from 'path';

/**
 * Write a secret file (e.g. the generated `.env`, the raw admin key) with owner-only permissions.
 *
 * `writeFileSync`'s `mode` is honored only when the file is CREATED — on an overwrite it keeps the
 * existing permissions. So we chmod to 0o600 BEFORE writing too: if the file already exists with
 * looser perms, the new secret content is never briefly world-readable during the rewrite. The
 * post-write chmod is a backstop. Both chmods are best-effort (a mount that can't chmod, or an
 * absent file on the pre-write call, shouldn't break the write — create-mode covers new files).
 */
export function writeSecretFile(filePath: string, content: string): void {
  // Ensure parent directory exists (Railway and some Docker setups may need this)
  const dir = dirname(filePath);
  if (!fs.existsSync(dir)) {
    try {
      mkdirSync(dir, { recursive: true, mode: 0o755 });
    } catch (mkdirError) {
      // Best-effort - may fail on read-only filesystems
      console.warn(`[OpenWA] Could not create directory ${dir}: ${(mkdirError as Error).message}`);
    }
  }

  try {
    chmodSync(filePath, 0o600);
  } catch (error) {
    // file not present yet, or chmod unsupported — create-mode below covers a new file. Log the
    // failure so a world-readable secret on a chmod-unsupported FS (or an unexpected error) is
    // not silently left world-readable after a rewrite.
    console.warn(`[OpenWA] pre-write chmod 0o600 failed for ${filePath}: ${(error as Error).message}`);
  }
  writeFileSync(filePath, content, { mode: 0o600 });
  try {
    chmodSync(filePath, 0o600);
  } catch (error) {
    console.warn(`[OpenWA] post-write chmod 0o600 failed for ${filePath}: ${(error as Error).message}`);
  }
}
