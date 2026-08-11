/**
 * Resolves the worker script path.
 * In browsers (WPT), it uses a path relative to the current script URL.
 * In JS shells, it attempts to build a path relative to the script's location
 * provided in the command-line arguments, with a fallback for this repo.
 */
function getWorkerPath(scriptName) {
  // 1. Browser/WPT detection.
  if (typeof location !== 'undefined') {
    return scriptName;
  }

  // 2. JS shell detection (using the script path from command-line arguments).
  try {
    if (typeof arguments !== 'undefined' && arguments.length > 0) {
      const lastArg = arguments[arguments.length - 1];
      if (lastArg.includes('/')) {
        return lastArg.substring(0, lastArg.lastIndexOf('/') + 1) + scriptName;
      }
    }
  } catch (e) {
    // Fallback if arguments is not available or mapping fails.
  }

  // 3. Fallback for the current repo root.
  return 'test/js-api/memory/' + scriptName;
}
