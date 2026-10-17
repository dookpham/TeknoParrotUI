# Development handoff

## Source and fix

This branch starts from official TeknoParrotUI commit `547789ced2db220737efd5327ddab8502a460d41` and fixes RawInput button configuration after first-launch policy acceptance.

The first policy dialog could remain WPF's implicit MainWindow and Windows[0] after being hidden. Clicking a binding such as Jurassic Park's Coin then threw `InvalidOperationException: The specified Visual is not an ancestor of this Visual` in JoystickControl.KeepCursorInTextBox. Input hooks and focus lookup could also target the hidden window.

The fix assigns the visible MainWindow explicitly, calculates cursor bounds from the textbox's own screen coordinates, and uses the focused control's actual focus scope for RawInput capture.

## Build on another Windows computer

Install Visual Studio 2022 with the .NET desktop development workload and .NET Framework 4.6.1/4.6.2 targeting packs. The UI targets .NET Framework 4.6.2, C# 9, x86; the Common project targets .NET Framework 4.6.1. Preserve the package versions in packages.config.

From the checkout, run PowerShell:

```powershell
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (!$msbuild) { throw 'Visual Studio full-framework MSBuild was not found.' }

# Use an explicit restore feed without changing global NuGet settings.
$nugetConfig = Join-Path $env:TEMP 'TeknoParrotUI-development-NuGet.Config'
'<configuration><packageSources><clear /><add key="nuget.org" value="https://api.nuget.org/v3/index.json" /></packageSources></configuration>' | Set-Content $nugetConfig

& $msbuild .\TeknoParrotUI.sln -restore -p:RestorePackagesConfig=true `
  "-p:RestoreConfigFile=$nugetConfig" -p:Configuration=Debug -p:Platform=x86 -m
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }

Start-Process .\bin\x86\Debug\TeknoParrotUi.exe `
  -WorkingDirectory (Resolve-Path .\bin\x86\Debug) -WindowStyle Normal
```

Keep the complete generated runtime directory, including libs and libs/CefSharp. Accept the application's policies yourself. Account login and game scanning are optional for this development workflow.

The source hardcodes AssemblyVersion and AssemblyFileVersion to `1.0.0.0`; that is the displayed version for a local build. It does not identify the corresponding numbered packaged UI release. Identify this build by its Git commit and branch. The native loader has a separate version.

## Runtime packages

Building the UI does not install game loaders. Terminator Salvation and Jurassic Park select **ElfLdr2 (32 bit)**. Obtain native packages from the official releases; install them inside `bin\x86\Debug`:

| Package tested during setup | Official release | Destination |
| --- | --- | --- |
| TeknoParrotElfLdr2 1.0.0.1472 | https://github.com/teknogods/TeknoParrot/releases/tag/TeknoParrotElfLdr2 | Extract the complete archive into ElfLdr2 |
| SegaApi 0.0.0.0 | https://github.com/teknogods/TeknoParrot/releases/tag/SegaApi | Copy SegaApi.dll into TeknoParrot and ElfLdr2/libs |

The complete ElfLdr2 package includes BudgieLoader.exe, MSYS DLLs, native TeknoParrot.dll, env and supporting libraries. For the tested package, `ElfLdr2/.version` should contain `1.0.0.1472`, matching the UI updater's manual version tracking. Refresh/restart the UI to refresh About's component inventory. Preserve this branch's source-built UI executable when obtaining runtime components.

The tested release assets had these SHA256 digests (verify current release metadata when downloading, as release assets may change):

- TeknoParrotElfLdr2Core_1.0.0.1472.zip: `ff03c1b62e9020d1ab9af591377da6233ff270ba01944659d163784ecead4a8a`
- SegaApi_0.0.0.0.zip: `fbb8fc5262c4fd0ddbfaa6e344bb001a81c540875909deb0e7757762f70d744d`

On the setup computer, Windows VC++ and DirectX dependencies were already installed. Check actual runtime failures on the next computer before installing additional system prerequisites.

The native DLL can reject environments with an active Windows hypervisor, including virtualization-based security/Credential Guard on physical hardware. Obtain administrator guidance for managed computers; this branch does not change Windows security or bypass the native loader's checks.

## Settings and game files

Game files, runtime binaries, account data, machine diagnostics and saved control profiles are not included in this source branch. Transfer your own game files and settings separately. For testing, create writable game copies and configure the profiles against those copies; preserve the originals. ParrotData.xml and UserProfiles live in the UI runtime directory.

The UI writes `teknoparrot.ini` into the configured game directory before starting ElfLdr2. Check write permissions and read-only attributes if configuration fails. ElfLdr2 runs with the game directory as its working directory. Enable the supported ElfLdr2 Log To File setting first when investigating game startup; the public UI does not establish a fixed loader-log filename.

The UI's asynchronous stdout reader excludes ElfLdr2. Record supported loader logs, process lifetime and exit codes together. The corresponding native loader implementation is not in this UI repository.

## Verification

Run the portable regression test:

```powershell
powershell.exe -NoProfile -File .\Tests\RawInputFocus\Regression.ps1
```

The test compares the actual baseline and fixed methods using WPF windows, including a hidden policy window and negative screen coordinates. Its ClipCursor stub records bounds without clipping the user's cursor; it launches no game.

Interactive verification completed during setup: Jurassic Park Controller Setup opened, Coin captured a temporary F6 input, and Save settings persisted the binding without crashing. The temporary test settings were restored afterward. Library, Settings and About were responsive. Full game startup was not verified: the managed setup computer's native loader rejected its virtualization environment.
