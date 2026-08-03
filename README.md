<br/>

<h3 align="center">ConnectForPowerBI</h3>

<p align="center">
  <img src="https://github.com/BOC-Group/ConnectForPowerBI/assets/28571214/8dd02229-6131-433a-a3c4-1d8e04358d89" alt="ADOIT logo" width="45%">
  <img src="https://raw.githubusercontent.com/wiki/BOC-Group/ConnectForPowerBI/images/ci/2021.11.08%20-%20ADONIS%20Connect%20for%20Power%20BI%20Thumb.png" alt="ADONIS logo" width="45%">
</p>

<p align="center">
  A Power BI custom connector for ADONIS and ADOIT.
  <br/>
  <br/>
  <a href="https://github.com/BOC-Group/ConnectForPowerBI/wiki/"><strong>Explore the docs »</strong></a>
</p>

# ConnectForPowerBI

ConnectForPowerBI makes ADONIS and ADOIT data available in Power BI through a custom connector. It allows report authors to build and refresh their own dashboards while working flexibly with repository data.

For installation, OAuth configuration, and usage instructions, see the [project wiki](https://github.com/BOC-Group/ConnectForPowerBI/wiki/).

## Build

### Portable PowerShell build

The repository includes a packaging script that works with Windows PowerShell 5.1 or PowerShell 7 and requires no .NET SDK:

```powershell
./build.ps1
```

If the local execution policy blocks scripts, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./build.ps1
```

The build produces:

```text
dist/BOCADONISADOITConnector.mez
dist/BOCADONISADOITConnector.mez.sha256
```

The script reads the `MezContent` entries from `BOCADONISADOITConnector.proj`, rejects missing or unsafe paths, packages only those files, verifies the archive contents, and writes a SHA-256 checksum.

To write the package elsewhere:

```powershell
./build.ps1 -OutputDirectory C:\Build\ConnectForPowerBI
```

### Power Query SDK build

For connector development and interactive query testing:

1. Install [Visual Studio Code](https://code.visualstudio.com/) and Microsoft's [Power Query SDK](https://marketplace.visualstudio.com/items?itemName=PowerQuery.vscode-powerquery-sdk).
2. Open this repository folder in Visual Studio Code.
3. Run the Power Query SDK build command.

The SDK writes its package to `bin/AnyCPU/Debug/BOCADONISADOITConnector.mez`. The included workspace settings point the SDK at the connector and query files.
