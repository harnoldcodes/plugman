param(
    [Parameter(Mandatory=$false)]
    [string]$Url,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile,
    
    [string]$VST3_PATH = $(if ($env:VST3_PATH) { $env:VST3_PATH } else { "C:\Program Files\Common Files\VST3" }),
    [string]$CLAP_PATH = $(if ($env:CLAP_PATH) { $env:CLAP_PATH } else { "C:\Program Files\Common Files\CLAP" }),
    
    [switch]$Force
)

function Show-Usage {
    Write-Host @"
PlugMan - VST3/CLAP Plugin Manager

USAGE:
    PlugMan.ps1 -Url <GitHubRepoUrl> [-VST3_PATH <path>] [-CLAP_PATH <path>] [-Force]
    PlugMan.ps1 -ConfigFile <path> [-VST3_PATH <path>] [-CLAP_PATH <path>] [-Force]
    PlugMan.ps1 [-VST3_PATH <path>] [-CLAP_PATH <path>] [-Force]

PARAMETERS:
    -Url            GitHub repository URL (e.g., https://github.com/user/repo)
    -ConfigFile     Path to JSON config file containing URLs
    -VST3_PATH      VST3 installation directory (default: C:\Program Files\Common Files\VST3)
    -CLAP_PATH      CLAP installation directory (default: C:\Program Files\Common Files\CLAP)
    -Force          Overwrite existing plugins without prompting

EXAMPLES:
    PlugMan.ps1 -Url "https://github.com/surge-synthesizer/surge"
    PlugMan.ps1 -ConfigFile "C:\MyPlugins\config.json"
    PlugMan.ps1 -Force

CONFIG FILE FORMAT (JSON):
    {
        "urls": [
            "https://github.com/user/repo1",
            "https://github.com/user/repo2"
        ]
    }

DEFAULT CONFIG LOCATION:
    $env:USERPROFILE\.config\plugman\plugins.json

"@ -ForegroundColor Yellow
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Test-Paths {
    $errors = @()
    
    if (-not $VST3_PATH) {
        $errors += "VST3_PATH not specified. Set environment variable or use -VST3_PATH parameter."
    } elseif (-not (Test-Path $VST3_PATH)) {
        try {
            New-Item -ItemType Directory -Path $VST3_PATH -Force | Out-Null
            Write-Log "Created VST3 directory: $VST3_PATH"
        } catch {
            $errors += "Cannot create VST3_PATH directory: $VST3_PATH"
        }
    }
    
    if (-not $CLAP_PATH) {
        $errors += "CLAP_PATH not specified. Set environment variable or use -CLAP_PATH parameter."
    } elseif (-not (Test-Path $CLAP_PATH)) {
        try {
            New-Item -ItemType Directory -Path $CLAP_PATH -Force | Out-Null
            Write-Log "Created CLAP directory: $CLAP_PATH"
        } catch {
            $errors += "Cannot create CLAP_PATH directory: $CLAP_PATH"
        }
    }
    
    if ($errors.Count -gt 0) {
        foreach ($error in $errors) {
            Write-Log $error "ERROR"
        }
        exit 1
    }
}

function Get-RepoInfo {
    param([string]$RepoUrl)
    
    if ($RepoUrl -match "github\.com/([^/]+)/([^/]+)") {
        return @{
            Owner = $matches[1]
            Repo = $matches[2].TrimEnd('.git')
        }
    } else {
        throw "Invalid GitHub repository URL format"
    }
}

function Get-LatestRelease {
    param([string]$Owner, [string]$Repo)
    
    $apiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers @{
            "User-Agent" = "PlugMan/1.0"
        }
        return $response
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            throw "Repository not found or no releases available"
        } else {
            throw "Failed to fetch release information: $($_.Exception.Message)"
        }
    }
}

