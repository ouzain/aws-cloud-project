import { cpSync, mkdirSync, rmSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
execFileSync('npm', ['ci', '--prefix', path.join(root, 'app'), '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'], { stdio: 'inherit' });
const target = path.join(root, '.build/runtime');
rmSync(target, { recursive: true, force: true });
mkdirSync(target, { recursive: true });
for (const folder of ['app', 'shared', 'sql', 'catalog', 'certs', 'modules/messaging/lambda']) {
  cpSync(path.join(root, folder), path.join(target, folder), {
    recursive: true, filter: (source) => !source.split(path.sep).includes('node_modules'),
  });
}
cpSync(path.join(root, 'app/node_modules'), path.join(target, 'node_modules'), { recursive: true });
for (const file of ['package.json', 'package-lock.json']) cpSync(path.join(root, 'app', file), path.join(target, file));
if (!existsSync(path.join(target, 'certs/global-bundle.pem'))) throw new Error("Le bundle de certificats RDS est absent.");
console.log("Paquet de déploiement commun EC2 et Lambda compilé.");
