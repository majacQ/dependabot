const npm = require("npm7");
const Arborist = require("@npmcli/arborist");
const semver = require("semver");
const { muteStderr, runAsync } = require("./helpers.js");

async function latestResolvableVersions(directory, dependencies) {
  // Load npm config and populate flatOptions
  await new Promise((resolve) => {
    npm.load(resolve);
  });

  const arb = new Arborist({
    ...npm.flatOptions,
    path: directory,
    packageLockOnly: true,
  });

  const depName = dependencies[0].name;
  const targetVersion = dependencies[0].target_version;
  try {
    await arb.reify({ update: [`${depName}@${targetVersion}`] });
  } catch (err) {
    debugger;
  }

  return await arb.loadVirtual().then((tree) => {
    const resolved = new Map();
    for (const node of tree.inventory.query("name", depName)) {
      const key = [node.name, node.version].join("@");
      resolved.set(key, {
        name: node.name,
        version: node.version,
      });
    }
    return Array.from(resolved.values());
  });
}

module.exports = { latestResolvableVersions };
