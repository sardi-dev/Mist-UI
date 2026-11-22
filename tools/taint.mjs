#!/usr/bin/env node
// Usage: node tools/taint.mjs [<taint.log or the Logs folder that holds it>]
// Lists the blocked actions and tainted globals that MistUI or MistUI_Options
// caused, grouped, most frequent first, with the addon file and line from the
// stack. Without an argument the path comes from the MISTUI_TAINT_LOG
// environment variable. Needs the client's taint log to be switched on
// (/console taintLog 1 in the 5.4.8 client).

import { existsSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { formatTaintReport, parseTaintLog, summarizeTaint } from './lib/taintlog.mjs';

const REPORTED_ADDONS = ['MistUI', 'MistUI_Options'];
const LOG_FILE_NAME = 'taint.log';
const ENV_VARIABLE = 'MISTUI_TAINT_LOG';
const EXIT_FAILED = 1;
const EXIT_USAGE = 2;

function usage() {
  return [
    'Usage: npm run taint -- [<path to taint.log or to the Logs folder>]',
    `Without a path the ${ENV_VARIABLE} environment variable is used.`,
  ].join('\n');
}

function main(argv) {
  const target = argv[0] ?? process.env[ENV_VARIABLE];
  if (!target) {
    console.log(usage());
    process.exitCode = EXIT_USAGE;
    return;
  }
  const file = existsSync(target) && statSync(target).isDirectory() ? join(target, LOG_FILE_NAME) : target;
  if (!existsSync(file)) {
    console.error(`Taint log not found: ${file}`);
    process.exitCode = EXIT_FAILED;
    return;
  }
  const groups = summarizeTaint(parseTaintLog(readFileSync(file, 'utf8')), REPORTED_ADDONS);
  console.log(formatTaintReport(groups));
}

main(process.argv.slice(2));
