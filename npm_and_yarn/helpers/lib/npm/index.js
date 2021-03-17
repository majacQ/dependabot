const updater = require("./updater");
const peerDependencyChecker = require("./peer-dependency-checker");
const subdependencyUpdater = require("./subdependency-updater");
const subdependencyVersionResolver = require("./subdependency-version-resolver");
const conflictingDependencyParser = require("./conflicting-dependency-parser");

module.exports = {
  update: updater.updateDependencyFiles,
  updateSubdependency: subdependencyUpdater.updateDependencyFile,
  subdependencyVersionResolver:
    subdependencyVersionResolver.latestResolvableVersions,
  checkPeerDependencies: peerDependencyChecker.checkPeerDependencies,
  findConflictingDependencies:
    conflictingDependencyParser.findConflictingDependencies,
};
