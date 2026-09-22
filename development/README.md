# Fedora development apps and tools

A portable development setup based on the Fedora 44 x86_64 workstation inspected
on **2026-09-22**. Follow the sections needed by your project. All example paths
use your own home directory; no Aeris desktop profile or restore script is needed.

This is a setup recipe and observed inventory, not a complete machine image.
Fedora packages and application releases move over time. Project manifests,
lockfiles, SDK pins, and CI configuration take precedence over the snapshot below.
Record the versions and download checksums you actually install in your project's
onboarding documentation. Installation commands here were reviewed, not executed
on a clean Fedora machine during this documentation pass.

## Start here: Community Codex

Community Codex is the first app in this workflow. The community project is
[ilysenko/codex-desktop-linux](https://github.com/ilysenko/codex-desktop-linux),
currently displayed as **ChatGPT Community** in the application menu, with the
command/package name `codex-desktop`.

On a regular Fedora install, download or clone this settings repository, open a
terminal in its root, and run:

```bash
./scripts/install-community-codex.sh --dry-run
./scripts/install-community-codex.sh
```

Run as your normal user, with sudo access for packages. Close existing Codex or
ChatGPT desktop apps first. The helper installs Git, Make, Rust and Cargo, clones
the community source into `$HOME/.local/share/codex-community/source`, prints its
Git revision, then runs upstream's `make bootstrap-native` to install the remaining
dependencies, build and install an RPM. It requires network access and build disk
space; this is a local build, not an instant binary download.

It uses upstream's default feature selection without copying our personal
settings. Upstream resolves and verifies the current signed application payload;
the observed package version below is an inventory entry, not an installer pin.
Retain the printed source revision and upstream build metadata when recording
your installation. See the community
[native setup guide](https://github.com/ilysenko/codex-desktop-linux/blob/main/docs/native-setup.md).

The helper refuses existing checkout paths, including partial failed clones.
Inspect a failed checkout before retrying; choose a new absolute path with
`CODEX_COMMUNITY_DIR` if needed. It does not overwrite or reset existing source.
Fedora Atomic is excluded; use upstream's documented AppImage/container flow.

After installation:

```bash
rpm -q codex-desktop
codex-desktop --diagnose
codex-desktop
```

Sign in with your own account, open the project folder, and use its README and
the sections below to set up the required toolchain. No personal account state,
plugins, model configuration, or Aeris settings are copied. For later updates,
use the community app's updater or follow its native update instructions; this
helper is for initial setup. Optional community features can be selected later
with upstream's `make setup-native` followed by `make install-native` in the
retained checkout.

## Apps and observed versions

| Area | Installed app/tool on 2026-09-22 | Purpose / install route |
| --- | --- | --- |
| Entry point | Community Codex / ChatGPT Community, `codex-desktop` 2026.09.13.100451 | Community native RPM; start here, then set up project tools |
| Editor | VS Code 1.138.0; Dart and Flutter extensions 3.142.0 | Native Linux archive; editor and debugger |
| Flutter | Flutter 3.47.2, Dart 3.13.2 | User-owned SDK; mobile and web development |
| Android | Command-line Tools 22.0, Platform-Tools 37.0.1, Emulator 37.1.11 | Google's SDK tools; Android Studio is optional and was not found in this inventory |
| Java | Temurin JDK 21.0.12.1 | Explicit Android build JDK; the system Java is OpenJDK 25 |
| Device display | scrcpy 4.1; Scrcpy GUI 1.4.18 | Upstream Linux binary / AppImage; device mirroring and control |
| PHP | mise 2026.9.0, PHP 8.3.33, Composer 2.10.3 | mise's `jdx/vfox-php` plugin; select a runtime per project |
| Web | Node 22.23.1, npm 10.9.8 | Fedora `nodejs22` packages; honor each project's runtime and package manager |
| Containers | Podman 5.8.4; Podman Desktop 1.29.3 | Fedora package + Flathub desktop app |
| Databases | Tabularis 0.22.0; MariaDB 11.8.8; SQLite 3.51.2 | Database GUI AppImage; host database packages only where needed |
| Supabase | CLI 2.116.0 | Optional for Supabase projects; upstream release or pinned project dependency |
| General development | Git 2.55.0, GitHub CLI 2.97.0, Python 3.14.7, uv 0.12.9, Rust 1.98.0 | Fedora tools plus user-owned uv/rustup |
| Browser | Google Chrome 152.0.7977.82 | Native browser for web debugging; choose the browser your tests target |

PHP and Composer are installed but **not selected globally**. Running `php` from
an unconfigured directory fails with a mise “No version is set” message. This is
resolved by project runtime selection, not by changing Composer requirements.
Docker Engine/Compose were not found; Podman availability does not prove a
Docker-specific development stack works. No standalone FVM, pnpm, or yarn install
was verified (an agent-bundled pnpm is not a workstation dependency).

## 1. Base packages and workspace

On Fedora with DNF5:

```bash
cat /etc/fedora-release
uname -m
sudo dnf install git git-lfs gh openssh-clients curl wget rsync jq unzip zip tar xz \
  make gcc gcc-c++ clang cmake ninja-build pkgconf-pkg-config \
  python3 python3-pip mesa-libGLU
git lfs install
mkdir -p "$HOME/Projects" "$HOME/SDKs" "$HOME/.local/bin"
```

Use a Linux-native filesystem for checkouts. Set your own Git name/email and
authenticate your own account; do not apply this repository's personal Git
identity script. Clone repositories and reconstruct dependencies from lockfiles.
Keep signing keys, `.env` files, SSH keys, and database credentials outside this
setup repository. Copy `.env.example` only into a new local environment.

## 2. VS Code and browser

Install the native Linux x64 archive or Fedora RPM using the official
[VS Code Linux instructions](https://code.visualstudio.com/docs/setup/linux).
For an archive installation, extract into a versioned directory under
`$HOME/Applications`, add its `bin` directory to `PATH`, and check `code --version`.
For the observed version, use the vendor's
[1.138.0 Linux x64 archive](https://update.code.visualstudio.com/1.138.0/linux-x64/stable).

```bash
code --install-extension Dart-Code.dart-code@3.142.0
code --install-extension Dart-Code.flutter@3.142.0
code --list-extensions --show-versions
```

Other extensions are project-specific. Install Remote - SSH only for a project
that needs it; configure your own host and key. Do not copy another developer's
editor profile, SSH configuration, or server history. Install your test browser
from its vendor; for Chrome use the Linux RPM from the
[Chrome download page](https://www.google.com/chrome/).

## 3. Flutter and Android

Download your project's pinned Linux SDK from the
[Flutter SDK archive](https://docs.flutter.dev/install/archive) and follow the
[manual setup](https://docs.flutter.dev/install/manual). Extract it into a
user-owned folder such as `$HOME/SDKs/flutter-3.47.2`; the archive's inner
`flutter/` folder should become that directory. Never run Flutter with sudo.

Install a JDK 21 using [Adoptium's distribution](https://adoptium.net/installation/linux)
or Fedora's `java-21-openjdk-devel` when available. For the archive route, extract
the JDK into `$HOME/SDKs/jdk-21`. Older projects may require a different JDK;
preserve their Gradle wrapper and Android Gradle Plugin compatibility.

Download Google's Linux **Command line tools only** from the
[Android Studio downloads page](https://developer.android.com/studio#command-tools).
Extract so that `sdkmanager` is at
`$HOME/Android/Sdk/cmdline-tools/latest/bin/sdkmanager` (avoid a doubled
`cmdline-tools/cmdline-tools` directory). Android Studio's SDK Manager is an
alternative if you prefer a full IDE.

For this example layout, add once to your shell configuration, then reopen the
terminal and editor:

```bash
export JAVA_HOME="$HOME/SDKs/jdk-21"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$HOME/.local/bin:$HOME/SDKs/flutter-3.47.2/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

Use the actual JDK path if you installed an RPM. The following is a representative
API 36 baseline, not a requirement to install every Android platform:

```bash
sdkmanager --sdk_root="$ANDROID_HOME" \
  "platform-tools" "emulator" "platforms;android-36" \
  "build-tools;36.0.0" "ndk;28.2.13676358"
flutter config --android-sdk "$ANDROID_HOME"
flutter config --jdk-dir "$JAVA_HOME"
flutter doctor --android-licenses
flutter doctor -v
```

Accept licenses interactively. Choose `compileSdk`, build-tools, NDK and Java
versions from your project's Android configuration. The inspected workstation
also has platforms `android-34`, `android-35`, `android-37.0` and build-tools
`35.0.0`; install these only when needed. Google's `platform-tools` and `emulator`
package names follow the current release, so record their installed revisions
after setup. See the official [sdkmanager reference](https://developer.android.com/tools/sdkmanager).

For an optional x86_64 emulator:

```bash
sdkmanager "system-images;android-36;google_apis;x86_64"
avdmanager create avd --name dev_api36 --package "system-images;android-36;google_apis;x86_64"
emulator -accel-check
emulator -avd dev_api36
```

Enable CPU virtualization and usable KVM access before expecting accelerated
emulation. A physical Android device with USB debugging is also sufficient.
Use `adb devices` and `flutter devices` to verify the chosen target. Linux cannot
perform an iOS/Xcode build; use a macOS build host for that target.

For Linux desktop Flutter builds, also install `gtk3-devel` and `libstdc++-devel`
alongside the base compiler/CMake/Ninja packages, then check `flutter doctor -v`.

### Android display apps

Install the matching architecture's upstream
[scrcpy Linux release](https://github.com/Genymobile/scrcpy/blob/master/doc/linux.md),
extract it into a user-owned application directory, and add that directory to
`PATH`. Keep its bundled files together. Optionally download the Linux AppImage
from [Scrcpy GUI releases](https://github.com/pizi-0/flutter-scrcpygui/releases),
make it executable, and select that scrcpy executable and the SDK's `adb` in its
settings. Authorize USB debugging on your device. Check `scrcpy --version`; when
multiple devices exist, select a specific serial with `scrcpy -s SERIAL`.

## 4. Laravel, PHP, and frontend tooling

Install [mise](https://mise.jdx.dev/installing-mise.html) and enable its shell
activation using the instructions for your shell (Bash: `eval "$(mise activate bash)"`).
The installed [vfox-php plugin](https://github.com/jdx/vfox-php) compiles PHP and
installs Composer. Its Fedora build dependencies, with database headers, are:

```bash
sudo dnf install autoconf bison re2c libxml2-devel openssl-devel libicu-devel \
  libzip-devel oniguruma-devel libcurl-devel libpng-devel libjpeg-turbo-devel \
  freetype-devel libwebp-devel gmp-devel libsodium-devel readline-devel \
  bzip2-devel zlib-devel sqlite-devel libpq-devel
mise install php@8.3.33
```

In the application directory, use an existing `mise.toml` if provided; otherwise
select the PHP release required by `composer.json` (8.3.33 is the snapshot example):

```bash
mise use php@8.3.33
mise exec php@8.3.33 -- php --version
mise exec php@8.3.33 -- composer --version
```

`mise use` creates or updates project configuration; review it before committing.
The plugin's Composer version can change independently. Pin Composer in the
project's build instructions when an exact reproduction requires it. Keep legacy
PHP in a separate runtime/container rather than downgrading all projects.

For the observed Node major:

```bash
sudo dnf install nodejs22 nodejs22-npm
node --version
npm --version
```

DNF installs the available patch release. Use a version manager when the project
requires an exact Node pin or multiple majors. Respect `engines`, `packageManager`,
and lockfiles; install pnpm/yarn only at the version specified by the project.

Inside a trusted Laravel checkout, with mise active:

```bash
composer install
composer check-platform-reqs
php artisan --version
npm ci
```

Run `npm ci` only where `package-lock.json` exists. Configure a local `.env` and
database per the project's README, then use its test/build commands (commonly
`php artisan test` and `npm run build`). For a new disposable local environment,
`php artisan key:generate` and `php artisan serve --host=127.0.0.1` provide the
basic app key and dev server. Preserve an existing environment's key and run
migrations only against the intended local database. See
[Laravel installation](https://laravel.com/docs/12.x/installation).

## 5. Containers and database apps

```bash
sudo dnf install podman flatpak
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub io.podman_desktop.PodmanDesktop
podman --version
podman info
```

Use [Podman Desktop's Linux setup](https://podman-desktop.io/docs/installation/linux-install)
to connect the UI to the local engine. These steps do not install a Compose
provider. Follow a project's container runtime instructions; if it explicitly
requires Docker Engine/Compose, use the
[official Fedora Docker guide](https://docs.docker.com/engine/install/fedora/)
and validate that stack separately. Do not assume substituting `podman` is enough.

Install [Tabularis](https://tabularis.dev/wiki/installation) from its Linux
release, make the AppImage executable, and create your own database connections.
The observed 0.22.0 launcher uses an app-local fontconfig exclusion for Fedora
44's `Noto-COLRv1.ttf` to avoid a WebKit/Skia crash. If that same version crashes,
use an updated compatible release or an app-scoped workaround; do not change the
desktop's font configuration globally. The saved connections are not portable
setup material.

MariaDB and SQLite are installed on the source host, but a database server is
optional. Prefer the database/version declared by the project and its container
configuration; installing a GUI does not install a server or restore data.
For a host server, Fedora provides `mariadb-server`/`mariadb`; SQLite uses `sqlite`.
Initialize and configure only your own development database.

Supabase projects can use the
[official CLI setup](https://supabase.com/docs/guides/local-development/cli/getting-started).
For example, add `supabase@2.116.0` as an exact project dev dependency and run
`npx supabase --version`. Its local stack also needs a compatible container
runtime; CLI presence alone is not a successful local-start check. Firebase and
other cloud CLIs should likewise be pinned only where a project uses them.

## 6. Python, Rust, and other work

Use a per-project environment with Fedora Python:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

For projects with `uv.lock`, install [uv](https://docs.astral.sh/uv/getting-started/installation/)
and use `uv sync --frozen` with the project's Python pin instead. Do not copy
another machine's virtual environments. For Rust, install
[rustup](https://rustup.rs/), honor `rust-toolchain.toml`, and run the project's
checks, normally `cargo test --locked`. Native dependencies remain project-specific.

Community Codex is the entry point for this workflow; other assistants and local
model servers are optional. No particular model, Aeris service, storage mount,
dashboard, RGB/cooling rule, window layout, or production server configuration is
required by this development guide.

## Reproduction checklist

- Record tool versions, architecture, SDK download checksums and editor extensions.
- Reopen a terminal and VS Code; confirm both resolve the intended SDKs/runtimes.
- Flutter: run `flutter doctor -v`, `flutter pub get`, `flutter analyze`,
  `flutter test`, and one project debug build, selecting the required flavor/target.
- Laravel: install from `composer.lock`, pass `composer check-platform-reqs`, and
  run tests against the local test database. Build frontend assets from its lockfile.
- Containers: start the project's documented stack and verify its health checks;
  record the runtime and Compose provider actually used.
- Database GUI/device tools: connect to a disposable local database and an
  explicitly selected test device, using your own credentials.
- Recreate caches (`node_modules`, `vendor`, `.dart_tool`, Gradle, virtualenvs)
  from source. Preserve source, lockfiles and project configuration in Git;
  restore secrets and non-reproducible data separately.

Version probes and existing repository tests were run on the source workstation.
Clean-install testing, application-specific Laravel/Flutter builds, device setup,
and database/container provisioning remain acceptance steps for the reader.
