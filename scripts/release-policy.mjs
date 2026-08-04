import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import process from "node:process";

const root = new URL("../", import.meta.url);
const read = (path) => readFileSync(new URL(path, root), "utf8");
const readJSON = (path) => JSON.parse(read(path));
const fail = (message) => {
  console.error(`Release policy failed: ${message}`);
  process.exitCode = 1;
};

const release = readJSON("release.json");
const versionMatch = /^(\d+\.\d+\.\d+)-beta\.(\d+)$/.exec(release.version);

if (!versionMatch) {
  fail(`release.json version must look like 0.2.0-beta.6, received ${release.version}`);
} else {
  const [, marketingVersion, betaNumber] = versionMatch;
  if (release.marketingVersion !== marketingVersion) {
    fail(`marketingVersion must be ${marketingVersion}`);
  }
  if (release.buildNumber !== Number(betaNumber)) {
    fail(`buildNumber must match the beta number (${betaNumber})`);
  }
}

const rootPackage = readJSON("package.json");
const webPackage = readJSON("WebApp/package.json");
const webLock = readJSON("WebApp/package-lock.json");
const releaseSource = read("WebApp/app/release.ts");
const project = read("AppleMobileApp.xcodeproj/project.pbxproj");
const readme = read("README.md");
const history = read("RELEASES.md");

for (const [label, actual] of [
  ["root package", rootPackage.version],
  ["web package", webPackage.version],
  ["web package lock", webLock.version],
  ["web package lock root", webLock.packages?.[""]?.version],
]) {
  if (actual !== release.version) {
    fail(`${label} is ${actual}; expected ${release.version}`);
  }
}

if (!releaseSource.includes(`ASITRA_RELEASE = "${release.version}"`)) {
  fail("WebApp/app/release.ts does not match release.json");
}

const marketingVersions = [...project.matchAll(/MARKETING_VERSION = ([^;]+);/g)].map((match) => match[1]);
const buildNumbers = [...project.matchAll(/CURRENT_PROJECT_VERSION = ([^;]+);/g)].map((match) => match[1]);

if (marketingVersions.length === 0 || marketingVersions.some((value) => value !== release.marketingVersion)) {
  fail(`all Apple marketing versions must be ${release.marketingVersion}`);
}
if (buildNumbers.length === 0 || buildNumbers.some((value) => value !== String(release.buildNumber))) {
  fail(`all Apple build numbers must be ${release.buildNumber}`);
}
if (!readme.includes(`current beta is version **${release.version} (${release.buildNumber})**`)) {
  fail("README current beta does not match release.json");
}

const heading = `## ${release.version} — ${release.releasedAt}`;
const headingIndex = history.indexOf(heading);
if (headingIndex < 0) {
  fail(`RELEASES.md is missing ${heading}`);
}

const baseSha = process.env.RELEASE_BASE_SHA?.trim();
const headBranch = process.env.RELEASE_HEAD_BRANCH?.trim();
const pullRequest = process.env.RELEASE_PR_NUMBER?.trim();

if (baseSha) {
  const changedFiles = execFileSync("git", ["diff", "--name-only", `${baseSha}...HEAD`], {
    cwd: new URL(".", root),
    encoding: "utf8",
  }).trim().split("\n").filter(Boolean);

  const productChanged = changedFiles.some((path) =>
    path.startsWith("AppleMobileApp/") ||
    path.startsWith("Packages/") ||
    path.startsWith("WebApp/app/") ||
    path.startsWith("WebApp/db/") ||
    path.startsWith("WebApp/drizzle/") ||
    path.startsWith("WebApp/public/")
  );

  const traceRequired = productChanged || changedFiles.includes("release.json");

  if (traceRequired) {
    for (const required of ["release.json", "RELEASES.md"]) {
      if (!changedFiles.includes(required)) {
        fail(`feature changes require updating ${required}`);
      }
    }

    let baseRelease;
    try {
      baseRelease = JSON.parse(execFileSync("git", ["show", `${baseSha}:release.json`], {
        cwd: new URL(".", root),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }));
    } catch {
      // The first governance PR introduces the canonical manifest.
    }
    if (baseRelease?.version === release.version) {
      fail(`feature changes must bump the release beyond ${baseRelease.version}`);
    }

    const nextHeading = history.indexOf("\n## ", headingIndex + heading.length);
    const currentEntry = history.slice(headingIndex, nextHeading < 0 ? undefined : nextHeading);
    if (headBranch && !currentEntry.includes(`\`${headBranch}\``)) {
      fail(`the ${release.version} entry must record branch ${headBranch}`);
    }
    if (pullRequest && !currentEntry.includes(`[#${pullRequest}]`)) {
      fail(`the ${release.version} entry must link pull request #${pullRequest}`);
    }
  }
}

if (!process.exitCode) {
  console.log(`Release policy passed for ${release.version}.`);
}
