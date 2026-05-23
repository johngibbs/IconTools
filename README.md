# IconTools

`IconTools` is a PowerShell module containing a high-performance C# class library designed to list, extract, and compile Windows Icon (`.ico`) resources from Portable Executable (PE) files (such as `.exe` and `.dll` files) without quality or resolution loss. 

It supports both **Windows PowerShell 5.1** (running on .NET Framework) and **PowerShell 7+** (running on .NET Core).

---

## Features

- 🔍 **Lossless PE Icon Listing**: Read and inspect embedded `RT_GROUP_ICON` metadata inside `.exe` and `.dll` files.
- 📦 **Lossless Reconstructive Extraction**: Directly copies and wraps the raw resource bytes (`RT_ICON`) into standard `.ico` files containing all embedded resolutions (e.g., 16x16, 32x32, 48x48, 256x256) instead of using lossy GDI-based HICON handle wrappers.
- 🖼️ **PNG Frame Export**: Unpack individual frames of an icon group to independent PNG files (using native WPF image codecs).
- 🛠️ **Multi-Resolution Compilation**: Pack a set of PNG files of varying sizes back into a single standard `.ico` file.
- 🚀 **Zero External Dependencies**: Reconstructs binary files and calls Windows APIs purely through standard P/Invoke and native framework image encoders.

---

## Directory Structure

```
IconTools/
├── IconTools.psd1       # PowerShell Module Manifest
├── IconTools.psm1       # PowerShell Script Module (Cmdlet Definitions)
├── build.ps1            # Module compilation script
├── src/
│   ├── IconTools.csproj # C# Project (multi-targeted to net48 and net6.0-windows)
│   └── IconExtractor.cs # Native API declarations and extraction logic
├── bin/                 # Compiled binaries folder (Created at build time)
└── tests/
    └── IconTools.Tests.ps1 # Pester Unit Tests
```

---

## Getting Started

### Prerequisites
- [.NET SDK](https://dotnet.microsoft.com/download) (Version 6.0+ recommended to build for both targets)
- Windows OS (required for Win32 Resource APIs and WPF codecs)

### Build the Module
To compile the C# backend assembly, run the build script in a PowerShell session:
```powershell
./build.ps1
```

### Import the Module
Once built, import the module:
```powershell
Import-Module ./IconTools.psd1 -Force
```

---

## Usage Examples

### 1. View Available Icons in a File
Enumerate all icon resources and list details like image sizes and maximum resolutions:
```powershell
Get-IconResource -Path C:\Windows\explorer.exe
```

### 2. Export Icon Resource as `.ico` (Lossless)
Export a specific icon group (by name or ID like `#101`) into a directory:
```powershell
Export-IconResource -Path C:\Windows\explorer.exe -Name "ICO_MYCOMPUTER" -OutputPath C:\temp\icons -Format Ico -Force
```

### 3. Extract Icon Frames as Independent PNGs
Unpack all resolutions inside an icon group as independent `.png` images (useful for editing):
```powershell
Export-IconResource -Path C:\Windows\explorer.exe -Name "ICO_MYCOMPUTER" -OutputPath C:\temp\png_frames -Format Png -Force
```

### 4. Pack PNG Files into a Multi-Resolution `.ico` File
Compile edited PNG frames of different sizes back into a single multi-resolution icon container:
```powershell
New-IconFile -Path C:\temp\png_frames\explorer.exe_ICO_MYCOMPUTER_*.png -OutputPath C:\temp\rebuilt_computer.ico -Force
```

---

## Running Tests
This project includes Pester unit tests. To run them, execute:
```powershell
Invoke-Pester -Path ./tests/IconTools.Tests.ps1
```
