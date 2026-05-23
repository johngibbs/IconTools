# Pester unit tests for IconTools module
$ErrorActionPreference = 'Stop'

Describe "IconTools Module" {
    BeforeAll {
        $ManifestPath = Join-Path $PSScriptRoot "../IconTools.psd1"
        
        Write-Host "Importing module from $ManifestPath..." -ForegroundColor Cyan
        Import-Module $ManifestPath -Force
    }

    Context "Module Exports" {
        It "Should export the required functions" {
            $Module = Get-Module -Name IconTools
            $Module.ExportedFunctions.Keys | Should -Contain "Get-IconResource"
            $Module.ExportedFunctions.Keys | Should -Contain "Export-IconResource"
            $Module.ExportedFunctions.Keys | Should -Contain "New-IconFile"
        }
    }

    Context "Get-IconResource" {
        It "Should scan and list icons in explorer.exe" {
            # explorer.exe is guaranteed to have icons on any standard Windows system
            $explorerPath = "C:\Windows\explorer.exe"
            if (-not (Test-Path $explorerPath)) {
                $explorerPath = "$env:SystemRoot\explorer.exe"
            }

            $Icons = Get-IconResource -Path $explorerPath
            $Icons.Count | Should -BeGreaterThan 0
            
            $FirstIcon = $Icons[0]
            $FirstIcon.Name | Should -Not -BeNullOrEmpty
            $FirstIcon.ImageCount | Should -BeGreaterThan 0
            $FirstIcon.Sizes | Should -Not -BeNullOrEmpty
            $FirstIcon.MaxResolution | Should -Not -BeNullOrEmpty
            $FirstIcon.SourcePath | Should -Be $explorerPath
        }

        It "Should fail gracefully for files without icons" {
            # cmd.exe typically does not have standard RT_GROUP_ICON resource under Windows
            # Actually cmd.exe might have one, but a plain text file definitely won't
            $TempFile = [System.IO.Path]::GetTempFileName()
            try {
                "Hello World" | Out-File $TempFile -Force
                $Icons = Get-IconResource -Path $TempFile
                $Icons.Count | Should -Be 0
            }
            finally {
                Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Export-IconResource" {
        BeforeAll {
            $script:ExportTempDir = Join-Path $env:TEMP "IconToolsTests_$(Get-Random)"
            New-Item -ItemType Directory -Path $script:ExportTempDir -Force | Out-Null
        }

        AfterAll {
            if (Test-Path $script:ExportTempDir) {
                Remove-Item $script:ExportTempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should export icon resources as .ico files" {
            $explorerPath = "C:\Windows\explorer.exe"
            $Icons = Get-IconResource -Path $explorerPath
            # Choose the first resource
            $ResourceName = $Icons[0].Name

            $Results = Export-IconResource -Path $explorerPath -Name $ResourceName -OutputPath $script:ExportTempDir -Format Ico -PassThru -Force
            @($Results).Count | Should -Be 1
            $Results[0].Path | Should -Exist
            $Results[0].Format | Should -Be 'Ico'
            $Results[0].ResourceName | Should -Be $ResourceName
            $Results[0].SourcePath | Should -Be $explorerPath
        }

        It "Should export icon resources as PNG frames" {
            $explorerPath = "C:\Windows\explorer.exe"
            $Icons = Get-IconResource -Path $explorerPath
            # Find the resource with multiple images
            $MultiIcon = $Icons | Where-Object { $_.ImageCount -gt 1 } | Select-Object -First 1
            if (-not $MultiIcon) { $MultiIcon = $Icons[0] }

            $Results = Export-IconResource -Path $explorerPath -Name $MultiIcon.Name -OutputPath $script:ExportTempDir -Format Png -PassThru -Force
            $Results.Count | Should -BeGreaterThan 0
            foreach ($res in $Results) {
                $res.Path | Should -Exist
                $res.Format | Should -Be 'Png'
                $res.Path | Should -Match ".*_\d+x\d+\.png$"
            }
        }
    }

    Context "New-IconFile" {
        BeforeAll {
            $script:CompileTempDir = Join-Path $env:TEMP "IconToolsCompileTests_$(Get-Random)"
            New-Item -ItemType Directory -Path $script:CompileTempDir -Force | Out-Null
        }

        AfterAll {
            if (Test-Path $script:CompileTempDir) {
                Remove-Item $script:CompileTempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should compile multiple PNGs into a single .ico file" {
            $explorerPath = "C:\Windows\explorer.exe"
            $Icons = Get-IconResource -Path $explorerPath
            $MultiIcon = $Icons | Where-Object { $_.ImageCount -gt 1 } | Select-Object -First 1
            if (-not $MultiIcon) { $MultiIcon = $Icons[0] }

            # Extract PNG frames
            $ExportedPngs = Export-IconResource -Path $explorerPath -Name $MultiIcon.Name -OutputPath $script:CompileTempDir -Format Png -PassThru -Force
            $PngPaths = $ExportedPngs.Path
            $PngPaths.Count | Should -BeGreaterThan 0

            # Compile into a single ICO
            $OutputIco = Join-Path $script:CompileTempDir "reconstructed_icon.ico"
            New-IconFile -Path $PngPaths -OutputPath $OutputIco -Force

            # Verify
            $OutputIco | Should -Exist
            (Get-Item $OutputIco).Length | Should -BeGreaterThan 0

            # Verify it's a valid ICO by checking if we can load it (e.g. read stream, or just verify file properties)
            # Since it's a standalone file, we can't load it with Get-IconResource (which reads PE resources).
            # But we can check that it starts with the correct ICO signature (00 00 01 00)
            $Bytes = [System.IO.File]::ReadAllBytes($OutputIco)
            $Bytes[0] | Should -Be 0
            $Bytes[1] | Should -Be 0
            $Bytes[2] | Should -Be 1
            $Bytes[3] | Should -Be 0
            # Verify frame count matches
            $FrameCount = [System.BitConverter]::ToUInt16($Bytes, 4)
            $FrameCount | Should -Be $PngPaths.Count
        }
    }
}