function Get-FileFromUrl {
    param([string]$Url, [string]$OutputPath)
    
    try {
        Write-Log "Downloading: $Url"
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UserAgent "PlugMan/1.0"
        Write-Log "Downloaded to: $OutputPath"
        return $true
    } catch {
        Write-Log "Failed to download $Url`: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Expand-ZipFile {
    param([string]$ZipPath, [string]$ExtractPath)
    
    try {
        Write-Log "Extracting: $ZipPath"
        if (Test-Path $ExtractPath) {
            Remove-Item $ExtractPath -Recurse -Force
        }
        Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force
        Write-Log "Extracted to: $ExtractPath"
        return $true
    } catch {
        Write-Log "Failed to extract $ZipPath`: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Install-Plugin {
    param([string]$SourcePath, [string]$DestinationPath, [string]$PluginType, [bool]$Force = $false)
    
    try {
        if (Test-Path $DestinationPath) {
            $pluginName = Split-Path $DestinationPath -Leaf
            Write-Log "Plugin already exists: $pluginName" "WARNING"
            
            if (-not $Force) {
                do {
                    $response = Read-Host "Overwrite existing $PluginType plugin '$pluginName'? (y/n)"
                    $response = $response.ToLower()
                } while ($response -ne 'y' -and $response -ne 'n' -and $response -ne 'yes' -and $response -ne 'no')
                
                if ($response -eq 'n' -or $response -eq 'no') {
                    Write-Log "Skipping installation of $PluginType plugin: $pluginName" "INFO"
                    return $true
                }
            } else {
                Write-Log "Force flag specified, overwriting without prompt" "INFO"
            }
            
            Write-Log "Removing existing $PluginType plugin: $DestinationPath"
            Remove-Item $DestinationPath -Recurse -Force
        }
        
        Copy-Item $SourcePath $DestinationPath -Recurse -Force
        Write-Log "Installed $PluginType plugin: $DestinationPath" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to install $PluginType plugin: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Read-PluginConfig {
    param([string]$ConfigPath)
    
    try {
        if (-not (Test-Path $ConfigPath)) {
            throw "Config file not found: $ConfigPath"
        }
        
        $jsonContent = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        
        if (-not $jsonContent.urls) {
            throw "No 'urls' property found in config file"
        }
        
        $urls = @($jsonContent.urls)
        
        if ($urls.Count -eq 0) {
            throw "No URLs found in config file"
        }
        
        Write-Log "Found $($urls.Count) URLs in config file"
        return $urls
        
    } catch {
        throw "Failed to read config file: $($_.Exception.Message)"
    }
}

function Find-PluginsInDirectory {
    param([string]$Directory)
    
    $plugins = @{
        VST3 = @()
        CLAP = @()
    }
    
    Get-ChildItem -Path $Directory -Recurse -File | ForEach-Object {
        if ($_.Extension -eq ".vst3") {
            $plugins.VST3 += $_.FullName
        } elseif ($_.Extension -eq ".clap") {
            $plugins.CLAP += $_.FullName
        }
    }
    
    return $plugins
}

# Parameter validation
if ($Url -and $ConfigFile) {
    Write-Host "ERROR: Cannot specify both -Url and -ConfigFile parameters. Use only one." -ForegroundColor Red
    Show-Usage
    exit 1
}

Write-Log "PlugMan - VST3/CLAP Plugin Manager"

# Determine URLs to process
$urlsToProcess = @()

try {
    if ($Url) {
        Write-Log "Processing single URL: $Url"
        $urlsToProcess = @($Url)
    } elseif ($ConfigFile) {
        Write-Log "Reading URLs from config file: $ConfigFile"
        $urlsToProcess = Read-PluginConfig -ConfigPath $ConfigFile
    } else {
        # Default config file path
        $defaultConfigPath = Join-Path $env:USERPROFILE ".config\plugman\plugins.json"
        Write-Log "No URL or ConfigFile specified, checking default config: $defaultConfigPath"
        
        if (Test-Path $defaultConfigPath) {
            $urlsToProcess = Read-PluginConfig -ConfigPath $defaultConfigPath
        } else {
            Write-Host "`nNo URL specified and no default config file found." -ForegroundColor Red
            Write-Host "Please either:" -ForegroundColor Yellow
            Write-Host "  1. Provide a URL: PlugMan.ps1 -Url 'https://github.com/user/repo'" -ForegroundColor Yellow
            Write-Host "  2. Create a config file at: $defaultConfigPath" -ForegroundColor Yellow
            Write-Host ""
            Show-Usage
            exit 1
        }
    }
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Show-Usage
    exit 1
}

Test-Paths

try {
    foreach ($currentUrl in $urlsToProcess) {
        Write-Log "Processing repository: $currentUrl"
        
        $repoInfo = Get-RepoInfo -RepoUrl $currentUrl
        Write-Log "Repository: $($repoInfo.Owner)/$($repoInfo.Repo)"
        
        $release = Get-LatestRelease -Owner $repoInfo.Owner -Repo $repoInfo.Repo
        Write-Log "Latest release: $($release.tag_name) - $($release.name)"
        
        $tempDir = Join-Path $env:TEMP "PlugMan_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        $vst3Found = $false
        $clapFound = $false
    
        foreach ($asset in $release.assets) {
            Write-Log "Found asset: $($asset.name)"
            
            if ($asset.name -like "*.vst3") {
                $downloadPath = Join-Path $tempDir $asset.name
                if (Get-FileFromUrl -Url $asset.browser_download_url -OutputPath $downloadPath) {
                    $destinationPath = Join-Path $VST3_PATH $asset.name
                    Install-Plugin -SourcePath $downloadPath -DestinationPath $destinationPath -PluginType "VST3" -Force $Force
                    $vst3Found = $true
                }
            } elseif ($asset.name -like "*.clap") {
                $downloadPath = Join-Path $tempDir $asset.name
                if (Get-FileFromUrl -Url $asset.browser_download_url -OutputPath $downloadPath) {
                    $destinationPath = Join-Path $CLAP_PATH $asset.name
                    Install-Plugin -SourcePath $downloadPath -DestinationPath $destinationPath -PluginType "CLAP" -Force $Force
                    $clapFound = $true
                }
            }
        }
    
        if (-not $vst3Found -and -not $clapFound) {
            Write-Log "No direct VST3/CLAP files found. Looking for ZIP files with 'win' in name..."
            
            $winZips = $release.assets | Where-Object { $_.name -like "*.zip" -and $_.name -like "*win*" }
            
            if ($winZips.Count -eq 0) {
                Write-Log "No ZIP files with 'win' in name found for $currentUrl" "ERROR"
                continue
            }
            
            foreach ($zipAsset in $winZips) {
                Write-Log "Processing ZIP file: $($zipAsset.name)"
                
                $zipPath = Join-Path $tempDir $zipAsset.name
                $extractPath = Join-Path $tempDir "extracted_$($zipAsset.name -replace '\.zip$', '')"
                
                if (Get-FileFromUrl -Url $zipAsset.browser_download_url -OutputPath $zipPath) {
                    if (Expand-ZipFile -ZipPath $zipPath -ExtractPath $extractPath) {
                        $plugins = Find-PluginsInDirectory -Directory $extractPath
                        
                        foreach ($vst3Plugin in $plugins.VST3) {
                            $pluginName = Split-Path $vst3Plugin -Leaf
                            $destinationPath = Join-Path $VST3_PATH $pluginName
                            Install-Plugin -SourcePath $vst3Plugin -DestinationPath $destinationPath -PluginType "VST3" -Force $Force
                            $vst3Found = $true
                        }
                        
                        foreach ($clapPlugin in $plugins.CLAP) {
                            $pluginName = Split-Path $clapPlugin -Leaf
                            $destinationPath = Join-Path $CLAP_PATH $pluginName
                            Install-Plugin -SourcePath $clapPlugin -DestinationPath $destinationPath -PluginType "CLAP" -Force $Force
                            $clapFound = $true
                        }
                    }
                }
            }
        }
    
        if ($vst3Found -or $clapFound) {
            Write-Log "Plugin installation completed for $currentUrl!" "SUCCESS"
            if ($vst3Found) { Write-Log "VST3 plugins installed to: $VST3_PATH" }
            if ($clapFound) { Write-Log "CLAP plugins installed to: $CLAP_PATH" }
        } else {
            Write-Log "No VST3 or CLAP plugins found for $currentUrl" "ERROR"
        }
        
        # Clean up temp directory for this repository
        if ($tempDir -and (Test-Path $tempDir)) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Log "All repositories processed successfully!" "SUCCESS"
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" "ERROR"
    exit 1
}