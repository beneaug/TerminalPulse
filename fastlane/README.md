fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload App Store screenshots only

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload App Store text metadata only (description, keywords, what's new, URLs, review info) for all locales

### ios upload_listing

```sh
[bundle exec] fastlane ios upload_listing
```

Upload both metadata and screenshots in one shot

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
