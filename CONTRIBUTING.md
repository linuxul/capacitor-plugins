# Contributing

See [`CONTRIBUTING.md`](https://github.com/ionic-team/capacitor/blob/HEAD/CONTRIBUTING.md) in the Capacitor repo for more general contribution guidelines.

## Developing Capacitor Plugins

### Local Setup

1. Fork and clone this repo.
2. Install the monorepo dependencies.

    ```shell
    npm install
    ```

3. Install SwiftLint if you're on macOS. Contributions to iOS code will be linted in CI if you don't have macOS.

    ```shell
    brew install swiftlint
    ```

4. Install ktlint to lint and format the Kotlin code.

    ```shell
    brew install ktlint
    ```

These plugins are built for a fork of Capacitor whose runtimes are written in Kotlin and Swift, and they do not compile against the `@capacitor/android` and `@capacitor/ios` packages on npm. The fork is not published to npm; each plugin's `devDependencies` install its packages from the tarballs attached to a release of [linuxul/capacitor](https://github.com/linuxul/capacitor/releases), so `npm install` is enough to verify against that release. To verify against unreleased changes of the fork, point the plugins at a checkout of it instead:

5. Follow the fork's local setup instructions in its `CONTRIBUTING.md`.
6. Toggle each plugin to use your local copy of Capacitor. Pass the path to the checkout unless it is a sibling directory named `capacitor`.

    ```shell
    npm install
    npm run toggle-local -- ../path/to/capacitor
    npm run set-settings-gradle-for-monorepo
    ```

    :bulb: *Remember not to commit unnecessary changes to `package.json` and `package-lock.json`.*

7. Make sure your app is using local copies of the Capacitor plugin and Capacitor core.

    ```shell
    cd my-app/
    npm install ../path/to/capacitor-plugins/<plugin>
    npm install ../path/to/capacitor/core
    npm install ../path/to/capacitor/android
    npm install ../path/to/capacitor/ios
    ```

### Verifying a Plugin

Each plugin has the same scripts. Run them from the plugin's directory:

```shell
npm run lint             # ESLint, Prettier, SwiftLint and ktlint; `npm run fmt` fixes what can be fixed
npm run verify:android   # Gradle build and unit tests against the Kotlin runtime
npm run verify:ios       # xcodebuild against the Swift runtime
npm run verify:web
```

`verify:ios` builds the plugin's Swift package on its own. In an app, the plugin's `capacitor-swift-pm` dependency is replaced by the `@capacitor/ios` that the app installed; for a standalone build the package reads the runtime's location from `CAPACITOR_IOS_PATH`, which the script sets to the installed `@capacitor/ios`. Set the variable yourself to build against another checkout, and leave it unset when building an app.

### Monorepo Scripts

To aid in managing these plugins, this repo has a variety of scripts (located in `scripts/`) that can be run with `npm`.

#### `npm run set-capacitor-version "<version>"`

This script is for setting the version (or version range) of Capacitor packages in each plugin's `package.json`.

#### `npm run toggle-local`

This script is for switching between Capacitor packages from the fork's release tarballs and Capacitor packages installed locally. It takes the path to the Capacitor checkout, `npm run toggle-local -- ../path/to/capacitor`, and defaults to a sibling directory named `capacitor`. Run it again to switch back.

> If you get npm errors, you can try installing from scratch:
>
> 1. Reset the changes in `package.json` files.
> 1. Clear out all `node_modules`.
>
>     ```shell
>     npx lerna exec 'rm -fr package-lock.json && rm -fr node_modules'
>     rm -fr node_modules
>     ```
> 1. Install with local dependencies:
>
>     ```
>     npm run toggle-local -- ../path/to/capacitor
>     ```

#### `npm run apply-patches "<package>"`

This script is for copying git changes from one plugin to all plugins.

To use:

1. Make sure your staging area is clean, e.g. `git reset`
1. Stage the changes from (and only from) your package, e.g. `git add -p -- text-zoom/`
1. Run the script with `<package>` being the npm name of your package, e.g. `npm run apply-patches @capacitor/text-zoom`
