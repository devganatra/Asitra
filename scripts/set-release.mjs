import { readFileSync, writeFileSync } from "node:fs";
import process from "node:process";

const nextVersion = process.argv[2];
const match = /^(\d+\.\d+\.\d+)-beta\.(\d+)$/.exec(nextVersion ?? "");

if (!match) {
  console.error("Usage: npm run release:set -- 0.2.0-beta.7");
  process.exit(1);
}

const root = new URL("../", import.meta.url);
const read = (path) => readFileSync(new URL(path, root), "utf8");
const write = (path, contents) => writeFileSync(new URL(path, root), contents);
const readJSON = (path) => JSON.parse(read(path));
const writeJSON = (path, value) => write(path, `${JSON.stringify(value, null, 2)}\n`);
const [, marketingVersion, betaNumber] = match;
const buildNumber = Number(betaNumber);

const release = readJSON("release.json");
release.version = nextVersion;
release.marketingVersion = marketingVersion;
release.buildNumber = buildNumber;
release.releasedAt = new Date().toISOString().slice(0, 10);
writeJSON("release.json", release);

for (const path of ["package.json", "WebApp/package.json"]) {
  const packageFile = readJSON(path);
  packageFile.version = nextVersion;
  writeJSON(path, packageFile);
}

const lock = readJSON("WebApp/package-lock.json");
lock.version = nextVersion;
lock.packages[""].version = nextVersion;
writeJSON("WebApp/package-lock.json", lock);

write(
  "WebApp/app/release.ts",
  read("WebApp/app/release.ts").replace(/ASITRA_RELEASE = "[^"]+"/, `ASITRA_RELEASE = "${nextVersion}"`),
);
write(
  "AppleMobileApp.xcodeproj/project.pbxproj",
  read("AppleMobileApp.xcodeproj/project.pbxproj")
    .replace(/CURRENT_PROJECT_VERSION = [^;]+;/g, `CURRENT_PROJECT_VERSION = ${buildNumber};`)
    .replace(/MARKETING_VERSION = [^;]+;/g, `MARKETING_VERSION = ${marketingVersion};`),
);
write(
  "README.md",
  read("README.md").replace(
    /current beta is version \*\*[^*]+\*\*/,
    `current beta is version **${nextVersion} (${buildNumber})**`,
  ),
);

console.log(`Synchronized Asitra ${nextVersion} across web and Apple.`);
console.log("Next: add the release, branch, pull request, platforms, and changes to RELEASES.md.");
