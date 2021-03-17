const path = require("path");
const os = require("os");
const fs = require("fs");
const rimraf = require("rimraf");
const {
  latestResolvableVersions,
} = require("../../lib/npm/subdependency-version-resolver");
const helpers = require("./helpers");

describe("sub-dependency version resolver", () => {
  let tempDir;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => rimraf.sync(tempDir));

  it("returns updated dependency", async () => {
    helpers.copyDependencies(
      "subdependency-version-resolver/v2-lockfile",
      tempDir
    );

    const result = await latestResolvableVersions(tempDir, [
      {
        name: "kind-of",
        version: "3.2.2",
        target_version: "6.0.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }],
      },
    ]);

    expect(result).toEqual([
      {
        name: "kind-of",
        version: "4.0.0",
      },
      {
        name: "kind-of",
        version: "3.2.2",
      },
      {
        name: "kind-of",
        version: "5.1.0",
      },
      {
        name: "kind-of",
        version: "6.0.3",
      },
    ]);
  }, 30000);

  fit("returns updated dependency v2", async () => {
    helpers.copyDependencies(
      "subdependency-version-resolver/v2-lockfile",
      tempDir
    );

    const result = await latestResolvableVersions(tempDir, [
      {
        name: "kind-of",
        version: "3.2.2",
        target_version: "6.0.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }],
      },
    ]);

    expect(result).toEqual([
      {
        name: "kind-of",
        version: "4.0.0",
      },
      {
        name: "kind-of",
        version: "3.2.2",
      },
      {
        name: "kind-of",
        version: "5.1.0",
      },
      {
        name: "kind-of",
        version: "6.0.3",
      },
    ]);
  }, 6000);
});
