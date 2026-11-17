// Release checks and the contents of a release zip. The zip holds the two addon folders as
// committed (never the git-ignored artwork) plus the artwork manifest the install script reads.

import { parseToc } from './loadlist.mjs';

export const ADDONS = ['MistUI', 'MistUI_Options'];
export const MANIFEST_IN_ZIP = 'MistUI/art-manifest.json';

const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;

/**
 * @param {Record<string, string>} tocTexts addon name -> .toc file text
 * @param {string} changelogText CHANGELOG.md
 * @param {{ allowPrerelease?: boolean }} [options]
 * @returns {{ version: string, problems: string[] }}
 */
export function checkRelease(tocTexts, changelogText, options = {}) {
  const problems = [];
  const versions = ADDONS.map((name) => {
    const text = tocTexts[name];
    if (text === undefined) {
      problems.push(`${name}.toc is missing`);
      return undefined;
    }
    const version = parseToc(text).meta.Version;
    if (!version) problems.push(`${name}.toc has no Version line`);
    return version;
  });
  const version = versions[0];
  if (versions.some((v) => v !== version)) {
    problems.push(`the .toc versions differ: ${versions.join(', ')}`);
  }
  if (version && !SEMVER.test(version)) problems.push(`version ${version} is not MAJOR.MINOR.PATCH`);
  if (version && version.includes('-') && !options.allowPrerelease) {
    problems.push(`version ${version} is a pre-release (pass --pre to build it anyway)`);
  }
  if (version && !version.includes('-') && !changelogText.includes(`## [${version}]`)) {
    problems.push(`CHANGELOG.md has no "## [${version}]" section`);
  }
  return { version: version ?? '', problems };
}

/** Name of the zip for a version. */
export function zipName(version) {
  return `MistUI-${version}.zip`;
}
