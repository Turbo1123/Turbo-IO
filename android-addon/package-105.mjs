// Compatibility CLI; resource helpers remain importable without running a build.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
export * from './package-resources.mjs';
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) await import('./package.mjs');
